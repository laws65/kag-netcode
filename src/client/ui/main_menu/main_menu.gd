extends Control


func _ready() -> void:
	Multiplayer.server_started.connect(_on_server_started)
	Multiplayer.joined_server.connect(_on_joined_server)


func _physics_process(_delta: float) -> void:
	$FPS.text = str(Engine.get_frames_per_second())


func _on_server_started() -> void:
	$HBoxContainer.hide()
	$Server.show()


func _on_joined_server() -> void:
	$HBoxContainer.hide()
	$Client.show()


func _on_server_start_button_up() -> void:
	var port := 50302
	Multiplayer.start_server(port)


func _on_client_start_button_up() -> void:
	var ip := "127.0.0.1"
	var port := 50302
	var username := %ClientUsername.text as String
	Multiplayer.join_server(ip, port, [username])
