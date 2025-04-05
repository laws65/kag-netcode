extends Node
class_name Player

signal blob_id_changed(old_id: int, new_id: int)

var _username: String
var _blob_id := -1


func _init(data: Array) -> void:
	name = str(data[0])
	_username = data[1]


func serialise() -> Array:
	return [int(str(name)), _username]


func get_id() -> int:
	return int(str(name))


func is_me() -> bool:
	return get_id() == multiplayer.get_unique_id()


func server_set_blob_id(blob_id: int) -> void:
	assert(Multiplayer.is_server())
	_set_blob_id.rpc_id(0, blob_id)


func server_set_blob(blob: Blob) -> void:
	assert(Multiplayer.is_server())
	assert(is_instance_valid(blob))
	_set_blob_id.rpc_id(0, blob.get_id())


@rpc("call_local", "reliable")
func _set_blob_id(blob_id: int) -> void:
	set_blob_id(blob_id)
	var blob := Blob.get_blob_by_id(blob_id)
	if blob != null:
		blob.set_player_id(get_id())


func set_blob_id(blob_id: int) -> void:
	var old_id := _blob_id
	_blob_id = blob_id
	blob_id_changed.emit(old_id, blob_id)


######################
## Helper functions ##
######################
static func get_players() -> Array:
	return Multiplayer.get_players_parent().get_children()


static func get_player_by_id(player_id: int) -> Player:
	return Multiplayer.get_players_parent().get_node_or_null(str(player_id))


static func player_exists(player_id: int) -> bool:
	return Multiplayer.get_players_parent().has_node(str(player_id))


static func is_valid_player(player: Player) -> bool:
	return player and player.get_id() > 0


func has_blob() -> bool:
	return _blob_id != -1


func get_rtt_msecs() -> int:
	return Clock.player_rtt.get(get_id(), 0.0) * 1000


func get_blob() -> Blob:
	if not has_blob():
		return null
	return Blob.get_blob_by_id(_blob_id)


func get_blob_id() -> int:
	return _blob_id
