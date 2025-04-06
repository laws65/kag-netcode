extends Node


var cum_ticks := 0
@export var blob: Blob


func _ready() -> void:
	assert(blob != null, "Set the blob")



var ground_accel := 300
var air_accel := 450
var max_ground_speed := 65
var max_air_speed := 80
var ground_friction := 30
var air_friction := 8
var jump_force := 114
var shield_gravity := 200
var gravity := 520

var shield_surf_accel := 600
var initial_wall_scrape_gravity := 200
var max_wall_scrape_speed := 100
var after_wall_scrape_gravity := 10


var bounce_cooldown_time_ticks := 4
var current_bounce_cooldown = 0

var just_jumped := false

# TODO add slide cooldown for jump so that we can shield slide properly

func _on_rollback_tick(delta: float, _tick: int, is_fresh: bool = true) -> void:
	if not blob.has_player():
		return
	if Multiplayer.is_client() and is_fresh:
		return

	var _velocity = blob.velocity
	blob.velocity = Vector2.ZERO
	blob.move_and_slide()
	blob.velocity = _velocity
	cum_ticks += 1
	if cum_ticks <= 60:
		return

	if current_bounce_cooldown > 0 and blob.is_on_floor():
		current_bounce_cooldown -= 1

	var trying_to_glide := false
	var angle_to_mouse := -blob.position.angle_to_point(NetworkedInput.get_input("mouse", Vector2.ZERO))
	var shield_direction_string := Helpers.get_direction_string_from_angle(angle_to_mouse)
	if blob.shielded and (shield_direction_string == "diagonal_up" or shield_direction_string == "vertical"):
		trying_to_glide = true

	var i_buttons = NetworkedInput.get_input("buttons")
	var i_mouse = NetworkedInput.get_input("mouse")
	var mouse_pos = blob.global_position
	var direction := 0.0
	var jump_pressed := false

	if i_buttons != null:
		direction = int(NetworkedInput.is_button_pressed("right")) - int(NetworkedInput.is_button_pressed("left"))
		jump_pressed = NetworkedInput.is_button_pressed("up")
		mouse_pos = i_mouse

	var facing = 1
	if mouse_pos.x < blob.position.x:
		facing = -1
	if blob.is_on_floor():
		if sign(blob.velocity.x) == -direction:
			blob.velocity.x *= -0.5
		else:
			if blob.shielded and shield_direction_string == "diagonal_down":
				blob.velocity.x += shield_surf_accel * direction * delta
			else:
				blob.velocity.x += ground_accel * direction * delta

		if direction == 0:
			blob.velocity.x = lerp(blob.velocity.x, 0.0, ground_friction * delta)
		if direction == facing:
			blob.velocity.x = clamp(blob.velocity.x, -max_ground_speed, max_ground_speed)
		else:
			blob.velocity.x = clamp(blob.velocity.x, -max_ground_speed*0.8, max_ground_speed*0.8)
	else:
		if sign(blob.velocity.x) == -direction:
			blob.velocity.x *= -0.2
		else:
			blob.velocity.x += air_accel * direction * delta

		if direction == 0:
			blob.velocity.x = lerp(blob.velocity.x, 0.0, ground_friction * delta)
		if direction == facing:
			blob.velocity.x = clamp(blob.velocity.x, -max_air_speed, max_air_speed)
		else:
			blob.velocity.x = clamp(blob.velocity.x, -max_air_speed*0.8, max_air_speed*0.8)

	if jump_pressed and current_bounce_cooldown == 0:
		if blob.is_on_floor():
			just_jumped = true
			current_bounce_cooldown = bounce_cooldown_time_ticks
			if blob.shielded and not trying_to_glide:
				blob.velocity.y -= jump_force * 0.4
			else:
				blob.velocity.y -= jump_force

	if just_jumped and jump_pressed and blob.velocity.y < 0:
		blob.velocity.y += gravity * 0.5 * delta
	else:
		if blob.is_on_wall() and direction != 0:
			blob.velocity.y += initial_wall_scrape_gravity * delta
			blob.velocity.y = min(blob.velocity.y, max_wall_scrape_speed)
		elif trying_to_glide and blob.velocity.y > 0:
			blob.velocity.y += gravity * 0.5 * delta
		else:
			blob.velocity.y += gravity * delta

	blob.move_and_slide()

	if blob.is_on_floor():
		if just_jumped:
			blob.velocity.x *= 0.75
		just_jumped = false

	if (blob.is_on_floor()
	and not NetworkedInput.is_button_pressed("right") and not NetworkedInput.is_button_pressed("left")
	and NetworkedInput.is_button_pressed("down")):
		blob.crouched = true
	else:
		blob.crouched = false
