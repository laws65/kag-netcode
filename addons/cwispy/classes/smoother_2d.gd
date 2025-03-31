extends Node
class_name Smoother2D

@export var authority: Node2D
@export var targets: Array[Node2D]
@export var enabled: bool = true
@onready var offsets: Dictionary[Node2D, Vector2] = _get_initial_offsets()

var last_tick_time := 0.0
var next_tick_time := 3.0
var old_position := Vector2.ZERO
var new_position := Vector2.ZERO


func _ready() -> void:
	Synchroniser.after_tick.connect(_post_tick)


func _process(_delta: float) -> void:
	if not enabled: return
	if Multiplayer.is_server():
		queue_free()
		return

	var current_time := Time.get_unix_time_from_system()

	var interpolation_delta: float = (current_time-last_tick_time) / (next_tick_time-last_tick_time)
	for target in targets:
		target.global_position = old_position.lerp(new_position, interpolation_delta) + offsets[target]


func _get_initial_offsets() -> Dictionary[Node2D, Vector2]:
	var out: Dictionary[Node2D, Vector2]

	for target in targets:
		out[target] = target.position

	return out


func _post_tick() -> void:
	last_tick_time = Time.get_unix_time_from_system()
	next_tick_time = last_tick_time + NetworkTime.ticktime
	if authority != null:
		old_position = new_position
		new_position = authority.position
