@tool
extends Node
class_name RollbackSynchronizer

## Similar to [MultiplayerSynchronizer], this class is responsible for
## synchronizing data between players, but with support for rollback.
## [br][br]
## @tutorial(RollbackSynchronizer Guide): https://foxssake.github.io/netfox/netfox/nodes/rollback-synchronizer/

## The root node for resolving node paths in properties. Defaults to the parent
## node.
@export var root: Node = get_parent()

## Toggle prediction.
## [br][br]
## Enabling this will run [code]_rollback_tick[/code] on nodes under
## [member root] even if there's no current input available for the tick.
@export var enable_prediction: bool = false

@export_group("State")
## Properties that define the game state.
## [br][br]
## State properties are recorded for each tick and restored during rollback.
## State is restored before every rollback tick, and recorded after simulating
## the tick.
@export var state_properties: Array[String]

## Ticks to wait between sending full states.
## [br][br]
## If set to 0, full states will never be sent. If set to 1, only full states
## will be sent. If set higher, full states will be sent regularly, but not
## for every tick.
## [br][br]
## Only considered if [member _NetworkRollback.enable_diff_states] is true.
@export_range(0, 128, 1, "or_greater")
var full_state_interval: int = 24

## Ticks to wait between unreliably acknowledging diff states.
## [br][br]
## This can reduce the amount of properties sent in diff states, due to clients
## more often acknowledging received states. To avoid introducing hickups, these
## are sent unreliably.
## [br][br]
## If set to 0, diff states will never be acknowledged. If set to 1, all diff
## states will be acknowledged. If set higher, ack's will be sent regularly, but
## not for every diff state.
## [br][br]
## If enabled, it's worth to tune this setting until network traffic is actually
## reduced.
## [br][br]
## Only considered if [member _NetworkRollback.enable_diff_states] is true.
@export_range(0, 128, 1, "or_greater")
var diff_ack_interval: int = 0

@export_group("Inputs")
## Properties that define the input for the game simulation.
## [br][br]
## Input properties drive the simulation, which in turn results in updated state
## properties. Input is recorded after every network tick.
@export var input_properties: Array[String]

## This will broadcast input to all peers, turning this off will limit to
## sending it to the server only. Turning this off is recommended to save
## bandwidth and reduce cheating risks.
@export var enable_input_broadcast: bool = true

var _record_state_property_entries: Array[PropertyEntry] = []
var _record_input_property_entries: Array[PropertyEntry] = []
var _auth_state_property_entries: Array[PropertyEntry] = []
var _auth_input_property_entries: Array[PropertyEntry] = []
var _nodes: Array[Node] = []

var _simset: _Set = _Set.new()
var _skipset: _Set = _Set.new()

var _properties_dirty: bool = false

var _states: Dictionary = {}
var _inputs: Dictionary = {}
var _latest_state_tick: int
var _earliest_input_tick: int

var _ackd_state: Dictionary = {}
var _next_full_state_tick: int
var _next_diff_ack_tick: int

var _retrieved_tick: int
var _has_input: bool
var _input_tick: int
var _is_predicted_tick: bool

var _property_cache: PropertyCache
var _freshness_store: RollbackFreshnessStore

var _is_initialized: bool = false

static var _logger: _NetfoxLogger = _NetfoxLogger.for_netfox("RollbackSynchronizer")

signal _on_transmit_state(state: Dictionary, tick: int)

## Process settings.
##
## Call this after any change to configuration. Updates based on authority too
## ( calls process_authority ).
func process_settings():
	_property_cache = PropertyCache.new(root)
	_freshness_store = RollbackFreshnessStore.new()

	_nodes.clear()
	_record_state_property_entries.clear()

	_states.clear()
	_inputs.clear()
	_ackd_state.clear()
	_latest_state_tick = NetworkTime.tick - 1
	_earliest_input_tick = NetworkTime.tick
	_next_full_state_tick = NetworkTime.tick
	_next_diff_ack_tick = NetworkTime.tick

	# Scatter full state sends, so not all nodes send at the same tick
	if is_inside_tree():
		_next_full_state_tick += hash(get_path()) % maxi(1, full_state_interval)
		_next_diff_ack_tick += hash(get_path()) % maxi(1, diff_ack_interval)
	else:
		_next_full_state_tick += hash(name) % maxi(1, full_state_interval)
		_next_diff_ack_tick += hash(name) % maxi(1, diff_ack_interval)

	# Gather state properties - all state properties are recorded
	for property in state_properties:
		var property_entry = _property_cache.get_entry(property)
		_record_state_property_entries.push_back(property_entry)

	process_authority()

	# Gather all rollback-aware nodes to simulate during rollbacks
	_nodes = root.find_children("*")
	_nodes.push_front(root)
	_nodes = _nodes.filter(func(it): return NetworkRollback.is_rollback_aware(it))
	_nodes.erase(self)

	_is_initialized = true

