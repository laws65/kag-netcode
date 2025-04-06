extends CharacterBody2D
class_name Blob

signal player_id_changed(old_id: int, new_id: int)
signal rollback_tick(delta: float, tick: int, is_fresh: bool)

var _player_id := -1

@export var spawn_props: Array[String]
@export var snapshot_props: Array[String]


func _internal_rollback_tick(delta: float, tick: int, is_fresh: bool = true) -> void:
	if has_player():
		NetworkedInput.set_time(tick)
		NetworkedInput.set_target_player(get_player())
	_rollback_tick(delta, tick, is_fresh)
	rollback_tick.emit(delta, tick, is_fresh)


func _rollback_tick(delta: float, tick: int, is_fresh: bool = true) -> void:
	pass


func load_spawn_data(params: Dictionary) -> void:
	name = str(params["id"])

	for prop_name in params:
		if prop_name == "id": continue

		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		get_node(node_path).set(node_prop, params[prop_name])


func get_spawn_data() -> Dictionary:
	var spawn_data := {
		"path": scene_file_path,
		"id": get_id(),
	}

	for prop_name in spawn_props:
		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		spawn_data[prop_name] = get_node(node_path).get(node_prop)

	return spawn_data


func get_id() -> int:
	return int(str(name))


static func get_blobs() -> Array:
	return Multiplayer.get_blobs_parent().get_children() as Array


static func blob_id_exists(blob_id: int) -> bool:
	return blob_id > 0 and Multiplayer.get_blobs_parent().has_node(str(blob_id))


static func get_blob_by_id(blob_id: int) -> Blob:
	if blob_id > 0 and Multiplayer.get_blobs_parent().has_node(str(blob_id)):
		return Multiplayer.get_blobs_parent().get_node(str(blob_id)) as Blob
	return null


static func is_valid_blob(blob: Blob) -> bool:
	return blob and blob.get_id() > 0


func has_player() -> bool:
	return _player_id != -1


func is_my_blob() -> bool:
	return _player_id == multiplayer.get_unique_id()


func get_player_id() -> int:
	return _player_id


func get_player() -> Player:
	return Player.get_player_by_id(_player_id)


func server_set_player_id(player_id: int) -> void:
	assert(Multiplayer.is_server(), "Must be called on server")
	_set_player_id.rpc_id(0, player_id)


func server_set_player(player: Player) -> void:
	assert(Multiplayer.is_server(), "Must be called on server")
	_set_player_id.rpc_id(0, player.get_id())


@rpc("call_local", "reliable")
func _set_player_id(player_id: int) -> void:
	set_player_id(player_id)
	var player := Player.get_player_by_id(player_id)

	if player != null:
		player.set_blob_id(get_id())


func set_player_id(player_id: int) -> void:
	var old_id := _player_id
	_player_id = player_id

	player_id_changed.emit(old_id, player_id)


func server_kill() -> void:
	assert(Multiplayer.is_server())
	_die.rpc_id(0)


@rpc("call_local", "reliable")
func _die() -> void:
	queue_free()
	Multiplayer.blob_died.emit(self)
	get_parent().remove_child(self)


func load_snapshot(snapshot: Dictionary) -> void:
	for prop_name in snapshot.keys():
		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		get_node(node_path).set(node_prop, snapshot[prop_name])


func get_snapshot() -> Dictionary:
	var snapshot: Dictionary
	for prop_name in snapshot_props:
		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		snapshot[prop_name] = get_node(node_path).get(node_prop)

	return snapshot
