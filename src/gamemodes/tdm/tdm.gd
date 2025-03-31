extends Node


func _ready() -> void:
	Multiplayer.player_joined.connect(_on_Player_joined)
	Multiplayer.player_left.connect(_on_Player_left)


func _on_Player_joined(player: Player) -> void:
	if not Multiplayer.is_server():
		return

	var random_pos := Vector3(
		randf_range(-4, 4), 10, randf_range(-4, 4)
	)
	var params := {"position": random_pos}
	var new_blob := Multiplayer.server_spawn_blob("res://src/blobs/player_blob/player_blob.tscn", params)
	player.server_set_blob(new_blob)


func _on_Player_left(player: Player) -> void:
	if not Multiplayer.is_server():
		return
	var blob := player.get_blob()
	if blob != null:
		blob.server_kill()
