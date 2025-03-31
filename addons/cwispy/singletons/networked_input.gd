extends Node


const MAX_INPUT_BUFFER_SIZE = 10

var _input_buffer: Dictionary[int, Array]
var _target_input_time := -1
var _target_player_id := -1

var collect_input_function: Callable = func():
	return {"movement": Input.get_vector("left", "right", "up", "down"), "mouse": get_tree().root.get_node("/root/Main/Game").get_global_mouse_position()}


func _ready() -> void:
	NetworkTime.before_tick.connect(_pre_tick)


func _pre_tick(_delta: float, tick: int) -> void:
	if Multiplayer.is_client():
		_broadcast_and_save_inputs(tick)


func _broadcast_and_save_inputs(tick: int) -> void:
	var inputs := collect_input_function.call()
	_receive_client_inputs.rpc_id(1, inputs, tick)
	_add_inputs_to_buffer(inputs, tick, multiplayer.get_unique_id())


@rpc("unreliable", "any_peer")
func _receive_client_inputs(inputs: Dictionary, timestamp: int) -> void:
	var player_id := multiplayer.get_remote_sender_id()
	_add_inputs_to_buffer(inputs, timestamp, player_id)


func _add_inputs_to_buffer(inputs: Dictionary, timestamp: int, player_id: int) -> void:
	if not _input_buffer.has(player_id):
		_input_buffer[player_id] = [[inputs, timestamp]]
		return

	for i in _input_buffer[player_id].size():
		var i_timestamp := _input_buffer[player_id][i][1] as int
		if timestamp > i_timestamp:
			_input_buffer[player_id].insert(i, [inputs, timestamp])
			break

		if i == _input_buffer[player_id].size() - 1:
			_input_buffer[player_id].push_back([inputs, timestamp])

	while _input_buffer[player_id].size() > MAX_INPUT_BUFFER_SIZE:
		_input_buffer[player_id].pop_back()


func get_input(input_name: String) -> Variant:
	assert(_target_input_time != -1, "Target input time must be selected")
	assert(_target_player_id != -1, "Target player must be selected")

	if not _input_buffer.has(_target_player_id):
		return null

	for i in _input_buffer[_target_player_id].size():
		var i_timestamp := _input_buffer[_target_player_id][i][1] as int
		if i_timestamp <= _target_input_time:
			var inputs := _input_buffer[_target_player_id][i][0] as Dictionary
			assert(inputs.has(input_name), "Invalid input name " + str(input_name))
			return inputs[input_name]

	assert("Trying to get an out of date input! For player " + str(_target_player_id) + " their oldest input is tick " + str(_input_buffer[_target_player_id].back()[1]) + " but you are requesting tick " + str(_target_input_time))
	return


func set_target(new_target_id: int) -> void:
	_target_player_id = new_target_id


func set_time(new_time: int) -> void:
	_target_input_time = new_time


func get_inputs_for_player_at_time(player_id: int, tick: int) -> Dictionary:
	if not _input_buffer.has(player_id):
		return {}

	for i in _input_buffer[player_id].size():
		var i_timestamp := _input_buffer[player_id][i][1] as int
		if i_timestamp <= tick:
			var inputs := _input_buffer[player_id][i][0] as Dictionary
			return inputs

	return {}


func _remove_player_inputs(player_id: int) -> void:
	_input_buffer.erase(player_id)
