extends Node


signal after_tick

var RENDER_TIME_TICK_DELAY = 1

var client_prediction_enabled := false
var remote_client_prediction_enabled := false

var _debug_syncing := false

var client_sync_exclude: Array[int] # Array of blob id's that won't be in _load_snapshot()


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

	var render_tick = NetworkTime.tick - RENDER_TIME_TICK_DELAY - half_tick_rtt
	var latest_used_input_tick := ServerTicker.latest_consumed_player_inputs.get(multiplayer.get_unique_id())

	# try to directly load snapshot if available
	var snapshots_buffer := SnapshotManager.get_snapshots_buffer()
	for i in snapshots_buffer.size():
		var i_timestamp := snapshots_buffer[i]["time"] as int
		if render_tick != i_timestamp:
			continue
		if _debug_syncing:
			print("render tick", render_tick, " : ", NetworkTime.tick)
			print("last used input ", latest_used_input_tick)
		var snapshot: Dictionary = snapshots_buffer[i]

		if (client_prediction_enabled
		and latest_used_input_tick
		and latest_used_input_tick < render_tick):
			_attempt_client_prediction_from(latest_used_input_tick, NetworkTime.tick)
		elif client_prediction_enabled:
			_attempt_client_prediction_from(render_tick, NetworkTime.tick)
		var my_blob_id := Multiplayer.get_my_blob_id()
		if client_prediction_enabled:
			client_sync_exclude.push_back(my_blob_id)
			_load_snapshot(snapshot)
			client_sync_exclude.pop_back()
		else:
			_load_snapshot(snapshot)
		after_tick.emit()
		return

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
		_attempt_client_prediction_from(render_tick, NetworkTime.tick)
	after_tick.emit()


func _rollback_to(time: int) -> void:
	var snapshots_buffer := SnapshotManager.get_snapshots_buffer()
	for snapshot in snapshots_buffer:
		if snapshot["time"] == time:
			_load_snapshot(snapshot)
			return


func _load_snapshot(snapshot: Dictionary) -> void:
	for blob_id in snapshot["blobs"].keys():
		if blob_id in client_sync_exclude: continue

		if _debug_syncing:
			print("loading snapshot ", snapshot["time"])
		var blob_snapshot := snapshot["blobs"][blob_id] as Dictionary
		var blob := Blob.get_blob_by_id(blob_id)
		if Blob.is_valid_blob(blob):
			# BUG figure out why this check is needed
			blob.load_snapshot(blob_snapshot)


func _attempt_client_prediction_from(from_tick: int, to_tick: int) -> void:
	if _debug_syncing:
		print("predictin from ", from_tick, " to ", to_tick)
	assert(from_tick <= to_tick)

	if not Multiplayer.is_client(): return
	if not Multiplayer.has_local_blob(): return

	var blob := Multiplayer.get_my_blob()

	_rollback_to(from_tick)
	var current_tick := from_tick + 1
	while current_tick <= to_tick:
		if _debug_syncing:
			print("predicting ", current_tick)
		#print("simulating tick ", current_tick, " : ", NetworkTime.tick)
		blob._internal_rollback_tick(NetworkTime.ticktime, current_tick, false)
		current_tick += 1
