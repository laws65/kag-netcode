extends Node

var ping_ms := -1
var rtt_buffer := []


func _physics_process(delta: float) -> void:
	if not Multiplayer.server_active(): return

	if not is_multiplayer_authority():
		if rtt_buffer.is_empty():
			_ping_server()


func _ping_server() -> void:
	var time := int(Time.get_unix_time_from_system() * 1000)
	ping.rpc_id(1, time)


@rpc("reliable", "any_peer")
func ping(client_time: int) -> void:
	var server_time := int(Time.get_unix_time_from_system() * 1000)
	var player_id := multiplayer.get_remote_sender_id()
	pong.rpc_id(player_id, server_time, client_time)


@rpc("reliable", "authority")
func pong(server_time: int, client_time: int) -> void:
	var rtt := int(Time.get_unix_time_from_system() * 1000) - client_time
	rtt_buffer.push_back(rtt)
	if rtt_buffer.size() < 10:
		_ping_server()
	else:
		rtt_buffer.pop_front()
		await get_tree().create_timer(0.33).timeout
		_ping_server()


func get_rtt_conservative() -> int:
	# TODO implement
	return get_rtt()


func get_rtt() -> int:
	if rtt_buffer.size() == 0:
		return 0
	var total := 0
	for num in rtt_buffer:
		total += num
	return total/rtt_buffer.size()
	#return roundi(total/float(rtt_buffer.size()))
