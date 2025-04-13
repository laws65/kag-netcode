extends Node
## Ticks the world blobs, and player blobs if they have inputs
# TODO move latest_consumed_player_inputs() code out of world state maybe? More for SOC

# TODO work on getting this down to 1, on 0 ping it needs to be 2 otherwise the inputs wont exist for some rason
var INPUT_BUFFER_SIZE = 2 # not constant
var server_latest_player_ticks: Dictionary[int, int]

var latest_consumed_player_inputs: Dictionary[int, int]


func _ready() -> void:
	NetworkTime.on_tick.connect(func(_delta: float, tick: int):
		if Multiplayer.is_server():
			_tick_world(tick)
	)
	Multiplayer.player_joined.connect(func(player: Player):
		if Multiplayer.is_server():
			server_latest_player_ticks[player.get_id()] = NetworkTime.tick
	)
	Multiplayer.player_left.connect(func(player: Player):
		if Multiplayer.is_server():
			server_latest_player_ticks.erase(player.get_id())
			latest_consumed_player_inputs.erase(player.get_id())
	)


func _tick_world(tick: int) -> void:
	var blobs := Blob.get_blobs()
	for blob: Blob in blobs:
		var player := blob.get_player()
		if not Player.is_valid_player(player):
			blob._internal_rollback_tick(Clock.fixed_delta, tick, true)
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
		# BUG fix this print to show the actual inptu being used, not just the latest one
		if Synchroniser._debug_syncing:
			print("consuming input ", latest_input_timestamp, " on tick ", current_tick, " ", predicted)
		if NetworkedInput.has_inputs_at_time(player_id, current_tick):
			latest_consumed_player_inputs[player_id] = current_tick
		if latest_input_timestamp < current_tick:
			print("Server: missed last player input, predicting input for tick " + str(current_tick))
			predicted = true
			# TODO increase buffer size, to account for changes in ping, etc. so that we don't have to predict inputs consistently
			#push_warning("Missing input on tick ", current_tick, " : ", latest_input_timestamp)
			var predicted_input := NetworkedInput.get_predicted_input(player_id, current_tick)
			NetworkedInput.add_temp_input(player_id, predicted_input)

		blob._internal_rollback_tick(Clock.fixed_delta, current_tick, true)
		current_tick += 1

	server_latest_player_ticks[player_id] = render_tick