## Process settings based on authority.
##
## Call this whenever the authority of any of the nodes managed by
## RollbackSynchronizer changes. Make sure to do this at the same time on all
## peers.
func process_authority():
	_record_input_property_entries.clear()
	_auth_input_property_entries.clear()
	_auth_state_property_entries.clear()

	# Gather state properties that we own
	# i.e. it's the state of a node that belongs to the local peer
	for property in state_properties:
		var property_entry = _property_cache.get_entry(property)
		if property_entry.node.is_multiplayer_authority():
			_auth_state_property_entries.push_back(property_entry)

	# Gather input properties that we own
	# Only record input that is our own
	for property in input_properties:
		var property_entry = _property_cache.get_entry(property)
		if property_entry.node.is_multiplayer_authority():
			_auth_input_property_entries.push_back(property_entry)
			_record_input_property_entries.push_back(property_entry)

## Add a state property.
## [br][br]
## Settings will be automatically updated. The [param node] may be a string or
## [NodePath] pointing to a node, or an actual [Node] instance. If the given
## property is already tracked, this method does nothing.
func add_state(node: Variant, property: String):
	var property_path := PropertyEntry.make_path(root, node, property)
	if not property_path or state_properties.has(property_path):
		return

	state_properties.push_back(property_path)
	_properties_dirty = true
	_reprocess_settings.call_deferred()

## Add an input property.
## [br][br]
## Settings will be automatically updated. The [param node] may be a string or
## [NodePath] pointing to a node, or an actual [Node] instance. If the given
## property is already tracked, this method does nothing.
func add_input(node: Variant, property: String):
	var property_path := PropertyEntry.make_path(root, node, property)
	if not property_path or input_properties.has(property_path):
		return

	input_properties.push_back(property_path)
	_properties_dirty = true
	_reprocess_settings.call_deferred()

## Check if input is available for the current tick.
##
## This input is not always current, it may be from multiple ticks ago.
## [br][br]
## Returns true if input is available.
func has_input() -> bool:
	return _has_input

## Get the age of currently available input in ticks.
##
## The available input may be from the current tick, or from multiple ticks ago.
## This number of tick is the input's age.
## [br][br]
## Calling this when [member has_input] is false will yield an error.
func get_input_age() -> int:
	if has_input():
		return NetworkRollback.tick - _input_tick
	else:
		_logger.error("Trying to check input age without having input!")
		return -1

## Check if the current tick is predicted.
##
## A tick becomes predicted if there's no up-to-date input available. It will be
## simulated and recorded, but will not be broadcast, nor considered
## authoritative.
func is_predicting() -> bool:
	return _is_predicted_tick

## Ignore a node's prediction for the current rollback tick.
##
## Call this when the input is too old to base predictions on. This call is
## ignored if [member enable_prediction] is false.
func ignore_prediction(node: Node):
	if enable_prediction:
		_skipset.add(node)

func _ready():
	if not NetworkTime.is_initial_sync_done():
		# Wait for time sync to complete
		await NetworkTime.after_sync
	process_settings.call_deferred()

func _connect_signals():
	NetworkTime.before_tick.connect(_before_tick)
	NetworkTime.after_tick.connect(_after_tick)
	NetworkRollback.before_loop.connect(_before_loop)
	NetworkRollback.on_prepare_tick.connect(_prepare_tick)
	NetworkRollback.on_process_tick.connect(_process_tick)
	NetworkRollback.on_record_tick.connect(_record_tick)
	NetworkRollback.after_loop.connect(_after_loop)

func _disconnect_signals():
	NetworkTime.before_tick.disconnect(_before_tick)
	NetworkTime.after_tick.disconnect(_after_tick)
	NetworkRollback.before_loop.disconnect(_before_loop)
	NetworkRollback.on_prepare_tick.disconnect(_prepare_tick)
	NetworkRollback.on_process_tick.disconnect(_process_tick)
	NetworkRollback.on_record_tick.disconnect(_record_tick)
	NetworkRollback.after_loop.disconnect(_after_loop)

