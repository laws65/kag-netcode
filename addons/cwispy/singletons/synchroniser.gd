extends Node

var _state_snapshots: Array[Dictionary]


func _ready() -> void:
	process_physics_priority = 99


func _physics_process(delta: float) -> void:
	var blobs := Blob.get_blobs()
	for blob in blobs:
		blob._rollback_tick(1/60.0, NetworkTime.tick, true)
	var snapshot := _create_world_snapshot(NetworkTime.tick)
	_state_snapshots.push_front(snapshot)
	
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
				blob._rollback_tick(1/60.0, current_tick, false)
			_replace_snapshot(_create_world_snapshot(current_tick))

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


func _replace_snapshot(snapshot: Dictionary) -> void:
	for i in _state_snapshots.size():
		var i_snapshot_time := _state_snapshots[i]["time"] as int
		if i_snapshot_time == snapshot["time"]:
			_state_snapshots[i] = snapshot


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


func _create_world_snapshot(time: int) -> Dictionary:
	var output = {"blobs": {}, "time": time}
	
	var blobs := Blob.get_blobs()
	for blob in blobs as Array[Blob]:
		var blob_snapshot := blob.get_snapshot()
		output["blobs"][blob.get_id()] = blob_snapshot
	
	return output
