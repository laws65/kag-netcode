extends Blob


var gravity := 300
var speed := 100
var jump_force := 150


func _on_rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	if not self.has_player():
		return

	if is_fresh:
		if not Multiplayer.is_server() and not self.is_my_blob():
			return

	var move_dir_x := int(NetworkedInput.is_button_pressed("right")) - int(NetworkedInput.is_button_pressed("left"))
	var jump := is_on_floor() and NetworkedInput.is_button_pressed("up")

	velocity.y += gravity * delta
	velocity.y -= int(jump) * jump_force
	velocity.x = move_dir_x * speed

	move_and_slide()
