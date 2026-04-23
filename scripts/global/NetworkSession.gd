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

enum TransportMode {
	ENET,
	WEBRTC
}

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var host_peer_id: int = 1

var transport_mode: int = TransportMode.ENET
var webrtc_signaling_url: String = "wss://bitarmy-signaling.juryriggedworks.workers.dev"
var webrtc_room_code: String = "default"

var lobby_team_count: int = 2
var lobby_map_path: String = ""
var lobby_map_name: String = "No Map"
var lobby_starting_credits: int = 10
var lobby_income_per_second: float = 1.0
var lobby_seats: Array[Dictionary] = []

var _webrtc_multiplayer_peer: WebRTCMultiplayerPeer = null
var _webrtc_connections: Dictionary = {}
var _signaling_socket: WebSocketPeer = null
var _signaling_join_sent: bool = false
var _webrtc_local_peer_id: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_multiplayer_signals()
	_reset_local_lobby()


func _process(_delta: float) -> void:
	_poll_signaling_socket()
	_poll_webrtc_connections()


func set_transport_mode(mode: int) -> void:
	if multiplayer.multiplayer_peer != null:
		return

	transport_mode = clamp(mode, TransportMode.ENET, TransportMode.WEBRTC)


func get_transport_display_name() -> String:
	match transport_mode:
		TransportMode.WEBRTC:
			return "WebRTC"
		_:
			return "ENet"


func set_webrtc_signaling_url(value: String) -> void:
	if multiplayer.multiplayer_peer != null:
		return

	webrtc_signaling_url = value.strip_edges()


func set_webrtc_room_code(value: String) -> void:
	if multiplayer.multiplayer_peer != null:
		return

	var trimmed: String = value.strip_edges()
	webrtc_room_code = trimmed if trimmed != "" else "default"


func host_game(port: int = DEFAULT_PORT) -> Error:
	match transport_mode:
		TransportMode.WEBRTC:
			return _host_game_webrtc()
		_:
			return _host_game_enet(port)


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	match transport_mode:
		TransportMode.WEBRTC:
			return _join_game_webrtc()
		_:
			return _join_game_enet(ip, port)


func _host_game_enet(port: int = DEFAULT_PORT) -> Error:
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


func _join_game_enet(ip: String, port: int = DEFAULT_PORT) -> Error:
	_close_existing_peer()

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		peer = null
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func _host_game_webrtc() -> Error:
	_close_existing_peer()

	if webrtc_signaling_url == "":
		return ERR_CANT_CONNECT

	_webrtc_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var err: Error = _webrtc_multiplayer_peer.create_server()
	if err != OK:
		_webrtc_multiplayer_peer = null
		return err

	multiplayer.multiplayer_peer = _webrtc_multiplayer_peer
	is_host = true
	host_peer_id = 1
	_webrtc_local_peer_id = 1

	_reset_host_lobby()

	err = _connect_signaling_socket()
	if err != OK:
		_close_existing_peer()
		return err

	hosting_started.emit()
	lobby_state_changed.emit()
	return OK


func _join_game_webrtc() -> Error:
	_close_existing_peer()

	if webrtc_signaling_url == "":
		return ERR_CANT_CONNECT

	_webrtc_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var err: Error = _webrtc_multiplayer_peer.create_client(2)
	if err != OK:
		_webrtc_multiplayer_peer = null
		return err

	multiplayer.multiplayer_peer = _webrtc_multiplayer_peer
	is_host = false
	host_peer_id = 1
	_webrtc_local_peer_id = 2

	err = _connect_signaling_socket()
	if err != OK:
		_close_existing_peer()
		return err

	return OK


func _connect_signaling_socket() -> Error:
	_signaling_socket = WebSocketPeer.new()
	_signaling_join_sent = false

	var url: String = _get_signaling_room_url()
	if url == "":
		return ERR_CANT_CONNECT

	return _signaling_socket.connect_to_url(url)


