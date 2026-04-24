extends Node

enum ControlType { CLOSED, PLAYER, AI }
enum MatchMode { SKIRMISH, ONLINE_PTP }

const MAX_TEAMS := 8
const MAX_SEATS := 8

var match_mode: int = MatchMode.SKIRMISH

# team_count now means active member slots, not unique alliances.
var team_count: int = 2

# Each entry is a match member/economy/HQ slot.
# member_id/slot index = owner runtime id.
# team_id = alliance/color id.
var team_setups: Array[Dictionary] = []

# Online/future lobby seats. Each seat becomes one member slot.
var seat_setups: Array[Dictionary] = []

var starting_credits: int = 100
var base_credit_income_per_second: float = 1.0

var selected_map_path: String = ""
var selected_map_name: String = "No Map"

var local_peer_id: int = 1

# Important: now this means local runtime member slot, not alliance id.
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

	team_setups[0]["control_type"] = ControlType.PLAYER
	team_setups[0]["team_id"] = 0
	team_setups[0]["display_name"] = "Player"

	team_setups[1]["control_type"] = ControlType.AI
	team_setups[1]["team_id"] = 1
	team_setups[1]["display_name"] = "AI"


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

	_rebuild_member_setups_from_seats()


func set_selected_map(path: String, display_name: String) -> void:
	selected_map_path = path
	selected_map_name = display_name


func clear_selected_map() -> void:
	selected_map_path = ""
	selected_map_name = "No Map"


func set_team_count(value: int) -> void:
	team_count = clamp(value, 2, MAX_TEAMS)


func set_team_control_type(member_id: int, control_type: int) -> void:
	if member_id < 0 or member_id >= team_setups.size():
		return

	team_setups[member_id]["control_type"] = control_type


func get_team_control_type(member_id: int) -> int:
	if member_id < 0 or member_id >= team_setups.size():
		return ControlType.CLOSED

	return int(team_setups[member_id].get("control_type", ControlType.CLOSED))


func set_team_assignment(member_id: int, alliance_team_id: int) -> void:
	if member_id < 0 or member_id >= team_setups.size():
		return

	team_setups[member_id]["team_id"] = clamp(alliance_team_id, 0, MAX_TEAMS - 1)


func get_team_assignment(member_id: int) -> int:
	if member_id < 0 or member_id >= team_setups.size():
		return member_id

	return int(team_setups[member_id].get("team_id", member_id))


func set_starting_credits(value: int) -> void:
	starting_credits = max(value, 0)


func set_base_credit_income_per_second(value: float) -> void:
	base_credit_income_per_second = max(value, 0.0)


func get_active_members() -> Array[Dictionary]:
	var active: Array[Dictionary] = []

	for member_id in range(team_count):
		var member_data: Dictionary = team_setups[member_id]
		var control_type: int = int(member_data.get("control_type", ControlType.CLOSED))

		if control_type == ControlType.CLOSED:
			continue

		var entry: Dictionary = member_data.duplicate(true)
		entry["member_id"] = member_id
		entry["slot_id"] = member_id
		entry["runtime_team_id"] = member_id
		entry["team_id"] = clamp(int(entry.get("team_id", member_id)), 0, MAX_TEAMS - 1)

		active.append(entry)

	return active


# Backward-compatible name for older scripts.
func get_active_teams() -> Array[Dictionary]:
	return get_active_members()


func has_at_least_one_player() -> bool:
	for member_id in range(team_count):
		if int(team_setups[member_id].get("control_type", ControlType.CLOSED)) == ControlType.PLAYER:
			return true

	return false


func get_active_alliance_count() -> int:
	var alliance_ids: Array[int] = []

	for member in get_active_members():
		var alliance_id: int = int(member.get("team_id", 0))

		if not alliance_ids.has(alliance_id):
			alliance_ids.append(alliance_id)

	return alliance_ids.size()


func can_start_skirmish() -> bool:
	var active_count: int = get_active_members().size()

	return (
		active_count >= 2
		and has_at_least_one_player()
		and get_active_alliance_count() >= 2
	)


func can_start_online_match() -> bool:
	var player_count: int = 0
	var alliance_ids: Array[int] = []

	for i in range(MAX_SEATS):
		var seat: Dictionary = seat_setups[i]
		var control_type: int = int(seat.get("control_type", ControlType.CLOSED))

		if control_type == ControlType.CLOSED:
			continue

		var alliance_id: int = clamp(int(seat.get("team_id", 0)), 0, MAX_TEAMS - 1)

		if not alliance_ids.has(alliance_id):
			alliance_ids.append(alliance_id)

		if control_type == ControlType.PLAYER:
			player_count += 1

	return player_count >= 2 and alliance_ids.size() >= 2


func _init_empty_team_setups() -> void:
	team_setups.clear()

	for i in range(MAX_TEAMS):
		team_setups.append({
			"member_id": i,
			"slot_id": i,
			"runtime_team_id": i,
			"team_id": i,
			"name": "Member %d" % (i + 1),
			"display_name": "Member %d" % (i + 1),
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


func _rebuild_member_setups_from_seats() -> void:
	_init_empty_team_setups()
	local_player_team_id = 0

	for i in range(MAX_SEATS):
		if i >= MAX_TEAMS:
			break

		var seat: Dictionary = seat_setups[i]
		var control_type: int = int(seat.get("control_type", ControlType.CLOSED))

		if control_type == ControlType.CLOSED:
			continue

		var alliance_team_id: int = clamp(int(seat.get("team_id", i)), 0, MAX_TEAMS - 1)
		var peer_id: int = int(seat.get("peer_id", 0))

		team_setups[i] = {
			"member_id": i,
			"slot_id": i,
			"runtime_team_id": i,
			"team_id": alliance_team_id,
			"name": str(seat.get("display_name", "Member %d" % (i + 1))),
			"display_name": str(seat.get("display_name", "Member %d" % (i + 1))),
			"control_type": control_type,
			"seat_ids": [i]
		}

		if peer_id == local_peer_id and control_type == ControlType.PLAYER:
			local_player_team_id = i
