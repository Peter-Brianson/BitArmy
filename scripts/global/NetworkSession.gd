class_name NetworkSession
extends Node

signal lobby_state_changed
signal hosting_started
signal joined_lobby
signal join_failed
signal disconnected
signal start_match_requested

const DEFAULT_PORT := 24567
const MAX_CLIENTS := 1

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var host_peer_id: int = 1

var lobby_team_count: int = 2
var lobby_map_path: String = ""
var lobby_map_name: String = "No Map"
var lobby_starting_credits: int = 10
var lobby_income_per_second: float = 1.0
var lobby_seats: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_multiplayer_signals()
	_reset_local_lobby()


func host_game(port: int = DEFAULT_PORT) -> Error:
	_close_existing_peer()

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		peer = null
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	host_peer_id = multiplayer.get_unique_id()

	_reset_host_lobby()

	hosting_started.emit()
	lobby_state_changed.emit()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	_close_existing_peer()

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		peer = null
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func disconnect_from_session() -> void:
	_close_existing_peer()
	disconnected.emit()


func set_lobby_map(path: String, display_name: String) -> void:
	if not is_host:
		return

	lobby_map_path = path
	lobby_map_name = display_name
	_broadcast_lobby_state()


func set_lobby_team_count(value: int) -> void:
	if not is_host:
		return

	lobby_team_count = clamp(value, 2, GameSession.MAX_TEAMS)
	_broadcast_lobby_state()


func set_lobby_starting_credits(value: int) -> void:
	if not is_host:
		return

	lobby_starting_credits = max(value, 0)
	_broadcast_lobby_state()


func set_lobby_income_per_second(value: float) -> void:
	if not is_host:
		return

	lobby_income_per_second = max(value, 0.0)
	_broadcast_lobby_state()


func set_seat_team(seat_id: int, team_id: int) -> void:
	if is_host:
		_set_seat_team_internal(seat_id, team_id)
		_broadcast_lobby_state()
	else:
		_server_request_set_seat_team.rpc_id(1, seat_id, team_id)


func set_seat_control_type(seat_id: int, control_type: int) -> void:
	if not is_host:
		return

	_set_seat_control_type_internal(seat_id, control_type)
	_broadcast_lobby_state()


func apply_lobby_to_game_session() -> void:
	GameSession.apply_online_lobby_state(_serialize_lobby_state(), multiplayer.get_unique_id())


func request_start_match() -> void:
	if not is_host:
		return

	_broadcast_lobby_state()
	_rpc_start_match.rpc()
	start_match_requested.emit()


func get_lobby_state() -> Dictionary:
	return _serialize_lobby_state()


func _connect_multiplayer_signals() -> void:
	var peer_connected_cb := Callable(self, "_on_peer_connected")
	if not multiplayer.peer_connected.is_connected(peer_connected_cb):
		multiplayer.peer_connected.connect(peer_connected_cb)

	var peer_disconnected_cb := Callable(self, "_on_peer_disconnected")
	if not multiplayer.peer_disconnected.is_connected(peer_disconnected_cb):
		multiplayer.peer_disconnected.connect(peer_disconnected_cb)

	var connected_cb := Callable(self, "_on_connected_to_server")
	if not multiplayer.connected_to_server.is_connected(connected_cb):
		multiplayer.connected_to_server.connect(connected_cb)

	var failed_cb := Callable(self, "_on_connection_failed")
	if not multiplayer.connection_failed.is_connected(failed_cb):
		multiplayer.connection_failed.connect(failed_cb)

	var server_disconnected_cb := Callable(self, "_on_server_disconnected")
	if not multiplayer.server_disconnected.is_connected(server_disconnected_cb):
		multiplayer.server_disconnected.connect(server_disconnected_cb)


func _close_existing_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null
	peer = null
	is_host = false
	host_peer_id = 1
	_reset_local_lobby()


func _reset_local_lobby() -> void:
	lobby_team_count = 2
	lobby_map_path = ""
	lobby_map_name = "No Map"
	lobby_starting_credits = 10
	lobby_income_per_second = 1.0

	lobby_seats.clear()
	for i in range(GameSession.MAX_TEAMS):
		lobby_seats.append({
			"seat_id": i,
			"peer_id": 0,
			"display_name": "Open",
			"team_id": i,
			"control_type": GameSession.ControlType.CLOSED
		})


