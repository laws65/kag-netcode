extends Blob

func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	velocity = net_input.movement * 100
	velocity.y += 1000 * delta
	velocity *= NetworkTime.physics_factor
	move_and_slide()