func _get_signaling_room_url() -> String:
	var base: String = webrtc_signaling_url.strip_edges()
	if base == "":
		return ""

	if base.ends_with("/"):
		base = base.substr(0, base.length() - 1)

	var room: String = webrtc_room_code.strip_edges()
	if room == "":
		room = "default"

	return "%s/room/%s" % [base, room]


func _poll_signaling_socket() -> void:
	if _signaling_socket == null:
		return

	_signaling_socket.poll()
	var state: int = _signaling_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _signaling_join_sent:
			_signaling_join_sent = true
			_send_signaling_message({
				"type": "join_room",
				"role": "host" if is_host else "client",
				"peer_id": _webrtc_local_peer_id
			})

		while _signaling_socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _signaling_socket.get_packet()
			var text: String = packet.get_string_from_utf8()
			var data = JSON.parse_string(text)

			if typeof(data) == TYPE_DICTIONARY:
				_handle_signaling_message(data)

	elif state == WebSocketPeer.STATE_CLOSED:
		if multiplayer.multiplayer_peer == null:
			return


func _poll_webrtc_connections() -> void:
	for remote_peer_id in _webrtc_connections.keys():
		var connection: WebRTCPeerConnection = _webrtc_connections[remote_peer_id]
		if connection != null:
			connection.poll()


func _handle_signaling_message(data: Dictionary) -> void:
	var from_peer_id: int = int(data.get("peer_id", data.get("from", -1)))
	if from_peer_id == _webrtc_local_peer_id:
		return

	var message_type: String = str(data.get("type", ""))

	match message_type:
		"join_room":
			var role: String = str(data.get("role", ""))

			if is_host and role == "client":
				var connection: WebRTCPeerConnection = _ensure_webrtc_connection(2)
				if connection != null and connection.get_signaling_state() == WebRTCPeerConnection.SIGNALING_STATE_STABLE:
					connection.create_offer()

		"sdp":
			var to_peer_id: int = int(data.get("to", -1))
			if to_peer_id != _webrtc_local_peer_id:
				return

			var remote_peer_id: int = int(data.get("from", -1))
			var connection: WebRTCPeerConnection = _ensure_webrtc_connection(remote_peer_id)
			if connection == null:
				return

			var description_type: String = str(data.get("description_type", "offer"))
			var sdp: String = str(data.get("sdp", ""))
			connection.set_remote_description(description_type, sdp)

		"ice":
			var to_peer_id: int = int(data.get("to", -1))
			if to_peer_id != _webrtc_local_peer_id:
				return

			var remote_peer_id: int = int(data.get("from", -1))
			var connection: WebRTCPeerConnection = _ensure_webrtc_connection(remote_peer_id)
			if connection == null:
				return

			connection.add_ice_candidate(
				str(data.get("media", "")),
				int(data.get("index", 0)),
				str(data.get("name", ""))
			)


func _ensure_webrtc_connection(remote_peer_id: int) -> WebRTCPeerConnection:
	if _webrtc_connections.has(remote_peer_id):
		return _webrtc_connections[remote_peer_id]

	if _webrtc_multiplayer_peer == null:
		return null

	var connection := WebRTCPeerConnection.new()
	var err: Error = connection.initialize({})
	if err != OK:
		return null

	connection.session_description_created.connect(
		Callable(self, "_on_webrtc_session_description_created").bind(remote_peer_id)
	)
	connection.ice_candidate_created.connect(
		Callable(self, "_on_webrtc_ice_candidate_created").bind(remote_peer_id)
	)

	err = _webrtc_multiplayer_peer.add_peer(connection, remote_peer_id)
	if err != OK:
		connection.close()
		return null

	_webrtc_connections[remote_peer_id] = connection
	return connection


