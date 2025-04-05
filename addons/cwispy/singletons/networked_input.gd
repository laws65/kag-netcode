extends Node


const MAX_INPUT_BUFFER_SIZE = 10

var _input_buffer: Dictionary[int, Array]
var _target_input_time := -1
var _target_player_id := -1


enum {
	RIGHT = 1,
	UP = 2,
	LEFT = 4,
	DOWN = 8,
}

var input_names: Dictionary[String, int] = {
	"right": RIGHT,
	"up": UP,
	"left": LEFT,
	"down": DOWN,
}

var _client_unacknowledged_serialised_inputs: Array[PackedByteArray]


func _get_inputs(tick: int) -> Dictionary:
	var get_button_inputs = func():
		var out := 0
		for input_name in input_names.keys():
			if Input.is_action_pressed(input_name):
				var input_code := input_names[input_name]
				out += input_code
		return out

	var button_inputs := get_button_inputs.call()
	var out := {
		"time": tick,
		"buttons": button_inputs,
		"mouse": get_tree().root.get_node("/root/Main/Game").get_global_mouse_position() as Vector2
	}

	return out


func _get_serialised_inputs(inputs: Dictionary) -> PackedByteArray:
	var bitstream := StreamPeerBuffer.new()

	bitstream.put_32(inputs["time"])
	bitstream.put_64(inputs["buttons"])
	bitstream.put_half(inputs["mouse"].x); bitstream.put_half(inputs["mouse"].y)

	return bitstream.data_array


func _get_deserialised_inputs(bytes: PackedByteArray) -> Dictionary:
	var bitstream := StreamPeerBuffer.new()
	bitstream.data_array = bytes

	var out: Dictionary

	out["time"] = bitstream.get_32()
	out["buttons"] = bitstream.get_64()
	out["mouse"] = Vector2(bitstream.get_half(), bitstream.get_half())

	return out


func _ready() -> void:
	NetworkTime.before_tick.connect(_pre_tick)
	NetworkTime.after_tick.connect(_post_tick)


func _pre_tick(_delta: float, tick: int) -> void:
	if Multiplayer.is_client():
		_broadcast_and_save_inputs(tick)


func _post_tick(_delta: float, _tick: int) -> void:
	pass


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
		if _input_buffer[player_id][i].is_empty():
			# BUG figure out the cause of needing this check
			continue
		var i_timestamp := _input_buffer[player_id][i]["time"] as int
		if inputs["time"] > i_timestamp:
			_input_buffer[player_id].insert(i, inputs)
			break

		if i == _input_buffer[player_id].size() - 1:
			_input_buffer[player_id].push_back(inputs)

	if Multiplayer.is_server():
		while _input_buffer[player_id].size() > MAX_INPUT_BUFFER_SIZE:
			_input_buffer[player_id].pop_back()


func get_input(input_name: String) -> Variant:
	assert(_target_input_time != -1, "Target input time must be selected")
	assert(_target_player_id != -1, "Target player must be selected")

	if not _input_buffer.has(_target_player_id):
		return null

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
		return _get_inputs(_target_input_time)[input_name]

	push_error("Trying to get an out of date input! For player " + str(_target_player_id) + " their oldest input is tick " + str(_input_buffer[_target_player_id].back()["time"]) + " but you are requesting tick " + str(_target_input_time))
	return


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


func _remove_player_inputs(player_id: int) -> void:
	_input_buffer.erase(player_id)

func get_latest_input_timestamp(player_id: int) -> int:
	if _input_buffer.has(player_id):
		var arr := _input_buffer[player_id]
		if not arr.is_empty():
			return arr.front()["time"]
	return 0


func has_input_at_time(player_id: int, tick: int) -> bool:
	if not _input_buffer.has(player_id):
		return false

	for input in _input_buffer[player_id]:
		if input["time"] == tick:
			return true


	return false

func get_collection(player_id: int) -> Array:
	return _input_buffer.get(player_id, [])


func is_button_pressed(button_name: String) -> bool:
	var buttons := get_input("buttons")

	return buttons & input_names[button_name] > 0
