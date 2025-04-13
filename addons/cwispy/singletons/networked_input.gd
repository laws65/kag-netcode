extends Node
class_name _NetworkedInput

const MAX_INPUT_BUFFER_SIZE = 10

var _input_buffer: Dictionary[int, Array]
var _target_input_time := -1
var _target_player_id := -1

var _client_unacknowledged_serialised_inputs: Array[PackedByteArray]

#region Implementation details
func _get_inputs(tick: int) -> Dictionary:
	push_error("Unimplemented!")
	return {}


func _get_serialised_inputs(inputs: Dictionary) -> PackedByteArray:
	push_error("Unimplemented!")
	return PackedByteArray()


func _get_deserialised_inputs(bytes: PackedByteArray) -> Dictionary:
	push_error("Unimplemented!")
	return {}


func _get_predicted_input(player_id: int, tick: int) -> Dictionary:
	push_error("Unimplemented!")
	return {}
#endregion


func _ready() -> void:
	NetworkTime.before_tick.connect(
		func (_delta: float, tick: int):
			if Multiplayer.is_client():
				_broadcast_and_save_inputs(tick)
	)
	Multiplayer.player_left.connect(
		func(player: Player):
			_input_buffer.erase(player.get_id())
	)


## Reads the player input into bytes
## Adds the player input into unacknowledged inputs buffer
## Send all unacknowledged inputs to server
## Add input to own buffer for blobs to use etc.
func _broadcast_and_save_inputs(tick: int) -> void:
	var inputs := _get_inputs(tick)
	var serialised_inputs := _get_serialised_inputs(inputs)
	_client_unacknowledged_serialised_inputs.push_front(serialised_inputs)
	_server_receive_unacknowledged_serialised_inputs.rpc_id(1, _client_unacknowledged_serialised_inputs)
	_add_inputs_to_buffer(inputs, multiplayer.get_unique_id())


## Receive array of inputs from client
## Put these into the input buffer for blobs to use etc.
## Tell client to no longer send the received inputs
@rpc("any_peer", "unreliable")
func _server_receive_unacknowledged_serialised_inputs(unacknowledged_serialised_inputs: Array[PackedByteArray]) -> void:
	# TODO add input sanitation (i.e. don't crash the server)
	var player_id := multiplayer.get_remote_sender_id()
	var acknowledged_input_timestamps: Array[int]
	for serialised_input in unacknowledged_serialised_inputs:
		var input := _get_deserialised_inputs(serialised_input)
		acknowledged_input_timestamps.push_back(input["time"] as int)
		_add_inputs_to_buffer(input, player_id)

	_client_receive_acknowledged_inputs.rpc_id(player_id, acknowledged_input_timestamps)


## Stop sending client inputs that have been received by the server
@rpc("authority", "unreliable")
func _client_receive_acknowledged_inputs(acknowledged_input_timestamps: Array[int]) -> void:
	_client_unacknowledged_serialised_inputs = _client_unacknowledged_serialised_inputs.filter(
		func(serialised_input: PackedByteArray):
			var time := serialised_input.decode_s32(0)
			time not in acknowledged_input_timestamps
	)


func _add_inputs_to_buffer(inputs: Dictionary, player_id: int) -> void:
	if not _input_buffer.has(player_id):
		_input_buffer[player_id] = [inputs]
		return

	for i in _input_buffer[player_id].size():
		var i_inputs: Dictionary = _input_buffer[player_id][i]
		if i_inputs.is_empty():
			# BUG figure out the cause of needing this check
			continue
		var i_timestamp := i_inputs["time"] as int
		if inputs["time"] > i_timestamp:
			_input_buffer[player_id].insert(i, inputs)
			break

		if (inputs["time"] == i_timestamp
		and (i_inputs.has("flag_predicted") or i_inputs.has("flag_temp"))):
			_input_buffer[player_id][i] = inputs
			break

		if i == _input_buffer[player_id].size() - 1:
			_input_buffer[player_id].push_back(inputs)

	if Multiplayer.is_server():
		while (_input_buffer[player_id].size() > MAX_INPUT_BUFFER_SIZE
		and not _input_buffer[player_id].is_empty()
		and _input_buffer[player_id].front()["time"] - _input_buffer[player_id].back()["time"] > Engine.get_physics_ticks_per_second()
		):
			_input_buffer[player_id].pop_back()


func get_input(input_name: String, null_ret: Variant = null) -> Variant:
	assert(_target_input_time != -1, "Target input time must be selected")
	assert(_target_player_id != -1, "Target player must be selected")

	if not _input_buffer.has(_target_player_id):
		return null_ret

	for i in _input_buffer[_target_player_id].size():
		var inputs := _input_buffer[_target_player_id][i] as Dictionary
		if inputs.is_empty():
			# TODO figure out why the inputs here are empty
			continue
		var i_timestamp := inputs["time"] as int
		if i_timestamp <= _target_input_time:
			assert(inputs.has(input_name), "Invalid input name " + str(input_name))
			return inputs[input_name]

	# TODO fix this bandaid where sometimes the client deletes their own input and can't find it, def something to do with needing rollback for high ping (therefore needing old inputs), even though they've been acknowledged? idk
	if Multiplayer.is_client():
		return _get_inputs(_target_input_time).get(input_name, null_ret)

	push_error("Trying to get an out of date input! For player " + str(_target_player_id) + " their oldest input is tick " + str(_input_buffer[_target_player_id].back()["time"]) + " but you are requesting tick " + str(_target_input_time))
	return null_ret


func set_target_player_id(target_player_id: int) -> void:
	_target_player_id = target_player_id


func set_target_player(target_player: Player) -> void:
	if Player.is_valid_player(target_player):
		set_target_player_id(target_player.get_id())


func set_time(new_time: int) -> void:
	_target_input_time = new_time


func get_inputs_for_player_at_time(player_id: int, tick: int) -> Dictionary:
	if not _input_buffer.has(player_id):
		return {}

	for i in _input_buffer[player_id].size():
		var inputs := _input_buffer[player_id][i] as Dictionary
		var i_timestamp := inputs["time"] as int
		if i_timestamp <= tick:
			return inputs

	return {}


func get_latest_input_timestamp(player_id: int) -> int:
	if _input_buffer.has(player_id):
		var arr := _input_buffer[player_id]
		if not arr.is_empty():
			return arr.front()["time"]
	return 0


func has_inputs_at_time(player_id: int, tick: int) -> bool:
	var inputs := get_inputs_for_player_at_time(player_id, tick)
	return inputs and inputs["time"] == tick


func get_predicted_input(player_id: int, tick: int) -> Dictionary:
	var predicted := _get_predicted_input(player_id, tick)
	predicted["flag_predicted"] = true
	predicted["time"] = tick
	return predicted


func add_temp_input(player_id: int, input: Dictionary) -> void:
	input["flag_temp"] = true
	_add_inputs_to_buffer(input, player_id)
