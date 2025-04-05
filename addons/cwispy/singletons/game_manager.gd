extends Node


signal gamemode_switched(old_gamemode, new_gamemode)
signal map_switched(old_map, new_map)

var gamemode_path := "res://src/gamemodes/tdm/tdm.cfg"
var current_map := "res://src/maps/dust2/dust2.tscn"


func _ready() -> void:
	Multiplayer.server_started.connect(_on_server_started)


func _on_server_started() -> void:
	load_gamemode.rpc_id(0, "res://src/gamemodes/tdm/tdm.cfg")
	load_random_map()


@rpc("authority", "reliable", "call_local")
func load_gamemode(path: String) -> void:
	var config := ConfigFile.new()
	var err := config.load(path)

	if err != OK:
		print("Couldn't open config file with path " + str(path) + " (error code " + str(err) + ")")
		return

	var old_gamemode_path = gamemode_path
	gamemode_path = path

	gamemode_switched.emit(old_gamemode_path, gamemode_path)

	var scripts_parent := get_scripts_parent()
	for child in scripts_parent.get_children():
		scripts_parent.remove_child(child)
		child.queue_free()

	var scripts := config.get_value("Rules", "scripts") as Array
	for script_path in scripts:
		var script := load(script_path) as GDScript
		var node := Node.new()
		node.set_script(script)
		scripts_parent.add_child(node)


func load_random_map() -> void:
	var config := ConfigFile.new()
	var err := config.load(gamemode_path)

	if err != OK:
		print("Couldn't open config file with path " + str(gamemode_path) + " (error code " + str(err) + ")")
		return

	var map_pool := config.get_value("Rules", "maps") as Array
	var new_map_path := map_pool.pick_random() as String
	load_map.rpc_id(0, new_map_path)


@rpc("authority", "reliable", "call_local")
func load_map(map_path: String) -> void:
	var packed_scene := load(map_path)
	var instance = packed_scene.instantiate() as Node2D

	var old_map = current_map
	current_map = map_path

	var map_parent := get_map_parent()
	for map_object in map_parent.get_children():
		map_parent.remove_child(map_object)
		map_object.queue_free()

	map_switched.emit(old_map, current_map)
	map_parent.add_child(instance)


func get_scripts_parent() -> Node:
	return get_node("/root/Main/Scripts")


func get_map_parent() -> Node:
	return get_node("/root/Main/Game/Map")
