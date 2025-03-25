extends Blob

var asdf := 0

var ground_accel := 300
var air_accel := 450
var max_ground_speed := 65
var max_air_speed := 80
var ground_friction := 30
var air_friction := 8
var jump_force := 114
var shield_gravity := 200
var gravity := 520

var initial_wall_scrape_gravity := 200
var max_wall_scrape_speed := 100
var after_wall_scrape_gravity := 10


var bounce_cooldown_time_ticks := 4
var current_bounce_cooldown = 0

var just_jumped := false

func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not is_my_blob():
		return
	if current_bounce_cooldown > 0 and is_on_floor():
		current_bounce_cooldown -= 1
	
	var direction = Input.get_axis("left", "right")
	
	var facing = 1
	if get_global_mouse_position().x < position.x:
		facing = -1
	if is_on_floor():
		if sign(velocity.x) == -direction:
			velocity.x *= -0.5
		else:
			velocity.x += ground_accel * direction * delta
		
		if direction == 0:
			velocity.x = lerp(velocity.x, 0.0, ground_friction * delta)
		if direction == facing:
			velocity.x = clamp(velocity.x, -max_ground_speed, max_ground_speed)
		else:
			velocity.x = clamp(velocity.x, -max_ground_speed*0.8, max_ground_speed*0.8)
	else:
		if sign(velocity.x) == -direction:
			velocity.x *= -0.2
		else:
			velocity.x += air_accel * direction * delta
		
		if direction == 0:
			velocity.x = lerp(velocity.x, 0.0, ground_friction * delta)
		if direction == facing:
			velocity.x = clamp(velocity.x, -max_air_speed, max_air_speed)
		else:
			velocity.x = clamp(velocity.x, -max_air_speed*0.8, max_air_speed*0.8)


	if Input.is_action_pressed("up") and current_bounce_cooldown == 0:
		if is_on_floor():
			just_jumped = true
			current_bounce_cooldown = bounce_cooldown_time_ticks
			velocity.y -= jump_force
	
	if just_jumped and Input.is_action_pressed("up") and velocity.y < 0:
		velocity.y += gravity * 0.5 * delta
	else:
		if is_on_wall() and direction != 0:
			velocity.y += initial_wall_scrape_gravity * delta
			velocity.y = min(velocity.y, max_wall_scrape_speed)
		else:
			velocity.y += gravity * delta
			
	
	move_and_slide()
	
	if is_on_floor():
		just_jumped = false
