extends Node

enum ControlType {
	CLOSED,
	PLAYER,
	AI
}

enum MatchMode {
	SKIRMISH,
	ONLINE_PTP
}

const MAX_TEAMS := 8
const MAX_ONLINE_SEATS := 2

var match_mode: int = MatchMode.SKIRMISH

# Backward-compatible skirmish data.
var team_count: int = 2
var team_setups: Array[Dictionary] = []

# Shared match settings.
var starting_credits: int = 10
var base_credit_income_per_second: float = 1.0
var selected_map_path: String = ""
var selected_map_name: String = "No Map"

# Online/PTP data.
var local_player_team_id: int = 0
var online_is_host: bool = false


func _ready() -> void:
	reset_skirmish_defaults()


func reset_skirmish_defaults() -> void:
	match_mode = MatchMode.SKIRMISH
	online_is_host = false
	local_player_team_id = 0

	team_count = 2
	starting_credits = 10
	base_credit_income_per_second = 1.0
	clear_selected_map()

	team_setups.clear()

	for i in range(MAX_TEAMS):
		team_setups.append({
			"team_id": i,
			"name": "Team %d" % (i + 1),
			"control_type": ControlType.CLOSED,
			"seat_id": -1,
			"peer_id": 0
		})

	team_setups[0]["control_type"] = ControlType.PLAYER
	team_setups[0]["team_id"] = 0

	team_setups[1]["control_type"] = ControlType.AI
	team_setups[1]["team_id"] = 1


func reset_online_defaults() -> void:
	match_mode = MatchMode.ONLINE_PTP
	online_is_host = false
	local_player_team_id = 0

	# Keep all 8 team slots available so online players can choose any team index.
	team_count = MAX_TEAMS
	starting_credits = 10
	base_credit_income_per_second = 1.0
	clear_selected_map()

	team_setups.clear()

	for i in range(MAX_TEAMS):
		team_setups.append({
			"team_id": i,
			"name": "Team %d" % (i + 1),
			"control_type": ControlType.CLOSED,
			"seat_id": -1,
			"peer_id": 0
		})


func apply_online_lobby_state(lobby_state: Dictionary, local_peer_id: int) -> void:
	reset_online_defaults()

	match_mode = MatchMode.ONLINE_PTP

	selected_map_path = str(lobby_state.get("map_path", ""))
	selected_map_name = str(lobby_state.get("map_name", "No Map"))
	starting_credits = int(lobby_state.get("starting_credits", 10))
	base_credit_income_per_second = float(lobby_state.get("income_per_second", 1.0))

	var host_peer_id: int = int(lobby_state.get("host_peer_id", 1))
	online_is_host = local_peer_id == host_peer_id

	var seats: Array = lobby_state.get("seats", [])
	for seat_data in seats:
		var seat: Dictionary = seat_data
		var peer_id: int = int(seat.get("peer_id", 0))
		var team_id: int = int(seat.get("team_id", -1))

		if peer_id == 0:
			continue
		if team_id < 0 or team_id >= MAX_TEAMS:
			continue

		team_setups[team_id]["control_type"] = ControlType.PLAYER
		team_setups[team_id]["team_id"] = team_id
		team_setups[team_id]["seat_id"] = int(seat.get("seat_id", -1))
		team_setups[team_id]["peer_id"] = peer_id

		if peer_id == local_peer_id:
			local_player_team_id = team_id


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

	return int(team_setups[team_id]["control_type"])


func set_team_assignment(team_id: int, assigned_team_id: int) -> void:
	if team_id < 0 or team_id >= team_setups.size():
		return

	team_setups[team_id]["team_id"] = clamp(assigned_team_id, 0, MAX_TEAMS - 1)


func get_team_assignment(team_id: int) -> int:
	if team_id < 0 or team_id >= team_setups.size():
		return team_id

	return int(team_setups[team_id].get("team_id", team_id))


func set_starting_credits(value: int) -> void:
	starting_credits = max(value, 0)


func set_base_credit_income_per_second(value: float) -> void:
	base_credit_income_per_second = max(value, 0.0)


func get_active_teams() -> Array[Dictionary]:
	var active: Array[Dictionary] = []

	for i in range(team_count):
		var team_data: Dictionary = team_setups[i]
		if int(team_data["control_type"]) != ControlType.CLOSED:
			active.append(team_data)

	return active


func has_at_least_one_player() -> bool:
	for i in range(team_count):
		if int(team_setups[i]["control_type"]) == ControlType.PLAYER:
			return true

	return false


func can_start_skirmish() -> bool:
	var active_count: int = 0

	for i in range(team_count):
		if int(team_setups[i]["control_type"]) != ControlType.CLOSED:
			active_count += 1

	return active_count >= 2 and has_at_least_one_player()


func can_start_online_match() -> bool:
	var active_players: Array[int] = []

	for i in range(MAX_TEAMS):
		var setup: Dictionary = team_setups[i]
		if int(setup["control_type"]) == ControlType.PLAYER:
			active_players.append(int(setup["team_id"]))

	if active_players.size() != 2:
		return false

	return active_players[0] != active_players[1]
