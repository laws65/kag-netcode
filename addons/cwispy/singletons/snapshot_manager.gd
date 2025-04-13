extends Node
## Broadcasts the world state to the clients
## Saves the history of the world state to a buffer


var _snapshots_buffer: Array[Dictionary]


func _ready() -> void:
	NetworkTime.after_tick.connect(func(_delta: float, tick: int):
		if Multiplayer.is_server():
			var snapshot := create_world_snapshot(tick)
			insert_snapshot_into_buffer(snapshot)
			broadcast_snapshot(snapshot)
	)


func create_world_snapshot(time: int) -> Dictionary:
	var output = {
		"blobs": {},
		"time": time,
		"authority": Multiplayer.is_server(),
		"latest_inputs": ServerTicker.latest_consumed_player_inputs,
	}

	var blobs := Blob.get_blobs()
	for blob in blobs as Array[Blob]:
		var blob_snapshot := blob.get_snapshot()
		output["blobs"][blob.get_id()] = blob_snapshot

	if Multiplayer.is_server():
		var player_inputs: Dictionary[int, Dictionary]
		var players := Player.get_players()
		for player in players:
			var player_id := player.get_id() as int
			var inputs = NetworkedInput.get_inputs_for_player_at_time(player_id, time)
			player_inputs[player_id] = inputs
		output["inputs"] = player_inputs

	return output


func broadcast_snapshot(snapshot: Dictionary) -> void:
	_receive_server_snapshot.rpc_id(0, snapshot)


@rpc("unreliable", "authority")
func _receive_server_snapshot(snapshot: Dictionary) -> void:
	var player_id := multiplayer.get_unique_id()
	var latest_inputs: Dictionary[int, int] = snapshot["latest_inputs"]
	if latest_inputs.has(player_id):
		ServerTicker.latest_consumed_player_inputs[player_id] = latest_inputs[player_id]
	insert_snapshot_into_buffer(snapshot)


func get_snapshots_buffer() -> Array[Dictionary]:
	return _snapshots_buffer


func insert_snapshot_into_buffer(snapshot: Dictionary) -> void:
	# TODO write algorithm to find correct index, to prevent slowdowns for large buffer sizes
	if Multiplayer.is_server() or not Synchroniser.client_prediction_enabled:
		while _snapshots_buffer.size() > 20 + 1:
			_snapshots_buffer.pop_back()
	elif ServerTicker.latest_consumed_player_inputs.has(multiplayer.get_unique_id()):
		var latest_used_input := ServerTicker.latest_consumed_player_inputs[multiplayer.get_unique_id()]
		while not _snapshots_buffer.is_empty() and _snapshots_buffer.back()["time"] < latest_used_input:
			_snapshots_buffer.pop_back()

	if _snapshots_buffer.is_empty():
		_snapshots_buffer.push_front(snapshot)
		return

	if _snapshots_buffer[0]["time"] < snapshot["time"]:
		_snapshots_buffer.push_front(snapshot)
		return

	for i in _snapshots_buffer.size():
		var i_snapshot_time := _snapshots_buffer[i]["time"] as int
		if i_snapshot_time == snapshot["time"]:
			_snapshots_buffer[i] = snapshot
			return
	for i in _snapshots_buffer.size():
		var i_snapshot_time := _snapshots_buffer[i]["time"] as int
		if snapshot["time"] > i_snapshot_time:
			_snapshots_buffer.insert(i, snapshot)
			return

	_snapshots_buffer.push_back(snapshot)


func get_snapshot_at_time(time: int) -> Dictionary:
	for snapshot in _snapshots_buffer:
		if snapshot["time"] == time:
			return snapshot

	return {}