func _notification(what):
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		update_configuration_warnings()

func _get_configuration_warnings():
	if not root:
		root = get_parent()

	# Explore state and input properties
	if not root:
		return ["No valid root node found!"]

	var result = []
	result.append_array(_NetfoxEditorUtils.gather_properties(root, "_get_rollback_state_properties",
		func(node, prop):
			add_state(node, prop)
	))

	result.append_array(_NetfoxEditorUtils.gather_properties(root, "_get_rollback_input_properties",
		func(node, prop):
			add_input(node, prop)
	))

	return result

func _enter_tree():
	if Engine.is_editor_hint():
		return

	if not NetworkTime.is_initial_sync_done():
		# Wait for time sync to complete
		await NetworkTime.after_sync
	_connect_signals.call_deferred()
	process_settings.call_deferred()

func _exit_tree():
	if Engine.is_editor_hint():
		return

	_is_initialized = false
	_disconnect_signals()

func _before_loop():
	if _auth_input_property_entries.is_empty():
		# We don't have any inputs we own, simulate from earliest we've received
		NetworkRollback.notify_resimulation_start(_earliest_input_tick)
	else:
		# We own inputs, simulate from latest authorative state
		NetworkRollback.notify_resimulation_start(_latest_state_tick)

func _prepare_tick(tick: int):
	# Prepare state
	#	Done individually by Rewindables ( usually Rollback Synchronizers )
	#	Restore input and state for tick
	var state = _get_history(_states, tick)
	var input = _get_history(_inputs, tick)

	PropertySnapshot.apply(state, _property_cache)
	PropertySnapshot.apply(input, _property_cache)

	# Save data for input prediction
	_has_input = _retrieved_tick != -1
	_input_tick = _retrieved_tick
	_is_predicted_tick = not _inputs.has(tick)

	# Reset the set of simulated and ignored nodes
	_simset.clear()
	_skipset.clear()

	# Gather nodes that can be simulated
	for node in _nodes:
		if _can_simulate(node, tick):
			NetworkRollback.notify_simulated(node)

func _can_simulate(node: Node, tick: int) -> bool:
	if not enable_prediction and not _inputs.has(tick):
		# Don't simulate if prediction is not allowed and input is unknown
		return false
	if node.is_multiplayer_authority():
		# Simulate from earliest input
		# Don't simulate frames we don't have input for
		return tick >= _earliest_input_tick
	else:
		# Simulate ONLY if we have state from server
		# Simulate from latest authorative state - anything the server confirmed we don't rerun
		# Don't simulate frames we don't have input for
		return tick >= _latest_state_tick

func _process_tick(tick: int):
	# Simulate rollback tick
	#	Method call on rewindables
	#	Rollback synchronizers go through each node they manage
	#	If current tick is in node's range, tick
	#		If authority: Latest input >= tick >= Latest state
	#		If not: Latest input >= tick >= Earliest input
	for node in _nodes:
		if not NetworkRollback.is_simulated(node):
			continue

		var is_fresh = _freshness_store.is_fresh(node, tick)
		NetworkRollback.process_rollback(node, NetworkTime.ticktime, tick, is_fresh)

		if _skipset.has(node):
			continue

		_freshness_store.notify_processed(node, tick)
		_simset.add(node)

