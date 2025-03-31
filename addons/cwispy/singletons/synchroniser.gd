extends Node


var _state_snapshots: Array[Dictionary]


var RENDER_TIME_TICK_DELAY = 1


func _ready() -> void:
	NetworkTime.after_tick.connect(_post_tick)
	#NetworkTime.on_tick.connect(_on_tick)


func _post_tick(_delta: float, tick: int) -> void:
	if not Multiplayer.is_server() and not Multiplayer.is_client(): return

	if Multiplayer.is_client():
		_sync_blobs()
		#_interpolate_blobs()
		return

	var snapshot := _create_world_snapshot(tick)
	_insert_snapshot_into_buffer(snapshot)

	if Multiplayer.is_server():
		#print("broadcasting with time " + str(NetworkTime.tick))
		_broadcast_snapshot(snapshot)


func _physics_process(delta: float) -> void:
	return
	if not Multiplayer.is_server() and not Multiplayer.is_client(): return

	while _state_snapshots.size() > 20:
		_state_snapshots.pop_back()
	if Multiplayer.is_client():
		#_sync_blobs()
		#_interpolate_blobs()
		return

	var snapshot := _create_world_snapshot(NetworkTime.tick)
	_insert_snapshot_into_buffer(snapshot)

	if Multiplayer.is_server():
		#print("broadcasting with time " + str(NetworkTime.tick))
		_broadcast_snapshot(snapshot)
	return
	if not Multiplayer.is_client():
		return

	if _state_snapshots.size() > 20:
		var target_rollback_time := _state_snapshots[5]["time"] as int
		_rollback_to(target_rollback_time)
		var inputs := NetworkedInput.collect_input_function.call()
		var timestamp = NetworkTime.tick
		NetworkedInput._receive_client_inputs.rpc_id(1, inputs, timestamp)
		NetworkedInput._add_inputs_to_buffer(inputs, timestamp, multiplayer.get_unique_id())
		#print("rolling back to " + str(target_rollback_time) + " : current time " + str(NetworkTime.tick))
		var current_tick = target_rollback_time
		while current_tick != NetworkTime.tick:
			current_tick += 1
			for blob in Blob.get_blobs():
				blob._rollback_tick(1/float(Engine.get_physics_ticks_per_second()), current_tick, false)
			_insert_snapshot_into_buffer(_create_world_snapshot(current_tick))

		while _state_snapshots.size() > 10:
			_state_snapshots.pop_back()
		#print("rollback complete " + str(NetworkTime.tick))
		var rolled_back_reconciliated_snapshot := _create_world_snapshot(NetworkTime.tick)
		for blob_id in rolled_back_reconciliated_snapshot["blobs"].keys():
			if blob_id in snapshot["blobs"].keys():
				pass
				#print(snapshot["blobs"][blob_id]["position"] - rolled_back_reconciliated_snapshot["blobs"][blob_id]["position"])
				#print(str(snapshot["blobs"][blob_id]["position"]) + " : " + str(rolled_back_reconciliated_snapshot["blobs"][blob_id]["position"]))
		#_load_snapshot(snapshot)


