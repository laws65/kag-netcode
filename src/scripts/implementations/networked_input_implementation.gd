extends INetworkedInput


func get_inputs(tick: int) -> Dictionary:
	var out := {
		"time": tick,
		"buttons": (func():
			var button_bools := 0
			for input_name in NetworkedInput.input_names.keys():
				if Input.is_action_pressed(input_name):
					var input_code := NetworkedInput.input_names[input_name]
					button_bools += input_code
			return button_bools).call(),
		"mouse": (func():
			var vp := NetworkedInput.get_viewport()
			var screen_mouse_position := vp.get_mouse_position()
			var screen_size := vp.get_visible_rect().size
			var camera_position := vp.get_camera_2d().global_position
			return screen_mouse_position - screen_size*0.5 + camera_position).call()
	}
	return out


func get_serialised_inputs(inputs: Dictionary) -> PackedByteArray:
	var bitstream := StreamPeerBuffer.new()

	bitstream.put_32(inputs["time"])
	bitstream.put_64(inputs["buttons"])
	bitstream.put_half(inputs["mouse"].x); bitstream.put_half(inputs["mouse"].y)

	return bitstream.data_array


func get_deserialised_inputs(bytes: PackedByteArray) -> Dictionary:
	var bitstream := StreamPeerBuffer.new()
	bitstream.data_array = bytes

	var out: Dictionary

	out["time"] = bitstream.get_32()
	out["buttons"] = bitstream.get_64()
	out["mouse"] = Vector2(bitstream.get_half(), bitstream.get_half())

	return out


func get_predicted_input(player_id: int, tick: int) -> Dictionary:
	var previous_inputs := NetworkedInput.get_inputs_for_player_at_time(player_id, tick-1)
	var predicted := previous_inputs.duplicate(true)
	if predicted.is_empty():
		predicted["buttons"] = 0
		predicted["mouse"] = Vector2.ZERO

	return predicted
