extends Camera2D


func _ready() -> void:
	if Multiplayer.is_client():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if Multiplayer.is_client():
		var my_blob := Multiplayer.get_my_blob() as Blob
		if my_blob != null:
			if position.distance_squared_to(my_blob.position) > 1.0:
				position = lerp(position, my_blob.position, delta*5)
