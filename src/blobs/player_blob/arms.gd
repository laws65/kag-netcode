extends Node


@export var blob: Blob


func _ready() -> void:
	assert(blob)


func _on_rollback_tick(_delta: float, _tick: int, is_fresh: bool) -> void:
	if not blob.has_player():
		return

	if Multiplayer.is_client():
		if not blob.is_my_blob() and not is_fresh:
			return

	if not blob.stunned and NetworkedInput.is_button_pressed(&"rmb"):
		blob.shielded = true
	else:
		blob.shielded = false
