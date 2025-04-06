extends _NetworkedInput


enum {
	RIGHT = 1,
	UP = 2,
	LEFT = 4,
	DOWN = 8,
	LMB = 16,
	RMB = 32,
}

var input_names: Dictionary[String, int] = {
	"right": RIGHT,
	"up": UP,
	"left": LEFT,
	"down": DOWN,
	"lmb": LMB,
	"rmb": RMB,
}


func _get_inputs(tick: int) -> Dictionary:
	var out := {
		"time": tick,
		"buttons": (func():
			var button_bools := 0
			for input_name in input_names.keys():
				if Input.is_action_pressed(input_name):
					var input_code := input_names[input_name]
					button_bools += input_code
			return button_bools).call(),
		"mouse": (func():
			var screen_mouse_position := get_viewport().get_mouse_position()
			var screen_size := get_viewport().get_visible_rect().size
			var camera_position := get_viewport().get_camera_2d().global_position
			return screen_mouse_position - screen_size*0.5 + camera_position).call()
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


func _get_predicted_input(player_id: int, tick: int) -> Dictionary:
	var out := get_inputs_for_player_at_time(player_id, tick)
	if out.is_empty():
		out["buttons"] = 0
		out["mouse"] = Vector2.ZERO
	out["flag_predicted"] = true
	out["time"] = tick
	return out


func is_button_pressed(button_name: String) -> bool:
	var buttons: int = get_input("buttons")

	return buttons & input_names[button_name] > 0
