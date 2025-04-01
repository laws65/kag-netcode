extends Node


const MAX_INPUT_BUFFER_SIZE = 10

var _input_buffer: Dictionary[int, Array]
var _target_input_time := -1
var _target_player_id := -1

var collect_input_function: Callable = func():
	return {"movement": Input.get_vector("left", "right", "up", "down"), "mouse": get_tree().root.get_node("/root/Main/Game").get_global_mouse_position()}

var last_acknowledged_inputs: Dictionary[int, int]


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
	if Multiplayer.is_server():
		for player_id in last_acknowledged_inputs.keys():
			_acknowledge_input.rpc_id(player_id, last_acknowledged_inputs[player_id])


@rpc("authority", "unreliable")
func _acknowledge_input(input_tick: int) -> void:
	last_acknowledged_inputs[multiplayer.get_unique_id()] = input_tick

	for i in _input_buffer[multiplayer.get_unique_id()].size():
		var size = _input_buffer[multiplayer.get_unique_id()].size()
		var input := _input_buffer[multiplayer.get_unique_id()][size-i-1] as Dictionary
		if input["time"] < input_tick and size > MAX_INPUT_BUFFER_SIZE:
			_input_buffer.erase(i)


func _broadcast_and_save_inputs(tick: int) -> void:
	var inputs := _get_inputs(tick)
	_receive_client_inputs.rpc_id(1, inputs)
	_add_inputs_to_buffer(inputs, multiplayer.get_unique_id())


@rpc("unreliable", "any_peer")
func _receive_client_inputs(inputs: Dictionary) -> void:
	#print("received input ", timestamp)
	var player_id := multiplayer.get_remote_sender_id()
	_add_inputs_to_buffer(inputs, player_id)


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
			if Multiplayer.is_server():
				last_acknowledged_inputs[_target_player_id] = i_timestamp
				#print("input ", i_timestamp, " : ", _target_input_time)
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