func _sync_blobs() -> void:
	# TODO add per render frame interpolation of blobs (prolly have to rewrite physics interpolation)
	var rtt := NetworkTime.remote_rtt * 1000
	var half_tick_rtt: int = ceil(
		rtt*0.5/float((1000/float(Engine.get_physics_ticks_per_second())))
	)
	var render_tick = NetworkTime.tick - RENDER_TIME_TICK_DELAY - half_tick_rtt

	# try to directly load snapshot if available
	for i in _state_snapshots.size():
		var i_timestamp := _state_snapshots[i]["time"] as int
		if render_tick == i_timestamp:
			var snapshot: Dictionary = _state_snapshots[i]
			print("loading tick ", render_tick)
			_load_snapshot(snapshot)
			return

	# find latest snapshot and simulate until render_tick
	var recent_snapshot_before_render_tick: Dictionary = {"time":-1}
	for i in _state_snapshots.size():
		var snapshot: Dictionary = _state_snapshots[i]
		if (snapshot["time"] > recent_snapshot_before_render_tick["time"]
		and snapshot["time"] < render_tick
		and snapshot["authority"]):
			recent_snapshot_before_render_tick = snapshot

	if recent_snapshot_before_render_tick["time"] == -1:
		print("Couldn't even find snapshot, returning")
		return
	var ticks_to_simulate := render_tick - recent_snapshot_before_render_tick["time"] as int
	var player_inputs := recent_snapshot_before_render_tick["inputs"] as Dictionary[int, Dictionary]
	while ticks_to_simulate > 0:
		print("simulating tick ", render_tick - ticks_to_simulate + 1,)
		var blobs_to_simulate := []
		for blob_id in recent_snapshot_before_render_tick["blobs"].keys():
			blobs_to_simulate.push_back(blob_id)

		for player_id in player_inputs.keys():
			var player := Player.get_player_by_id(player_id)
			if not Player.is_valid_player(player):
				continue
			var blob := player.get_blob()
			if not Blob.is_valid_blob(blob):
				return

			blob.velocity = Vector2.ZERO
			blob.move_and_slide()
			blob.load_snapshot(recent_snapshot_before_render_tick["blobs"][blob.get_id()])

			NetworkedInput._add_inputs_to_buffer(player_inputs[player_id], render_tick, player_id)
			blob._rollback_tick(1/float(Engine.get_physics_frames()), render_tick - ticks_to_simulate + 1, false)
			NetworkedInput._remove_player_inputs(player_id)

			blobs_to_simulate.erase(blob.get_id())

		for blob_id in blobs_to_simulate:
			var blob := Blob.get_blob_by_id(blob_id)
			var velocity := blob.velocity
			blob.velocity = Vector2.ZERO
			blob.move_and_slide()
			blob.load_snapshot(recent_snapshot_before_render_tick["blobs"][blob.get_id()])
			blob._rollback_tick(1/float(Engine.get_physics_frames()), render_tick - ticks_to_simulate + 1, false)

		if ticks_to_simulate > 1:
			var snapshot := _create_world_snapshot(render_tick - ticks_to_simulate + 1)
			_insert_snapshot_into_buffer(snapshot)

		ticks_to_simulate -= 1


func _get_interpolated_snapshot(old_snapshot: Dictionary, new_snapshot: Dictionary, interpolation_delta: float) -> Dictionary:
	var out := {"blobs": {}, "authority": false, "time": new_snapshot["time"]}

	for blob_id in new_snapshot["blobs"].keys():
		if blob_id in old_snapshot["blobs"].keys():
			var blob_snapshot = {}
			for prop in new_snapshot["blobs"][blob_id]:
				if prop == "position":
					blob_snapshot["position"] = lerp(old_snapshot["blobs"][blob_id]["position"], new_snapshot["blobs"][blob_id]["position"], interpolation_delta)
			out["blobs"][blob_id] = blob_snapshot
		else:
			out["blobs"][blob_id] = new_snapshot["blobs"][blob_id]


	return out


func _insert_snapshot_into_buffer(snapshot: Dictionary) -> void:
	while _state_snapshots.size() > 20 + 1:
		_state_snapshots.pop_back()

	if _state_snapshots.is_empty():
		_state_snapshots.push_front(snapshot)
		return

	if _state_snapshots[0]["time"] < snapshot["time"]:
		_state_snapshots.push_front(snapshot)
		return

	for i in _state_snapshots.size():
		var i_snapshot_time := _state_snapshots[i]["time"] as int
		if i_snapshot_time == snapshot["time"]:
			_state_snapshots[i] = snapshot
			return
	for i in _state_snapshots.size():
		var i_snapshot_time := _state_snapshots[i]["time"] as int
		if snapshot["time"] > i_snapshot_time:
			_state_snapshots.insert(i, snapshot)
			return
	_state_snapshots.push_back(snapshot)


func _rollback_to(time: int) -> void:
	for snapshot in _state_snapshots:
		if snapshot["time"] == time:
			_load_snapshot(snapshot)
			return


func _load_snapshot(snapshot: Dictionary) -> void:
	for blob_id in snapshot["blobs"].keys():
		var blob_snapshot := snapshot["blobs"][blob_id] as Dictionary
		var blob := Blob.get_blob_by_id(blob_id)
		blob.load_snapshot(blob_snapshot)


func _broadcast_snapshot(snapshot: Dictionary) -> void:
	_receive_server_snapshot.rpc_id(0, snapshot)


@rpc("unreliable", "authority")
func _receive_server_snapshot(snapshot: Dictionary) -> void:
	_insert_snapshot_into_buffer(snapshot)


func _create_world_snapshot(time: int) -> Dictionary:
	var output = {
		"blobs": {},
		"time": time,
		"authority": Multiplayer.is_server(),
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
