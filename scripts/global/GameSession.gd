extends Node

enum ControlType {
	CLOSED,
	PLAYER,
	AI
}

const MAX_TEAMS := 8

var team_count: int = 2
var team_setups: Array[Dictionary] = []

var starting_credits: int = 500
var base_credit_income_per_second: float = 5.0

var selected_map_path: String = ""
var selected_map_name: String = "No Map"

func _ready() -> void:
	reset_skirmish_defaults()


func reset_skirmish_defaults() -> void:
	team_count = 2
	starting_credits = 10
	base_credit_income_per_second = 1
	clear_selected_map()
	team_setups.clear()

	for i in range(MAX_TEAMS):
		team_setups.append({
			"team_id": i,
			"name": "Team %d" % (i + 1),
			"control_type": ControlType.CLOSED
		})

	team_setups[0]["control_type"] = ControlType.PLAYER
	team_setups[1]["control_type"] = ControlType.AI

func set_selected_map(path: String, display_name: String) -> void:
	selected_map_path = path
	selected_map_name = display_name


func clear_selected_map() -> void:
	selected_map_path = ""
	selected_map_name = "No Map"


func set_team_count(value: int) -> void:
	team_count = clamp(value, 2, MAX_TEAMS)


func set_team_control_type(team_id: int, control_type: int) -> void:
	if team_id < 0 or team_id >= team_setups.size():
		return
	team_setups[team_id]["control_type"] = control_type


func get_team_control_type(team_id: int) -> int:
	if team_id < 0 or team_id >= team_setups.size():
		return ControlType.CLOSED
	return team_setups[team_id]["control_type"]


func set_starting_credits(value: int) -> void:
	starting_credits = max(value, 0)


func set_base_credit_income_per_second(value: float) -> void:
	base_credit_income_per_second = max(value, 0.0)


func get_active_teams() -> Array[Dictionary]:
	var active: Array[Dictionary] = []

	for i in range(team_count):
		var team_data: Dictionary = team_setups[i]
		if team_data["control_type"] != ControlType.CLOSED:
			active.append(team_data)

	return active


func has_at_least_one_player() -> bool:
	for i in range(team_count):
		if team_setups[i]["control_type"] == ControlType.PLAYER:
			return true
	return false


func can_start_skirmish() -> bool:
	var active_count: int = 0

	for i in range(team_count):
		if team_setups[i]["control_type"] != ControlType.CLOSED:
			active_count += 1

	return active_count >= 2 and has_at_least_one_player()