func _record_tick(tick: int):
	# Broadcast state we own
	if not _auth_state_property_entries.is_empty() and not _is_predicted_tick:
		var full_state: Dictionary = {}

		for property in _auth_state_property_entries:
			if _can_simulate(property.node, tick - 1) and not _skipset.has(property.node):
				# Only broadcast if we've simulated the node
				full_state[property.to_string()] = property.get_value()

		_on_transmit_state.emit(full_state, tick)

		if full_state.size() > 0:
			_latest_state_tick = max(_latest_state_tick, tick)
			_states[tick] = PropertySnapshot.merge(_states.get(tick, {}), full_state)

			if not NetworkRollback.enable_diff_states:
				# Broadcast new full state
				_submit_full_state.rpc(full_state, tick)

				NetworkPerformance.push_full_state_broadcast(full_state)
				NetworkPerformance.push_sent_state_broadcast(full_state)
			elif full_state_interval > 0 and tick > _next_full_state_tick:
				# Send full state so we can send deltas from there
				_logger.trace("Broadcasting full state for tick %d", [tick])
				_submit_full_state.rpc(full_state, tick)
				_next_full_state_tick = tick + full_state_interval

				NetworkPerformance.push_full_state_broadcast(full_state)
				NetworkPerformance.push_sent_state_broadcast(full_state)
			else:
				for peer in multiplayer.get_peers():
					NetworkPerformance.push_full_state(full_state)

					# Peer hasn't received a full state yet, can't send diffs
					if not _ackd_state.has(peer):
						_submit_full_state.rpc_id(peer, full_state, tick)
						NetworkPerformance.push_sent_state(full_state)
						continue

					# History doesn't have reference tick?
					var reference_tick = _ackd_state[peer]
					if not _states.has(reference_tick):
						_submit_full_state.rpc_id(peer, full_state, tick)
						NetworkPerformance.push_sent_state(full_state)
						continue

					# Prepare diff and send
					var reference_state = _get_history(_states, reference_tick)
					var diff_state = PropertySnapshot.make_patch(reference_state, full_state)

					if diff_state.size() == full_state.size():
						# State is completely different, send full state
						_submit_full_state.rpc_id(peer, full_state, tick)
						NetworkPerformance.push_sent_state(full_state)
					else:
						# Send only diff
						_submit_diff_state.rpc_id(peer, diff_state, tick, reference_tick)
						NetworkPerformance.push_sent_state(diff_state)

	# Record state for specified tick ( current + 1 )
	if not _record_state_property_entries.is_empty() and tick > _latest_state_tick:
		if _skipset.is_empty():
			_states[tick] = PropertySnapshot.extract(_record_state_property_entries)
		else:
			var record_properties = _record_state_property_entries\
				.filter(func(pe): return not _skipset.has(pe.node))

			var merge_state = _get_history(_states, tick - 1)
			var record_state = PropertySnapshot.extract(record_properties)

			_states[tick] = PropertySnapshot.merge(merge_state, record_state)

	# Push metrics
	NetworkPerformance.push_rollback_nodes_simulated(_simset.size())

func _after_loop():
	_earliest_input_tick = NetworkTime.tick

	# Apply display state
	var display_state = _get_history(_states, NetworkTime.tick - NetworkRollback.display_offset)
	PropertySnapshot.apply(display_state, _property_cache)

func _before_tick(_delta, tick):
	# Apply state for tick
	var state = _get_history(_states, tick)
	PropertySnapshot.apply(state, _property_cache)

func _after_tick(_delta, _tick):
	# Record input
	if not _record_input_property_entries.is_empty():
		var input = PropertySnapshot.extract(_record_input_property_entries)
		_inputs[NetworkTime.tick] = input

		#Send the last n inputs for each property
		var inputs = {}
		for i in range(0, NetworkRollback.input_redundancy):
			var tick_input = _inputs.get(NetworkTime.tick - i, {})
			for property in tick_input:
				if not inputs.has(property):
					inputs[property] = []
				inputs[property].push_back(tick_input[property])

		_attempt_submit_input(inputs)

	# Trim history
	while _states.size() > NetworkRollback.history_limit:
		_states.erase(_states.keys().min())

	while _inputs.size() > NetworkRollback.history_limit:
		_inputs.erase(_inputs.keys().min())

	_freshness_store.trim()

func _attempt_submit_input(input: Dictionary):
	# TODO: Default to input broadcast in mesh network setups
	if enable_input_broadcast:
		_submit_input.rpc(input, NetworkTime.tick)
	elif not multiplayer.is_server():
		_submit_input.rpc_id(1, input, NetworkTime.tick)

func _reprocess_settings():
	if not _properties_dirty or Engine.is_editor_hint():
		return

	_properties_dirty = false
	process_settings()

# TODO: Eventually refactor into separate HistoryBuffer class
func _get_history(buffer: Dictionary, tick: int) -> Dictionary:
	if buffer.has(tick):
		_retrieved_tick = tick
		return buffer[tick]

	if buffer.is_empty():
		_retrieved_tick = -1
		return {}

	var earliest_tick = buffer.keys().min()
	var latest_tick = buffer.keys().max()

	if tick < earliest_tick:
		_retrieved_tick = earliest_tick
		return buffer[earliest_tick]

	if tick > latest_tick:
		_retrieved_tick = latest_tick
		return buffer[latest_tick]

	var before = buffer.keys() \
		.filter(func (key): return key < tick) \
		.max()

	_retrieved_tick = before
	return buffer[before]

