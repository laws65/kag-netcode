extends Node

signal set_crouch(crouched: bool)


@export var blob: Blob

var crouch:
	set(val):
		if val != crouch:
			crouch = val
			set_crouch.emit(val)
	get:
		return crouch


func _ready() -> void:
	assert(blob)


func _on_rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	var input_crouch := NetworkedInput.is_button_pressed(&"down")
	if blob.is_on_floor():
		if not NetworkedInput.is_button_pressed(&"right") and not NetworkedInput.is_button_pressed(&"left"):
			crouch = true
		else:
			crouch = false
