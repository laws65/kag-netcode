extends Node


var input_buffer: Dictionary

var collect_input_function: Callable = func():
	return {"movement": Input.get_vector("left", "right", "up", "down")}


func _physics_process(delta: float) -> void:
	if Multiplayer.is_client():
		var input_state := collect_input_function.call()
		input_state["tick"] = NetworkTime.tick
