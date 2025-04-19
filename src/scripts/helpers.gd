extends Node
class_name Helpers

static func get_direction_string_from_angle(angle_rad: float) -> String:
	var angle_deg := rad_to_deg(angle_rad)
	if angle_deg > 75 and angle_deg < 115:
		return "vertical"
	elif angle_deg > 30 and angle_deg < 150:
		return "diagonal_up"
	elif angle_deg < -30 and angle_deg > -150:
		return "diagonal_down"
	else:
		return "horizontal"


static func get_node_props(node: Node, prop_names: Array[String]) -> Dictionary:
	var out: Dictionary
	for prop_name in prop_names:
		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		out[prop_name] = node.get_node(node_path).get(node_prop)
	return out


static func set_node_props(node: Node, props: Dictionary) -> void:
	for prop_name in props.keys():
		var split := prop_name.split(":") as PackedStringArray
		var node_path := "."
		var node_prop := ""
		if split.size() == 1:
			node_prop = split[0]
		else:
			node_path = split[0]
			node_prop = split[1]
		node.get_node(node_path).set(node_prop, props[prop_name])