func _reset_host_lobby() -> void:
	_reset_local_lobby()

	# Seat 1 = host player
	lobby_seats[0]["peer_id"] = multiplayer.get_unique_id()
	lobby_seats[0]["display_name"] = "Host"
	lobby_seats[0]["team_id"] = 0
	lobby_seats[0]["control_type"] = GameSession.ControlType.PLAYER

	# Seat 2 = open remote player slot
	lobby_seats[1]["peer_id"] = 0
	lobby_seats[1]["display_name"] = "Open"
	lobby_seats[1]["team_id"] = 1
	lobby_seats[1]["control_type"] = GameSession.ControlType.CLOSED

	# Seats 3..8 default closed
	for i in range(2, lobby_seats.size()):
		lobby_seats[i]["peer_id"] = 0
		lobby_seats[i]["display_name"] = "Open"
		lobby_seats[i]["team_id"] = i
		lobby_seats[i]["control_type"] = GameSession.ControlType.CLOSED


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return

	if _find_seat_for_peer(id) == -1:
		var empty_seat: int = _find_empty_remote_player_seat()
		if empty_seat != -1:
			lobby_seats[empty_seat]["peer_id"] = id
			lobby_seats[empty_seat]["display_name"] = "Client"
			lobby_seats[empty_seat]["control_type"] = GameSession.ControlType.PLAYER

	_broadcast_lobby_state()


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		var seat_id: int = _find_seat_for_peer(id)
		if seat_id != -1:
			lobby_seats[seat_id]["peer_id"] = 0
			lobby_seats[seat_id]["display_name"] = "Open"

			# Seat 2 stays as the reserved joinable player seat.
			if seat_id == 1:
				lobby_seats[seat_id]["control_type"] = GameSession.ControlType.CLOSED
			else:
				# AI seats remain whatever the host set them to if no peer was occupying them.
				if int(lobby_seats[seat_id]["control_type"]) == GameSession.ControlType.PLAYER:
					lobby_seats[seat_id]["control_type"] = GameSession.ControlType.CLOSED

			_broadcast_lobby_state()
	else:
		_close_existing_peer()
		disconnected.emit()


func _on_connected_to_server() -> void:
	joined_lobby.emit()
	_server_request_lobby_sync.rpc_id(1)


func _on_connection_failed() -> void:
	_close_existing_peer()
	join_failed.emit()


func _on_server_disconnected() -> void:
	_close_existing_peer()
	disconnected.emit()


func _find_seat_for_peer(peer_id: int) -> int:
	for i in range(lobby_seats.size()):
		if int(lobby_seats[i]["peer_id"]) == peer_id:
			return i

	return -1


func _find_empty_remote_player_seat() -> int:
	# First try the dedicated second seat.
	if lobby_seats.size() > 1 and int(lobby_seats[1]["peer_id"]) == 0:
		return 1

	# Fallback: find any closed/open player-eligible seat.
	for i in range(1, min(lobby_team_count, lobby_seats.size())):
		if int(lobby_seats[i]["peer_id"]) == 0 and int(lobby_seats[i]["control_type"]) != GameSession.ControlType.AI:
			return i

	return -1


func _set_seat_team_internal(seat_id: int, team_id: int) -> void:
	if seat_id < 0 or seat_id >= lobby_seats.size():
		return

	var safe_team_id: int = clamp(team_id, 0, GameSession.MAX_TEAMS - 1)
	lobby_seats[seat_id]["team_id"] = safe_team_id


func _set_seat_control_type_internal(seat_id: int, control_type: int) -> void:
	if seat_id < 0 or seat_id >= lobby_seats.size():
		return

	# Seat 0 is always the host player.
	if seat_id == 0:
		lobby_seats[seat_id]["control_type"] = GameSession.ControlType.PLAYER
		return

	var safe_type: int = clamp(control_type, GameSession.ControlType.CLOSED, GameSession.ControlType.AI)

	# If a remote peer occupies the seat, it must remain PLAYER.
	if int(lobby_seats[seat_id]["peer_id"]) != 0:
		lobby_seats[seat_id]["control_type"] = GameSession.ControlType.PLAYER
		return

	lobby_seats[seat_id]["control_type"] = safe_type


func _can_peer_edit_seat(peer_id: int, seat_id: int) -> bool:
	if seat_id < 0 or seat_id >= lobby_seats.size():
		return false

	return int(lobby_seats[seat_id]["peer_id"]) == peer_id


func _broadcast_lobby_state() -> void:
	var state: Dictionary = _serialize_lobby_state()
	lobby_state_changed.emit()

	if is_host:
		_rpc_receive_lobby_state.rpc(state)


func _serialize_lobby_state() -> Dictionary:
	return {
		"host_peer_id": host_peer_id,
		"team_count": lobby_team_count,
		"map_path": lobby_map_path,
		"map_name": lobby_map_name,
		"starting_credits": lobby_starting_credits,
		"income_per_second": lobby_income_per_second,
		"seats": lobby_seats.duplicate(true)
	}


func _deserialize_lobby_state(state: Dictionary) -> void:
	host_peer_id = int(state.get("host_peer_id", 1))
	lobby_team_count = int(state.get("team_count", 2))
	lobby_map_path = str(state.get("map_path", ""))
	lobby_map_name = str(state.get("map_name", "No Map"))
	lobby_starting_credits = int(state.get("starting_credits", 10))
	lobby_income_per_second = float(state.get("income_per_second", 1.0))
	lobby_seats = state.get("seats", []).duplicate(true)


@rpc("any_peer", "reliable")
func _server_request_lobby_sync() -> void:
	if not is_host:
		return

	_rpc_receive_lobby_state.rpc(_serialize_lobby_state())


@rpc("any_peer", "reliable")
func _server_request_set_seat_team(seat_id: int, team_id: int) -> void:
	if not is_host:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _can_peer_edit_seat(sender_id, seat_id):
		return

	_set_seat_team_internal(seat_id, team_id)
	_broadcast_lobby_state()


@rpc("authority", "reliable")
func _rpc_receive_lobby_state(state: Dictionary) -> void:
	_deserialize_lobby_state(state)
	lobby_state_changed.emit()


@rpc("authority", "reliable")
func _rpc_start_match() -> void:
	start_match_requested.emit()
