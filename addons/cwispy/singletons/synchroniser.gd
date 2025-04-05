extends Node


var _state_snapshots: Array[Dictionary]

signal after_tick

var RENDER_TIME_TICK_DELAY = 1
# TODO work on getting this down to 1, on 0 ping it needs to be 2 otherwise the inputs wont exist for some rason
var INPUT_BUFFER_SIZE = 2 # not constant

var client_prediction_enabled := true
var remote_client_prediction_enabled := false

var latest_player_ticks: Dictionary[int, int]


func _ready() -> void:
	NetworkTime.after_tick.connect(_post_tick)
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
	#render_tick = min(render_tick, latest_input_timestamp)
	var current_tick := latest_player_ticks[player_id] + 1
	var inputs_collection := NetworkedInput.get_collection(player_id).duplicate(true)
	inputs_collection.reverse()

	while current_tick <= render_tick:
		if NetworkedInput.has_input_at_time(player_id, current_tick):
			blob._rollback_tick(Clock.fixed_delta, current_tick, true)
		else:
			push_warning("Missing input on tick ", current_tick, " : ", latest_input_timestamp)
		current_tick += 1

	latest_player_ticks[player_id] = render_tick


func _post_tick(_delta: float, tick: int) -> void:
	if not Multiplayer.is_server() and not Multiplayer.is_client(): return

	if Multiplayer.is_server():
		var snapshot := _create_world_snapshot(tick)
		_insert_snapshot_into_buffer(snapshot)
		_broadcast_snapshot(snapshot)


func _sync_blobs() -> void:
	# TODO fix client side prediction code
	# TODO rewatch -> https://www.youtube.com/watch?v=W3aieHjyNvw&t=1529s&ab_channel=GameDevelopersConference

	var rtt := NetworkTime.remote_rtt * 1000
	var half_tick_rtt: int = ceil(
		# TODO rewrite this using NetworkTime.ticktime
		rtt*0.5/float((1000/float(Engine.get_physics_ticks_per_second())))
	)

	var render_tick = NetworkTime.tick - RENDER_TIME_TICK_DELAY - half_tick_rtt
	var latest_used_input_tick := latest_player_ticks.get(multiplayer.get_unique_id())
	if (latest_used_input_tick
	and latest_used_input_tick < render_tick
	and client_prediction_enabled):
		render_tick = latest_used_input_tick

	# try to directly load snapshot if available
	for i in _state_snapshots.size():
		var i_timestamp := _state_snapshots[i]["time"] as int

		if render_tick == i_timestamp:
			var snapshot: Dictionary = _state_snapshots[i]
			#print("loading tick ", render_tick)
			_load_snapshot(snapshot)
			if client_prediction_enabled:
				_attempt_client_prediction_from(render_tick, NetworkTime.tick)
			after_tick.emit()
			return

	# otherwise find latest snapshot and simulate until render_tick
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

	print("simulating")
	var ticks_to_simulate := render_tick - recent_snapshot_before_render_tick["time"] as int
	var player_inputs := recent_snapshot_before_render_tick["inputs"] as Dictionary[int, Dictionary]
	var blobs_to_simulate := recent_snapshot_before_render_tick["blobs"].keys() as Array

	while client_prediction_enabled and ticks_to_simulate > 0:
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
					NetworkedInput._add_inputs_to_buffer(player_inputs[player_id], player_id)
					blob._rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)
			else:
				blob._rollback_tick(NetworkTime.ticktime, simulated_render_tick, false)

		if ticks_to_simulate > 1:
			var snapshot := _create_world_snapshot(simulated_render_tick)
			_insert_snapshot_into_buffer(snapshot)

		ticks_to_simulate -= 1

	if client_prediction_enabled:
		_attempt_client_prediction_from(render_tick, NetworkTime.tick)
	after_tick.emit()


func _insert_snapshot_into_buffer(snapshot: Dictionary) -> void:
	# TODO write algorithm to find correct index, to prevent slowdowns for large buffer sizes
	if Multiplayer.is_server() or not client_prediction_enabled:
		while _state_snapshots.size() > 20 + 1:
			_state_snapshots.pop_back()
	elif latest_player_ticks.has(multiplayer.get_unique_id()):
		var latest_used_input := latest_player_ticks[multiplayer.get_unique_id()]
		while not _state_snapshots.is_empty() and _state_snapshots.back()["time"] < latest_used_input:
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
		if Blob.is_valid_blob(blob):
			# BUG figure out why this check is needed
			blob.load_snapshot(blob_snapshot)


func _broadcast_snapshot(snapshot: Dictionary) -> void:
	_receive_server_snapshot.rpc_id(0, snapshot, latest_player_ticks)


@rpc("unreliable", "authority")
func _receive_server_snapshot(snapshot: Dictionary, latest_player_ticks: Dictionary[int, int]) -> void:
	var player_id := multiplayer.get_unique_id()
	if latest_player_ticks.has(player_id):
		self.latest_player_ticks[player_id] = latest_player_ticks[player_id]
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


func _attempt_client_prediction_from(from_tick: int, to_tick: int) -> void:
	assert(from_tick <= to_tick)

	if not Multiplayer.is_client(): return
	if not Multiplayer.has_local_blob(): return

	var blob := Multiplayer.get_my_blob()

	var current_tick := from_tick
	while current_tick <= to_tick:
		#print("simulating tick ", current_tick, " : ", NetworkTime.tick)
		blob._rollback_tick(NetworkTime.ticktime, current_tick, false)


		current_tick += 1


func _on_Player_joined(player: Player) -> void:
	if Multiplayer.is_server():
		latest_player_ticks[player.get_id()] = NetworkTime.tick


func _on_Player_left(player: Player) -> void:
	if Multiplayer.is_server():
		latest_player_ticks.erase(player.get_id())