func _on_webrtc_session_description_created(type: String, sdp: String, remote_peer_id: int) -> void:
	var connection: WebRTCPeerConnection = _webrtc_connections.get(remote_peer_id, null)
	if connection == null:
		return

	connection.set_local_description(type, sdp)

	_send_signaling_message({
		"type": "sdp",
		"from": _webrtc_local_peer_id,
		"to": remote_peer_id,
		"description_type": type,
		"sdp": sdp
	})


func _on_webrtc_ice_candidate_created(media: String, index: int, name: String, remote_peer_id: int) -> void:
	_send_signaling_message({
		"type": "ice",
		"from": _webrtc_local_peer_id,
		"to": remote_peer_id,
		"media": media,
		"index": index,
		"name": name
	})


func _send_signaling_message(data: Dictionary) -> void:
	if _signaling_socket == null:
		return
	if _signaling_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_signaling_socket.send_text(JSON.stringify(data))


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

	for i in range(lobby_team_count, lobby_seats.size()):
		if i == 0:
			continue
		if int(lobby_seats[i]["peer_id"]) == 0:
			lobby_seats[i]["control_type"] = GameSession.ControlType.CLOSED

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
	if _signaling_socket != null:
		_signaling_socket.close()
	_signaling_socket = null
	_signaling_join_sent = false

	for remote_peer_id in _webrtc_connections.keys():
		var connection: WebRTCPeerConnection = _webrtc_connections[remote_peer_id]
		if connection != null:
			connection.close()
	_webrtc_connections.clear()
	_webrtc_multiplayer_peer = null

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null
	peer = null
	is_host = false
	host_peer_id = 1
	_webrtc_local_peer_id = 1
	_reset_local_lobby()


func _reset_local_lobby() -> void:
	lobby_team_count = 2
	lobby_map_path = ""
	lobby_map_name = "No Map"
	lobby_starting_credits = 10
	lobby_income_per_second = 1.0
	lobby_seats.clear()

	for i in range(GameSession.MAX_SEATS):
		lobby_seats.append({
			"seat_id": i,
			"peer_id": 0,
			"display_name": "Open",
			"team_id": i,
			"control_type": GameSession.ControlType.CLOSED
		})


func _reset_host_lobby() -> void:
	_reset_local_lobby()

	lobby_seats[0]["peer_id"] = 1
	lobby_seats[0]["display_name"] = "Host"
	lobby_seats[0]["team_id"] = 0
	lobby_seats[0]["control_type"] = GameSession.ControlType.PLAYER

	lobby_seats[1]["peer_id"] = 0
	lobby_seats[1]["display_name"] = "Open"
	lobby_seats[1]["team_id"] = 1
	lobby_seats[1]["control_type"] = GameSession.ControlType.CLOSED


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

			if seat_id == 1:
				lobby_seats[seat_id]["control_type"] = GameSession.ControlType.CLOSED
			elif int(lobby_seats[seat_id]["control_type"]) == GameSession.ControlType.PLAYER:
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
	if lobby_seats.size() > 1 and int(lobby_seats[1]["peer_id"]) == 0:
		return 1

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

	if seat_id == 0:
		lobby_seats[seat_id]["control_type"] = GameSession.ControlType.PLAYER
		return

	var safe_type: int = clamp(control_type, GameSession.ControlType.CLOSED, GameSession.ControlType.AI)

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
		"transport_mode": transport_mode,
		"webrtc_signaling_url": webrtc_signaling_url,
		"webrtc_room_code": webrtc_room_code,
		"host_peer_id": host_peer_id,
		"team_count": lobby_team_count,
		"map_path": lobby_map_path,
		"map_name": lobby_map_name,
		"starting_credits": lobby_starting_credits,
		"income_per_second": lobby_income_per_second,
		"seats": lobby_seats.duplicate(true)
	}


func _deserialize_lobby_state(state: Dictionary) -> void:
	transport_mode = int(state.get("transport_mode", TransportMode.ENET))
	webrtc_signaling_url = str(state.get("webrtc_signaling_url", ""))
	webrtc_room_code = str(state.get("webrtc_room_code", "default"))
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
