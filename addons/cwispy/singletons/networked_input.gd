extends Node


const MAX_INPUT_BUFFER_SIZE = 10

var _input_buffer: Dictionary[int, Array]
var _target_input_time := -1
var _target_player_id := -1

var collect_input_function: Callable = func():
	return {"movement": Input.get_vector("left", "right", "up", "down"), "mouse": get_tree().root.get_node("/root/Main/Game").get_global_mouse_position()}


var _client_unacknowledged_inputs: Array[Dictionary]


func _get_inputs(tick: int) -> Dictionary:
	var out := {"time": tick}
	out.merge(collect_input_function.call())
	return out


func _ready() -> void:
	NetworkTime.before_tick.connect(_pre_tick)
	NetworkTime.after_tick.connect(_post_tick)


func _pre_tick(_delta: float, tick: int) -> void:
	if Multiplayer.is_client():
		_broadcast_and_save_inputs(tick)


func _post_tick(_delta: float, _tick: int) -> void:
	pass


## Reads the player input into a dictionary.
## Adds the player input into unacknowledged inputs buffer
## Send all unacknowledged inputs to server
## Add input to own buffer for blobs to use etc.
func _broadcast_and_save_inputs(tick: int) -> void:
	var inputs := _get_inputs(tick)
	_client_unacknowledged_inputs.push_front(inputs)
	_server_receive_unacknowledged_inputs.rpc_id(1, _client_unacknowledged_inputs)
	_add_inputs_to_buffer(inputs, multiplayer.get_unique_id())


## Receive array of inputs from client
## Put these into the input buffer for blobs to use etc.
## Tell client to no longer send the received inputs
@rpc("any_peer", "unreliable")
func _server_receive_unacknowledged_inputs(unacknowledged_inputs: Array) -> void:
	# TODO add input sanitation (i.e. don't crash the server)
	var player_id := multiplayer.get_remote_sender_id()
	var acknowledged_input_timestamps: Array[int]
	for input in unacknowledged_inputs:
		acknowledged_input_timestamps.push_back(input["time"] as int)
		_add_inputs_to_buffer(input, player_id)

	_client_receive_acknowledged_inputs.rpc_id(player_id, acknowledged_input_timestamps)


## Stop sending client inputs that have been received by the server
@rpc("authority", "unreliable")
func _client_receive_acknowledged_inputs(acknowledged_input_timestamps: Array[int]) -> void:
	_client_unacknowledged_inputs = _client_unacknowledged_inputs.filter(
		func(input: Dictionary): input["time"] not in acknowledged_input_timestamps
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
		var i_timestamp := inputs["time"] as int
		if i_timestamp <= _target_input_time:
			assert(inputs.has(input_name), "Invalid input name " + str(input_name))
			return inputs[input_name]

	# TODO fix this bandaid where sometimes the client deletes their own input and can't find it, def something to do with needing rollback for high ping (therefore needing old inputs), even though they've been acknowledged? idk
	if Multiplayer.is_client():
		return _get_inputs(_target_input_time)[input_name]

	push_error("Trying to get an out of date input! For player " + str(_target_player_id) + " their oldest input is tick " + str(_input_buffer[_target_player_id].back()["time"]) + " but you are requesting tick " + str(_target_input_time))
	return


func set_target(new_target_id: int) -> void:
	_target_player_id = new_target_id


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
