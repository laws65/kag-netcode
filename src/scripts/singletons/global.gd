extends Node


enum {
	RIGHT = 1,
	UP = 2,
	LEFT = 4,
	DOWN = 8,
	LMB = 16,
	RMB = 32,
}


func _ready() -> void:
	_setup_inputs()


func _setup_inputs() -> void:
	var input_implementation: INetworkedInput = preload("res://src/scripts/implementations/networked_input_implementation.gd").new()
	NetworkedInput.input_implementation = input_implementation
	NetworkedInput.register_button(&"right", RIGHT)
	NetworkedInput.register_button(&"up", UP)
	NetworkedInput.register_button(&"left", LEFT)
	NetworkedInput.register_button(&"down", DOWN)
	NetworkedInput.register_button(&"lmb", LMB)
	NetworkedInput.register_button(&"rmb", RMB)
