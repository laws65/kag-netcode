extends Node


signal after_tick

var RENDER_TIME_TICK_DELAY = 1
# TODO work on getting this down to 1, on 0 ping it needs to be 2 otherwise the inputs wont exist for some rason
var INPUT_BUFFER_SIZE = 2 # not constant

var client_prediction_enabled := false
var remote_client_prediction_enabled := true

var server_latest_player_ticks: Dictionary[int, int]
var latest_consumed_player_inputs: Dictionary[int, int]

var client_sync_exclude: Array[int] # Array of blob id's that won't be in _load_snapshot()


func _ready() -> void:
	NetworkTime.on_tick.connect(_tick)
	Multiplayer.player_joined.connect(_on_Player_joined)
	Multiplayer.player_left.connect(_on_Player_left)


func _tick(_delta: float, tick: int) -> void:
	if Multiplayer.is_client():
		_sync_blobs()
	elif Multiplayer.is_server():
		_tick_world(tick)


func _tick_world(tick: int) -> void:
	var blobs := Blob.get_blobs()
	for blob: Blob in blobs:
		var player := blob.get_player()
		if not Player.is_valid_player(player):
			blob._rollback_tick(Clock.fixed_delta, tick, true)
		else:
			_tick_player_blob(blob, tick)


func _tick_player_blob(blob: Blob, tick: int) -> void:
	var player := blob.get_player()
	var player_id := player.get_id()

	var rtt := player.get_rtt_msecs()
	var half_tick_rtt: int = ceil(
		# TODO rewrite this using NetworkTime.ticktime
		rtt*0.5/float((1000/float(Engine.get_physics_ticks_per_second())))
	)

	var render_tick: int = tick - INPUT_BUFFER_SIZE - half_tick_rtt
	var latest_input_timestamp := NetworkedInput.get_latest_input_timestamp(player_id)
	var current_tick := server_latest_player_ticks[player_id] + 1

	while current_tick <= render_tick:
		var predicted = false
		print("consuming input ", latest_input_timestamp, " on tick ", current_tick, " ", predicted)
		if NetworkedInput.has_inputs_at_time(player_id, current_tick):
			latest_consumed_player_inputs[player_id] = current_tick
		if latest_input_timestamp < current_tick:
			predicted = true
			# TODO increase buffer size, to account for changes in ping, etc. so that we don't have to predict inputs consistently
			#push_warning("Missing input on tick ", current_tick, " : ", latest_input_timestamp)
			var predicted_input := NetworkedInput.get_predicted_input(player_id, current_tick)
			NetworkedInput.add_temp_input(player_id, predicted_input)

		blob._rollback_tick(Clock.fixed_delta, current_tick, true)
		current_tick += 1

	server_latest_player_ticks[player_id] = render_tick


func _sync_blobs() -> void:
	print("-----NEW TICK-----------")
	# TODO fix client side prediction code
	# TODO rewatch -> https://www.youtube.com/watch?v=W3aieHjyNvw&t=1529s&ab_channel=GameDevelopersConference

	var rtt := NetworkTime.remote_rtt * 1000
	var half_tick_rtt: int = ceil(
		# TODO rewrite this using NetworkTime.ticktime
		rtt*0.5/float((1000/float(Engine.get_physics_ticks_per_second())))
	)

	var render_tick = NetworkTime.tick - RENDER_TIME_TICK_DELAY - half_tick_rtt
	var latest_used_input_tick := latest_consumed_player_inputs.get(multiplayer.get_unique_id())

	# try to directly load snapshot if available
	var snapshots_buffer := SnapshotManager.get_snapshots_buffer()
	for i in snapshots_buffer.size():
		var i_timestamp := snapshots_buffer[i]["time"] as int
		if render_tick != i_timestamp:
			continue

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
					blob._rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)
			else:
				blob._rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)

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

		print("loading snapshot ", snapshot["time"])
		var blob_snapshot := snapshot["blobs"][blob_id] as Dictionary
		var blob := Blob.get_blob_by_id(blob_id)
		if Blob.is_valid_blob(blob):
			# BUG figure out why this check is needed
			blob.load_snapshot(blob_snapshot)


func _attempt_client_prediction_from(from_tick: int, to_tick: int) -> void:
	print("predictin from ", from_tick, " to ", to_tick)
	assert(from_tick <= to_tick)

	if not Multiplayer.is_client(): return
	if not Multiplayer.has_local_blob(): return

	var blob := Multiplayer.get_my_blob()

	_rollback_to(from_tick)
	var current_tick := from_tick + 1
	while current_tick <= to_tick:
		print("predicting ", current_tick)
		#print("simulating tick ", current_tick, " : ", NetworkTime.tick)
		blob._rollback_tick(NetworkTime.ticktime, current_tick, false)
		current_tick += 1


func _on_Player_joined(player: Player) -> void:
	if Multiplayer.is_server():
		server_latest_player_ticks[player.get_id()] = NetworkTime.tick


func _on_Player_left(player: Player) -> void:
	if Multiplayer.is_server():
		server_latest_player_ticks.erase(player.get_id())
		latest_consumed_player_inputs.erase(player.get_id())