func _sanitize_by_authority(snapshot: Dictionary, sender: int) -> Dictionary:
	var sanitized := {}

	for property in snapshot:
		var property_entry := _property_cache.get_entry(property)
		var value = snapshot[property]
		var authority := property_entry.node.get_multiplayer_authority()

		if authority == sender:
			sanitized[property] = value
		else:
			_logger.warning(
				"Received data for property %s, owned by %s, from sender %s",
				[ property, authority, sender ]
			)

	return sanitized

@rpc("any_peer", "unreliable", "call_remote")
func _submit_input(input: Dictionary, tick: int):
	if not _is_initialized:
		# Settings not processed yet
		return

	var sender = multiplayer.get_remote_sender_id()
	var sanitized = _sanitize_by_authority(input, sender)

	if sanitized.size() > 0:
		for property in sanitized:
			for i in range(0, sanitized[property].size()):
				var t = tick - i
				if t < NetworkTime.tick - NetworkRollback.history_limit:
					# Input too old
					_logger.error("Received input for %s, rejecting because older than %s frames", [t, NetworkRollback.history_limit])
					continue

				var old_input = _inputs.get(t, {}).get(property)
				var new_input = sanitized[property][i]

				if old_input == null:
					# We received an array of current and previous inputs, merge them into our history.
					_inputs[t] = _inputs.get(t, {})
					_inputs[t][property] = new_input
					_earliest_input_tick = min(_earliest_input_tick, t)
	else:
		_logger.warning("Received invalid input from %s for tick %s for %s", [sender, tick, root.name])

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _submit_full_state(state: Dictionary, tick: int):
	if not _is_initialized:
		# Settings not processed yet
		return

	if tick < NetworkTime.tick - NetworkRollback.history_limit:
		# State too old!
		_logger.error("Received full state for %s, rejecting because older than %s frames", [tick, NetworkRollback.history_limit])
		return

	var sender = multiplayer.get_remote_sender_id()
	var sanitized = _sanitize_by_authority(state, sender)

	if sanitized.is_empty():
		# State is completely invalid
		_logger.warning("Received invalid state from %s for tick %s", [sender, tick])
		return

	_states[tick] = PropertySnapshot.merge(_states.get(tick, {}), sanitized)
	_latest_state_tick = tick

	if NetworkRollback.enable_diff_states:
		_ack_full_state.rpc_id(get_multiplayer_authority(), tick)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _submit_diff_state(diff_state: Dictionary, tick: int, reference_tick: int):
	if not _is_initialized:
		# Settings not processed yet
		return

	if tick < NetworkTime.tick - NetworkRollback.history_limit:
		# State too old!
		_logger.error("Received diff state for %s, rejecting because older than %s frames", [tick, NetworkRollback.history_limit])
		return

	if not _states.has(reference_tick):
		# Reference tick missing, hope for the best
		_logger.warning("Reference tick %d missing for %d", [reference_tick, tick])

	var reference_state = _states.get(reference_tick, {})
	var is_valid_state := true

	if (diff_state.is_empty()):
		_latest_state_tick = tick
		_states[tick] = reference_state
	else:
		var sender = multiplayer.get_remote_sender_id()
		var sanitized = _sanitize_by_authority(diff_state, sender)

		if not sanitized.is_empty():
			var result_state := PropertySnapshot.merge(reference_state, sanitized)
			_states[tick] = result_state
			_latest_state_tick = tick
		else:
			# State is completely invalid
			_logger.warning("Received invalid state from %s for tick %s", [sender, tick])
			is_valid_state = false

	if NetworkRollback.enable_diff_states:
		if is_valid_state and diff_ack_interval > 0 and tick > _next_diff_ack_tick:
			_ack_diff_state.rpc_id(get_multiplayer_authority(), tick)
			_next_diff_ack_tick = tick + diff_ack_interval

@rpc("any_peer", "reliable", "call_remote")
func _ack_full_state(tick: int):
	var sender_id := multiplayer.get_remote_sender_id()
	_ackd_state[sender_id] = tick

	_logger.trace("Peer %d ack'd full state for tick %d", [sender_id, tick])

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _ack_diff_state(tick: int):
	var sender_id := multiplayer.get_remote_sender_id()
	_ackd_state[sender_id] = tick

	_logger.trace("Peer %d ack'd diff state for tick %d", [sender_id, tick])
