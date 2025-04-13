extends Node


signal after_tick

var RENDER_TIME_TICK_DELAY = 1

var client_prediction_enabled := true
var remote_client_prediction_enabled := false

var _debug_syncing := true

var client_sync_exclude: Array[int] # Array of the only blob ids that won't be in _load_snapshot()
var client_sync_include: Array[int] # Array of the only blob ids that will be synced in _load_snapshot()


func _ready() -> void:
	NetworkTime.on_tick.connect(_tick)


func _tick(_delta: float, tick: int) -> void:
	if Multiplayer.is_client():
		_sync_blobs()


func _sync_blobs() -> void:
	if _debug_syncing:
		print("-----NEW TICK-----------")
	# TODO fix client side prediction code
	# TODO rewatch -> https://www.youtube.com/watch?v=W3aieHjyNvw&t=1529s&ab_channel=GameDevelopersConference

	var rtt := NetworkTime.remote_rtt * 1000
	var half_tick_rtt: int = ceil(
		# TODO rewrite this using NetworkTime.ticktime
		rtt*0.5/float((1000/float(Engine.get_physics_ticks_per_second())))
	)

	var render_tick: int = NetworkTime.tick - RENDER_TIME_TICK_DELAY - half_tick_rtt

	# try to directly load snapshot if available
	var render_snapshot := SnapshotManager.get_snapshot_at_time(render_tick)
	if render_snapshot:
		if not client_prediction_enabled:
			_load_snapshot(render_snapshot)
		else:
			var predict_from := render_tick
			var latest_used_input_tick := ServerTicker.latest_consumed_player_inputs.get(multiplayer.get_unique_id())
			if latest_used_input_tick:
				# TODO figure out if below is true \/
				# If the server missed a player's input, we'll want to predict from an older snapshot before the input was missed
				predict_from = min(predict_from, latest_used_input_tick)
			_client_side_predict_from(predict_from, NetworkTime.tick)
	else:
		_predict_tick(render_tick)

	after_tick.emit()


func _rollback_to(time: int) -> void:
	var snapshots_buffer := SnapshotManager.get_snapshots_buffer()
	for snapshot in snapshots_buffer:
		if snapshot["time"] == time:
			_load_snapshot(snapshot)
			return


func _predict_tick(render_tick: int) -> void:
	var snapshots_buffer := SnapshotManager.get_snapshots_buffer()
	print("Client: missing state snapshot for tick ", render_tick)
	# otherwise find latest snapshot and simulate until render_tick
	var recent_snapshot_before_render_tick: Dictionary = {"time":-1}
	for i in snapshots_buffer.size():
		var snapshot: Dictionary = snapshots_buffer[i]
		if (snapshot["time"] > recent_snapshot_before_render_tick["time"]
		and snapshot["time"] < render_tick
		and snapshot["authority"]):
			recent_snapshot_before_render_tick = snapshot

	if recent_snapshot_before_render_tick["time"] == -1:
		print("Couldn't even find snapshot, returning")
		return

	var ticks_to_simulate := render_tick - recent_snapshot_before_render_tick["time"] as int
	var player_inputs := recent_snapshot_before_render_tick["inputs"] as Dictionary[int, Dictionary]
	var blobs_to_simulate := recent_snapshot_before_render_tick["blobs"].keys() as Array

	while remote_client_prediction_enabled and ticks_to_simulate > 0:
		if _debug_syncing:
			print("simulating")
		var simulated_render_tick: int = render_tick - ticks_to_simulate + 1
		for blob_id in blobs_to_simulate:
			var blob := Blob.get_blob_by_id(blob_id)
			if not Blob.is_valid_blob(blob):
				# BUG figure out why this check is needed
				continue
			blob.load_snapshot(recent_snapshot_before_render_tick["blobs"][blob.get_id()])
			var has_correct_input := false

			if blob.has_player():
				if not (client_prediction_enabled and blob.is_my_blob()):
					var player_id := blob.get_player_id()
					var inputs := player_inputs[player_id]
					#print("here simulating ", simulated_render_tick, " : ", NetworkTime.tick)
					NetworkedInput.add_temp_input(player_id, inputs)
					blob._internal_rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)
			else:
				blob._internal_rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)

		if ticks_to_simulate > 1:
			var snapshot := SnapshotManager.create_world_snapshot(simulated_render_tick)
			SnapshotManager.insert_snapshot_into_buffer(snapshot)

		ticks_to_simulate -= 1

	if client_prediction_enabled:
		_client_side_predict_from(render_tick, NetworkTime.tick)


func _load_snapshot(snapshot: Dictionary) -> void:
	assert(client_sync_exclude.is_empty() or client_sync_include.is_empty(), "You fucked up")

	for blob_id in snapshot["blobs"].keys():
		if client_sync_include and blob_id not in client_sync_include: continue
		if blob_id in client_sync_exclude: continue

		if _debug_syncing:
			print("loading snapshot ", snapshot["time"])
		var blob_snapshot := snapshot["blobs"][blob_id] as Dictionary
		var blob := Blob.get_blob_by_id(blob_id)
		if Blob.is_valid_blob(blob):
			# BUG figure out why this check is needed
			blob.load_snapshot(blob_snapshot)


func _client_side_predict_from(from_tick: int, to_tick: int) -> void:
	if _debug_syncing:
		print("Client: predicting from ", from_tick, " to ", to_tick)
	assert(from_tick <= to_tick)

	if not Multiplayer.is_client(): return
	if not Multiplayer.has_local_blob(): return

	var blob := Multiplayer.get_my_blob()
	var blob_id := blob.get_id()

	# Sync client blob back to server authoritative state
	client_sync_include.push_back(blob_id)
	_rollback_to(from_tick)
	client_sync_include.pop_back()

	client_sync_exclude.push_back(blob_id)
	var current_tick := from_tick + 1
	while current_tick <= to_tick:
		_rollback_to(current_tick)
		if _debug_syncing:
			print("Client: predicting tick ", current_tick)
		blob._internal_rollback_tick(NetworkTime.ticktime, current_tick, false)
		current_tick += 1
	client_sync_exclude.pop_back()
