extends Node

@export var head_sprite: Sprite2D
@export var body_sprite: Sprite2D
@export var blob: Blob
@export var animation_player: AnimationPlayer


var current_animation:
	set(val):
		if animation_player.has_animation(val):
			animation_player.play(val)
	get:
		return animation_player.current_animation


func _ready() -> void:
	assert(head_sprite != null)
	assert(body_sprite != null)
	assert(blob != null)
	assert(animation_player != null)


func _on_rollback_tick(_delta: float, _tick: int, is_fresh: bool) -> void:
	if not blob.has_player():
		return

	if Multiplayer.is_client():
		if not blob.is_my_blob() and not is_fresh:
			return

	body_sprite.scale.x = 1.0
	head_sprite.scale.x = 1.0
	var i_mouse = NetworkedInput.get_input("mouse", blob.global_position)
	if i_mouse.x < blob.position.x:
		body_sprite.scale.x = -1.0
		head_sprite.scale.x = -1.0

	var new_animation: String = "idle"
	if not blob.is_on_floor():
		new_animation = "air"
	elif NetworkedInput.is_button_pressed("right") or NetworkedInput.is_button_pressed("left"):
		new_animation = "walk"

	if blob.crouched:
		new_animation = "crouch"

	var mouse_pos: Vector2 = NetworkedInput.get_input("mouse", blob.position)
	var angle_to_mouse_rad := -blob.position.angle_to_point(mouse_pos)
	if blob.shielded:
		var dir_string := Helpers.get_direction_string_from_angle(angle_to_mouse_rad)
		if NetworkedInput.is_button_pressed("right") or NetworkedInput.is_button_pressed("left"):
			if dir_string == "vertical":
				dir_string = "diagonal_up"
			if (not blob.is_on_floor() or NetworkedInput.is_button_pressed("up")) and dir_string == "diagonal_down":
				new_animation = "surf"
			else:
				new_animation = "shield_move_" + dir_string
		else:
			new_animation = "shield_static_" + dir_string
		if (not blob.is_on_floor() or NetworkedInput.is_button_pressed("up")) and (dir_string == "diagonal_up" or dir_string == "vertical"):
			new_animation = "glide"
	animation_player.play(new_animation)
