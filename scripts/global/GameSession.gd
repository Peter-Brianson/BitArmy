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
const MAX_SEATS := 8

var match_mode: int = MatchMode.SKIRMISH

# Team-centric data consumed by match setup.
var team_count: int = 2
var team_setups: Array[Dictionary] = []

# Seat-centric lobby data for online / future unified menus.
var seat_setups: Array[Dictionary] = []

# Shared match settings.
var starting_credits: int = 100
var base_credit_income_per_second: float = 1.0
var selected_map_path: String = ""
var selected_map_name: String = "No Map"

# Online state.
var local_peer_id: int = 1
var local_player_team_id: int = 0
var online_is_host: bool = false


func _ready() -> void:
	reset_skirmish_defaults()


func reset_skirmish_defaults() -> void:
	match_mode = MatchMode.SKIRMISH
	local_peer_id = 1
	local_player_team_id = 0
	online_is_host = false

	team_count = 2
	starting_credits = 100
	base_credit_income_per_second = 1.0
	clear_selected_map()

	_init_empty_team_setups()
	_init_empty_seat_setups()

	# Default offline skirmish seats/teams.
	seat_setups[0]["control_type"] = ControlType.PLAYER
	seat_setups[0]["team_id"] = 0
	seat_setups[0]["display_name"] = "Player"

	seat_setups[1]["control_type"] = ControlType.AI
	seat_setups[1]["team_id"] = 1
	seat_setups[1]["display_name"] = "AI"

	_rebuild_team_setups_from_seats()


func reset_online_defaults() -> void:
	match_mode = MatchMode.ONLINE_PTP
	local_peer_id = 1
	local_player_team_id = 0
	online_is_host = false

	team_count = 2
	starting_credits = 100
	base_credit_income_per_second = 1.0
	clear_selected_map()

	_init_empty_team_setups()
	_init_empty_seat_setups()


func apply_online_lobby_state(lobby_state: Dictionary, p_local_peer_id: int) -> void:
	reset_online_defaults()

	match_mode = MatchMode.ONLINE_PTP
	local_peer_id = p_local_peer_id

	team_count = clamp(int(lobby_state.get("team_count", 2)), 2, MAX_TEAMS)
	selected_map_path = str(lobby_state.get("map_path", ""))
	selected_map_name = str(lobby_state.get("map_name", "No Map"))
	starting_credits = int(lobby_state.get("starting_credits", 100))
	base_credit_income_per_second = float(lobby_state.get("income_per_second", 1.0))

	var host_peer_id: int = int(lobby_state.get("host_peer_id", 1))
	online_is_host = local_peer_id == host_peer_id

	var incoming_seats: Array = lobby_state.get("seats", [])
	for i in range(min(incoming_seats.size(), MAX_SEATS)):
		var incoming: Dictionary = incoming_seats[i]
		seat_setups[i] = {
			"seat_id": int(incoming.get("seat_id", i)),
			"peer_id": int(incoming.get("peer_id", 0)),
			"display_name": str(incoming.get("display_name", "Open")),
			"team_id": clamp(int(incoming.get("team_id", i)), 0, MAX_TEAMS - 1),
			"control_type": int(incoming.get("control_type", ControlType.CLOSED))
		}

	_rebuild_team_setups_from_seats()


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

	return int(team_setups[team_id].get("control_type", ControlType.CLOSED))


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
		if int(team_data.get("control_type", ControlType.CLOSED)) != ControlType.CLOSED:
			active.append(team_data)

	return active


func has_at_least_one_player() -> bool:
	for i in range(team_count):
		if int(team_setups[i].get("control_type", ControlType.CLOSED)) == ControlType.PLAYER:
			return true
	return false


func can_start_skirmish() -> bool:
	var active_count: int = 0

	for i in range(team_count):
		if int(team_setups[i].get("control_type", ControlType.CLOSED)) != ControlType.CLOSED:
			active_count += 1

	return active_count >= 2 and has_at_least_one_player()


func can_start_online_match() -> bool:
	var active_team_ids: Array[int] = []
	var player_count: int = 0

	for i in range(MAX_SEATS):
		var seat: Dictionary = seat_setups[i]
		var control_type: int = int(seat.get("control_type", ControlType.CLOSED))

		if control_type == ControlType.CLOSED:
			continue

		var team_id: int = clamp(int(seat.get("team_id", 0)), 0, MAX_TEAMS - 1)

		if team_id not in active_team_ids:
			active_team_ids.append(team_id)

		if control_type == ControlType.PLAYER:
			player_count += 1

	return player_count >= 2 and active_team_ids.size() >= 2


func _init_empty_team_setups() -> void:
	team_setups.clear()

	for i in range(MAX_TEAMS):
		team_setups.append({
			"team_id": i,
			"name": "Team %d" % (i + 1),
			"control_type": ControlType.CLOSED,
			"seat_ids": []
		})


func _init_empty_seat_setups() -> void:
	seat_setups.clear()

	for i in range(MAX_SEATS):
		seat_setups.append({
			"seat_id": i,
			"peer_id": 0,
			"display_name": "Open",
			"team_id": i,
			"control_type": ControlType.CLOSED
		})


func _rebuild_team_setups_from_seats() -> void:
	_init_empty_team_setups()
	local_player_team_id = 0

	for i in range(MAX_SEATS):
		var seat: Dictionary = seat_setups[i]
		var control_type: int = int(seat.get("control_type", ControlType.CLOSED))

		if control_type == ControlType.CLOSED:
			continue

		var assigned_team_id: int = clamp(int(seat.get("team_id", 0)), 0, MAX_TEAMS - 1)
		var peer_id: int = int(seat.get("peer_id", 0))

		var team_entry: Dictionary = team_setups[assigned_team_id]
		var seat_ids: Array = team_entry.get("seat_ids", [])
		seat_ids.append(i)
		team_entry["seat_ids"] = seat_ids

		# If any human is on a team, the team is treated as PLAYER for match setup.
		if control_type == ControlType.PLAYER:
			team_entry["control_type"] = ControlType.PLAYER
		elif int(team_entry.get("control_type", ControlType.CLOSED)) != ControlType.PLAYER:
			team_entry["control_type"] = ControlType.AI

		team_setups[assigned_team_id] = team_entry

		if peer_id == local_peer_id and control_type == ControlType.PLAYER:
			local_player_team_id = assigned_team_id
