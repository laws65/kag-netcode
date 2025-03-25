extends Camera3D

const SENSITIVITY = 0.005


func _ready() -> void:
	if Multiplayer.is_client():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not Multiplayer.is_client(): return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.x -= event.relative.y * SENSITIVITY
		rotation.y -= event.relative.x * SENSITIVITY


func _process(delta: float) -> void:
	if Multiplayer.is_client():
		var my_blob := Multiplayer.get_my_blob() as Blob
		if my_blob != null:
			position = my_blob.position
			current = true
