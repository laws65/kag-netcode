extends BaseNetInput

var movement := Vector2.ZERO


func _gather():
	movement = Input.get_vector("left", "right", "up", "down")
