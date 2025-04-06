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
