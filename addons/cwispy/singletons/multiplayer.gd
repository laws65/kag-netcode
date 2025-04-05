extends Node


signal player_joined(player: Player)
signal player_left(player: Player)

signal joined_server()
signal server_started()

signal blob_died(blob: Blob)


signal before_tick()
signal tick()
signal after_tick()

## Client vars
var _data_for_server := []

## Server vars
var unregistered_players := {}


func start_server(port: int=50301) -> void:
	var network := ENetMultiplayerPeer.new()
	var err := network.create_server(port)

	if err != OK:
		print("Failed to start server with error code " + str(err))
		return

	print("Listening on port " + str(port))
	multiplayer.set_multiplayer_peer(network)
	multiplayer.peer_connected.connect(_on_Peer_connected)
	multiplayer.peer_disconnected.connect(_on_Peer_disconnected)

	server_started.emit()


func join_server(ip: String, port: int, data_for_server: Array) -> void:
	var network := ENetMultiplayerPeer.new()
	var err := network.create_client(ip, port)
	_data_for_server = data_for_server

	if err != OK:
		print("Failed to join server with error code " + str(err))
		return

	multiplayer.set_multiplayer_peer(network)
	multiplayer.connected_to_server.connect(_on_Connected_to_server)
	multiplayer.connection_failed.connect(_on_Connection_failed)


func _on_Peer_connected(player_id: int) -> void:
	print("Peer connected with id " + str(player_id))
	unregistered_players[player_id] = []


func _on_Peer_disconnected(player_id: int) -> void:
	print("Peer disconnected with id " + str(player_id))
	if player_id in unregistered_players.keys():
		unregistered_players.erase(player_id)
	else:
		_server_remove_player_by_id.rpc(player_id)


func _on_Connected_to_server() -> void:
	print("Successfully connected to server")
	_receive_client_data.rpc_id(1, _data_for_server)


func _on_Connection_failed() -> void:
	print("Couldn't connect to server")


@rpc("any_peer", "reliable")
func _receive_client_data(client_data: Array) -> void:
	var player_id := multiplayer.get_remote_sender_id()
	client_data.push_front(player_id)
	unregistered_players[player_id] = client_data
	_receive_game_data.rpc_id(player_id, get_game_info())


@rpc("authority", "reliable")
func _receive_game_data(game_info: Array) -> void:
	var players_data := game_info[0] as Array
	var players_parent := get_players_parent()
	for player_data in players_data:
		_add_player(player_data, false)

	var blobs_data := game_info[1] as Array
	var blobs_parent := get_blobs_parent()
	for blob_data in blobs_data:
		var blob_path := blob_data["path"] as String
		blob_data.erase("path")
		var packed_scene := load(blob_path) as PackedScene
		var blob := packed_scene.instantiate() as Blob
		blob.load_spawn_data(blob_data)
		blobs_parent.add_child(blob, true)

	GameManager.load_gamemode(game_info[2])
	GameManager.load_map(game_info[3])

	_game_loading_finished.rpc_id(1)


@rpc("any_peer", "reliable")
func _game_loading_finished() -> void:
	var player_id := multiplayer.get_remote_sender_id()
	var player_data := unregistered_players[player_id] as Array
	unregistered_players.erase(player_id)
	_add_player.rpc(player_data)


@rpc("authority", "call_local", "reliable")
func _add_player(player_data: Array, is_new:bool=true) -> void:
	var player := Player.new(player_data)
	get_players_parent().add_child(player, true)

	if is_new:
		player_joined.emit(player)
	if player.is_me():
		joined_server.emit()


@rpc("call_local", "reliable")
func _server_remove_player_by_id(player_id: int) -> void:
	var player := Player.get_player_by_id(player_id)
	player.queue_free()
	get_players_parent().remove_child(player)
	player_left.emit(player)


func get_game_info() -> Array:
	var players := Player.get_players()
	var players_data := []
	for i in players.size():
		var player: Player = players[i]
		players_data.append(player.serialise())

	var blobs := Blob.get_blobs()
	var blobs_data := []
	for i in blobs.size():
		var blob: Blob = blobs[i]
		blobs_data.append(blob.get_spawn_data())
	return [players_data, blobs_data, GameManager.gamemode_path, GameManager.current_map]


func server_spawn_blob(scene_path: String, params: Dictionary={}) -> Blob:
	var packed_scene := load(scene_path) as PackedScene
	assert(packed_scene.can_instantiate())
	var new_blob := packed_scene.instantiate() as Blob
	params["id"] = new_blob.get_instance_id()
	new_blob.load_spawn_data(params)
	get_blobs_parent().add_child(new_blob, true)

	_add_blob.rpc_id(0, scene_path, params)
	return new_blob

@rpc("reliable")
func _add_blob(scene_path: String, params: Dictionary={}, old: bool=false) -> void:
	var packed_scene := load(scene_path) as PackedScene
	assert(packed_scene.can_instantiate())
	var new_blob := packed_scene.instantiate() as Blob
	new_blob.load_spawn_data(params)
	get_blobs_parent().add_child(new_blob, true)

#######################
## Helper functions ###
#######################
func get_players_parent() -> Node:
	return get_node("/root/Main/Players")


func get_blobs_parent() -> Node:
	return get_node("/root/Main/Game/Blobs")


func server_active() -> bool:
	return (multiplayer.has_multiplayer_peer()
	and multiplayer.multiplayer_peer is ENetMultiplayerPeer
	and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


func is_client() -> bool:
	if not server_active():
		return false

	return has_local_player()



func is_server() -> bool:
	return server_active() and multiplayer.is_server()


func get_my_blob() -> Blob:
	if has_local_player():
		return get_my_player().get_blob()
	return null


func get_my_blob_id() -> int:
	if has_local_player():
		return get_my_player().get_blob_id()
	return -1


func get_my_player() -> Player:
	return Player.get_player_by_id(multiplayer.get_unique_id())


func has_local_player() -> bool:
	return Player.is_valid_player(get_my_player())


func has_local_blob() -> bool:
	return Blob.is_valid_blob(get_my_blob())
