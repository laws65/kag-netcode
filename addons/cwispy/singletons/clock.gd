extends Node


var player_rtt: Dictionary[int, float]
var sync_interval_secs := 0.2

var fixed_delta:
	get:
		return 1/float(Engine.get_physics_ticks_per_second())

func _ready() -> void:
	Multiplayer.player_left.connect(_on_Player_left)
	NetworkTime.on_tick.connect(_on_tick)


func _sync_rtt() -> void:
	_server_receive_rtt.rpc_id(1, NetworkTime.remote_rtt)
	await get_tree().create_timer(sync_interval_secs).timeout
	_sync_rtt()


@rpc("unreliable", "any_peer")
func _server_receive_rtt(rtt: float) -> void:
	var player_id := multiplayer.get_remote_sender_id()
	player_rtt[player_id] = rtt


func _on_Player_left(player: Player) -> void:
	player_rtt.erase(player.get_id())


func _on_tick(_delta: float, _tick: int) -> void:
	if Multiplayer.is_client():
		_sync_rtt()
		NetworkTime.on_tick.disconnect(_on_tick)
