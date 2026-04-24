class_name P2PVersusMenuController
extends Control

@export var match_scene_path: String = "res://scenes/main/MainMatch.tscn"

@export var return_scene_path: String = "res://scenes/ui/P2PVersusMenu.tscn"

@export_group("Main")
@export var main_panel: Control

@export_group("Network")
@export var transport_option: OptionButton
@export var signaling_url_line_edit: LineEdit
@export var room_code_line_edit: LineEdit
@export var host_button: Button
@export var join_button: Button
@export var disconnect_button: Button
@export var ip_line_edit: LineEdit
@export var port_spinbox: SpinBox
@export var connection_status_label: Label

@export_group("Match Settings")
@export var map_option: OptionButton
@export var available_maps: Array[PackedScene] = []
@export var team_count_option: OptionButton
@export var starting_credits_spinbox: SpinBox
@export var income_spinbox: SpinBox
@export var help_label: Label

@export_group("Seats")
@export var seat_rows_container: VBoxContainer

@export_group("Buttons")
@export var start_match_button: Button
@export var back_button: Button

const DEFAULT_MAP_PATHS: Array[String] = [
	"res://Maps/Ready Maps/Grass Land.tscn",
	"res://Maps/Ready Maps/Desert.tscn",
]

var _seat_rows: Array[Dictionary] = []
var _map_entries: Array[Dictionary] = []
var _is_refreshing_ui: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mouse_filter_fail_safe(self)

	if multiplayer.multiplayer_peer != null:
		NetworkHub.disconnect_from_session()

	GameSession.reset_online_defaults()

	_collect_seat_rows()
	_setup_network_controls()
	_setup_match_settings_controls()
	_bind_network_signals()
	_refresh_from_lobby_state()

	if start_match_button != null:
		start_match_button.grab_focus()

	_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _process(_delta: float) -> void:
	_refresh_button_states()


func _collect_seat_rows() -> void:
	_seat_rows.clear()

	if seat_rows_container == null:
		return

	for row in seat_rows_container.get_children():
		if not row is HBoxContainer:
			continue

		var row_box: HBoxContainer = row
		var seat_label: Label = row_box.get_node_or_null("SeatLabel")
		var occupancy_label: Label = row_box.get_node_or_null("OccupancyLabel")
		var control_option: OptionButton = row_box.get_node_or_null("ControlTypeOption")
		var team_option: OptionButton = row_box.get_node_or_null("TeamOption")

		_seat_rows.append({
			"row": row_box,
			"seat_label": seat_label,
			"occupancy_label": occupancy_label,
			"control_option": control_option,
			"team_option": team_option,
		})


func _setup_network_controls() -> void:
	if transport_option != null:
		transport_option.clear()
		transport_option.add_item("Direct IP (ENet)", NetworkHub.TransportMode.ENET)
		transport_option.add_item("Browser P2P (WebRTC)", NetworkHub.TransportMode.WEBRTC)
		transport_option.item_selected.connect(_on_transport_selected)

	if signaling_url_line_edit != null:
		signaling_url_line_edit.text = NetworkHub.webrtc_signaling_url
		signaling_url_line_edit.text_changed.connect(_on_signaling_url_changed)

	if room_code_line_edit != null:
		room_code_line_edit.text = NetworkHub.webrtc_room_code
		room_code_line_edit.text_changed.connect(_on_room_code_changed)

	if port_spinbox != null:
		port_spinbox.min_value = 1
		port_spinbox.max_value = 65535
		port_spinbox.step = 1
		port_spinbox.value = NetworkHub.DEFAULT_PORT

	if host_button != null:
		host_button.pressed.connect(_on_host_pressed)

	if join_button != null:
		join_button.pressed.connect(_on_join_pressed)

	if disconnect_button != null:
		disconnect_button.pressed.connect(_on_disconnect_pressed)

	if connection_status_label != null:
		connection_status_label.text = "Offline"


func _setup_match_settings_controls() -> void:
	if map_option != null:
		_setup_map_option()

	if team_count_option != null:
		_setup_team_count_option()

	if starting_credits_spinbox != null:
		starting_credits_spinbox.min_value = 0
		starting_credits_spinbox.max_value = 100000
		starting_credits_spinbox.step = 10
		starting_credits_spinbox.value = GameSession.starting_credits
		starting_credits_spinbox.value_changed.connect(_on_starting_credits_changed)

	if income_spinbox != null:
		income_spinbox.min_value = 0
		income_spinbox.max_value = 1000
		income_spinbox.step = 1
		income_spinbox.value = GameSession.base_credit_income_per_second
		income_spinbox.value_changed.connect(_on_income_changed)

	if start_match_button != null:
		start_match_button.pressed.connect(_on_start_match_pressed)

	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)

	if help_label != null:
		help_label.text = "Choose ENet for direct IP.\nChoose WebRTC for browser-friendly play using your signaling server."


func _bind_network_signals() -> void:
	if not NetworkHub.hosting_started.is_connected(_on_hosting_started):
		NetworkHub.hosting_started.connect(_on_hosting_started)

	if not NetworkHub.joined_lobby.is_connected(_on_joined_lobby):
		NetworkHub.joined_lobby.connect(_on_joined_lobby)

	if not NetworkHub.join_failed.is_connected(_on_join_failed):
		NetworkHub.join_failed.connect(_on_join_failed)

	if not NetworkHub.disconnected.is_connected(_on_disconnected):
		NetworkHub.disconnected.connect(_on_disconnected)

	if not NetworkHub.lobby_state_changed.is_connected(_on_lobby_state_changed):
		NetworkHub.lobby_state_changed.connect(_on_lobby_state_changed)

	if not NetworkHub.start_match_requested.is_connected(_on_start_match_requested):
		NetworkHub.start_match_requested.connect(_on_start_match_requested)


func _setup_map_option() -> void:
	_rebuild_map_entries()

	map_option.clear()

	if _map_entries.is_empty():
		map_option.add_item("No maps found", -1)
		map_option.select(0)
		GameSession.clear_selected_map()
		push_warning("P2PVersusMenu: no usable maps found. Check available_maps or DEFAULT_MAP_PATHS.")
		return

	for i in range(_map_entries.size()):
		var entry: Dictionary = _map_entries[i]
		map_option.add_item(str(entry.get("name", "Unknown Map")), i)

	var selected_entry_index: int = _find_map_entry_index_by_path(GameSession.selected_map_path)
	if selected_entry_index == -1:
		selected_entry_index = 0

	_select_map_option_by_entry_index(selected_entry_index)
	_set_local_selected_map_from_entry(selected_entry_index)

	map_option.item_selected.connect(_on_map_selected)


func _rebuild_map_entries() -> void:
	_map_entries.clear()

	for map_scene in available_maps:
		if map_scene == null:
			continue

		var path: String = map_scene.resource_path
		if path == "":
			continue

		_add_map_entry(path, _get_map_display_name_from_path(path), map_scene)

	for path in DEFAULT_MAP_PATHS:
		if _find_map_entry_index_by_path(path) != -1:
			continue

		if not ResourceLoader.exists(path):
			continue

		var loaded_scene: PackedScene = load(path) as PackedScene
		if loaded_scene == null:
			continue

		_add_map_entry(path, _get_map_display_name_from_path(path), loaded_scene)


func _add_map_entry(path: String, display_name: String, map_scene: PackedScene) -> void:
	_map_entries.append({
		"path": path,
		"name": display_name,
		"scene": map_scene,
	})


func _setup_team_count_option() -> void:
	team_count_option.clear()

	for count in range(2, GameSession.MAX_TEAMS + 1):
		team_count_option.add_item("%d Teams" % count, count)

	var selected_index: int = max(GameSession.team_count - 2, 0)
	team_count_option.select(selected_index)
	team_count_option.item_selected.connect(_on_team_count_selected)


func _refresh_from_lobby_state() -> void:
	_is_refreshing_ui = true

	var lobby_state: Dictionary = NetworkHub.get_lobby_state()
	var is_host_now: bool = NetworkHub.is_host
	var has_peer: bool = multiplayer.multiplayer_peer != null

	var local_peer_id: int = 1
	if has_peer:
		local_peer_id = multiplayer.get_unique_id()

	if transport_option != null:
		var desired_mode: int = int(lobby_state.get("transport_mode", NetworkHub.transport_mode))
		transport_option.select(_get_transport_option_index(desired_mode))

	if signaling_url_line_edit != null:
		signaling_url_line_edit.text = str(lobby_state.get("webrtc_signaling_url", NetworkHub.webrtc_signaling_url))

	if room_code_line_edit != null:
		room_code_line_edit.text = str(lobby_state.get("webrtc_room_code", NetworkHub.webrtc_room_code))

	if connection_status_label != null:
		if not has_peer:
			connection_status_label.text = "Offline [%s]" % NetworkHub.get_transport_display_name()
		elif is_host_now:
			connection_status_label.text = "Hosting [%s]" % NetworkHub.get_transport_display_name()
		else:
			connection_status_label.text = "Connected [%s]" % NetworkHub.get_transport_display_name()

	var lobby_team_count: int = int(lobby_state.get("team_count", GameSession.team_count))
	GameSession.set_team_count(lobby_team_count)

	if team_count_option != null:
		var team_idx: int = max(lobby_team_count - 2, 0)
		if team_idx >= 0 and team_idx < team_count_option.item_count:
			team_count_option.select(team_idx)

	var map_path: String = str(lobby_state.get("map_path", GameSession.selected_map_path))
	var map_name: String = str(lobby_state.get("map_name", GameSession.selected_map_name))

	if map_path != "":
		GameSession.set_selected_map(map_path, map_name)
		if map_option != null:
			_select_map_option_by_path(map_path)
	else:
		var fallback_map_index: int = _get_selected_map_entry_index()
		if fallback_map_index == -1 and not _map_entries.is_empty():
			fallback_map_index = 0

		if fallback_map_index != -1:
			_set_local_selected_map_from_entry(fallback_map_index)
			if map_option != null:
				_select_map_option_by_entry_index(fallback_map_index)

	var starting_credits: int = int(lobby_state.get("starting_credits", GameSession.starting_credits))
	var income_per_second: float = float(lobby_state.get("income_per_second", GameSession.base_credit_income_per_second))

	GameSession.set_starting_credits(starting_credits)
	GameSession.set_base_credit_income_per_second(income_per_second)

	if starting_credits_spinbox != null:
		starting_credits_spinbox.value = starting_credits

	if income_spinbox != null:
		income_spinbox.value = income_per_second

	var seats: Array = lobby_state.get("seats", [])

	for i in range(_seat_rows.size()):
		var row_data: Dictionary = _seat_rows[i]

		var row: HBoxContainer = row_data["row"]
		var seat_label: Label = row_data["seat_label"]
		var occupancy_label: Label = row_data["occupancy_label"]
		var control_option: OptionButton = row_data["control_option"]
		var team_option: OptionButton = row_data["team_option"]

		if row == null:
			continue

		var row_visible: bool = i < lobby_team_count
		row.visible = row_visible

		if not row_visible:
			continue

		var seat: Dictionary = {}
		if i < seats.size():
			seat = seats[i]

		var peer_id: int = int(seat.get("peer_id", 0))
		var team_id: int = int(seat.get("team_id", i))
		var display_name: String = str(seat.get("display_name", "Open"))

		var control_type: int
		if seat.has("control_type"):
			control_type = int(seat.get("control_type", GameSession.ControlType.CLOSED))
		else:
			control_type = GameSession.ControlType.PLAYER if peer_id != 0 else GameSession.ControlType.CLOSED

		if seat_label != null:
			seat_label.text = "Seat %d" % (i + 1)

		if occupancy_label != null:
			if peer_id == 0:
				if control_type == GameSession.ControlType.AI:
					occupancy_label.text = "AI"
				else:
					occupancy_label.text = display_name if display_name != "" else "Open"
			elif peer_id == local_peer_id:
				occupancy_label.text = "You"
			elif peer_id == int(lobby_state.get("host_peer_id", 1)):
				occupancy_label.text = "Host"
			else:
				occupancy_label.text = display_name if display_name != "" else "Client"

		if control_option != null:
			_setup_control_option(control_option, control_type)

			var can_edit_control: bool = false
			if is_host_now:
				if i == 0:
					can_edit_control = false
				elif peer_id != 0:
					can_edit_control = false
				else:
					can_edit_control = true

			control_option.disabled = not can_edit_control

		if team_option != null:
			_setup_team_option(team_option, lobby_team_count, team_id)

			var can_edit_team: bool = false
			if is_host_now:
				can_edit_team = true
			else:
				can_edit_team = peer_id == local_peer_id and peer_id != 0

			team_option.disabled = not can_edit_team

			_disconnect_item_selected_if_needed(team_option)
			team_option.item_selected.connect(_on_seat_team_selected.bind(i, team_option))

		if i >= 0 and i < GameSession.team_setups.size():
			GameSession.team_setups[i]["team_id"] = team_id
			GameSession.team_setups[i]["control_type"] = control_type
			GameSession.team_setups[i]["seat_id"] = i
			GameSession.team_setups[i]["peer_id"] = peer_id

	_is_refreshing_ui = false


func _setup_control_option(option: OptionButton, control_type: int) -> void:
	option.clear()

	option.add_item("Closed", GameSession.ControlType.CLOSED)
	option.add_item("Player", GameSession.ControlType.PLAYER)
	option.add_item("AI", GameSession.ControlType.AI)

	match control_type:
		GameSession.ControlType.CLOSED:
			option.select(0)
		GameSession.ControlType.PLAYER:
			option.select(1)
		GameSession.ControlType.AI:
			option.select(2)
		_:
			option.select(0)

	_disconnect_item_selected_if_needed(option)
	option.item_selected.connect(_on_seat_control_selected.bind(option))


func _setup_team_option(option: OptionButton, team_count: int, selected_team_id: int) -> void:
	option.clear()

	for i in range(team_count):
		option.add_item("Team %d" % (i + 1), i)

	var safe_team_id: int = clamp(selected_team_id, 0, max(team_count - 1, 0))

	for idx in range(option.item_count):
		if option.get_item_id(idx) == safe_team_id:
			option.select(idx)
			break


func _disconnect_item_selected_if_needed(option: OptionButton) -> void:
	for callable_info in option.item_selected.get_connections():
		option.item_selected.disconnect(callable_info.callable)


func _get_selected_map_entry_index() -> int:
	if map_option != null and map_option.item_count > 0:
		var selected_id: int = map_option.get_selected_id()
		if selected_id >= 0 and selected_id < _map_entries.size():
			return selected_id

	var session_index: int = _find_map_entry_index_by_path(GameSession.selected_map_path)
	if session_index != -1:
		return session_index

	if not _map_entries.is_empty():
		return 0

	return -1


func _get_selected_map_settings() -> Dictionary:
	var entry_index: int = _get_selected_map_entry_index()
	if entry_index == -1:
		return {
			"map_path": "",
			"map_name": "No Map",
		}

	var entry: Dictionary = _map_entries[entry_index]
	return {
		"map_path": str(entry.get("path", "")),
		"map_name": str(entry.get("name", "Unnamed Map")),
	}


func _set_local_selected_map_from_entry(entry_index: int) -> void:
	if entry_index < 0 or entry_index >= _map_entries.size():
		GameSession.clear_selected_map()
		return

	var entry: Dictionary = _map_entries[entry_index]
	var path: String = str(entry.get("path", ""))
	var display_name: String = str(entry.get("name", "Unnamed Map"))

	if path == "":
		GameSession.clear_selected_map()
		return

	GameSession.set_selected_map(path, display_name)


func _select_map_option_by_entry_index(entry_index: int) -> void:
	if map_option == null:
		return

	for option_index in range(map_option.item_count):
		if map_option.get_item_id(option_index) == entry_index:
			map_option.select(option_index)
			return


func _select_map_option_by_path(map_path: String) -> void:
	var entry_index: int = _find_map_entry_index_by_path(map_path)
	if entry_index == -1:
		return

	_select_map_option_by_entry_index(entry_index)


func _find_map_entry_index_by_path(map_path: String) -> int:
	if map_path == "":
		return -1

	for i in range(_map_entries.size()):
		var entry: Dictionary = _map_entries[i]
		if str(entry.get("path", "")) == map_path:
			return i

	return -1


func _get_transport_option_index(mode: int) -> int:
	if mode == NetworkHub.TransportMode.WEBRTC:
		return 1

	return 0


func _on_transport_selected(index: int) -> void:
	if _is_refreshing_ui:
		return

	var mode: int = transport_option.get_item_id(index)
	NetworkHub.set_transport_mode(mode)
	_refresh_button_states()


func _on_signaling_url_changed(value: String) -> void:
	if _is_refreshing_ui:
		return

	NetworkHub.set_webrtc_signaling_url(value)


func _on_room_code_changed(value: String) -> void:
	if _is_refreshing_ui:
		return

	NetworkHub.set_webrtc_room_code(value)


func _on_host_pressed() -> void:
	var pending_settings: Dictionary = _collect_pending_host_settings()

	var port: int = int(NetworkHub.DEFAULT_PORT)
	if port_spinbox != null:
		port = int(round(port_spinbox.value))

	var err: Error = NetworkHub.host_game(port)

	if err != OK:
		if connection_status_label != null:
			connection_status_label.text = "Host failed: %s" % error_string(err)
		return

	_push_settings_to_lobby(pending_settings)


func _collect_pending_host_settings() -> Dictionary:
	var map_settings: Dictionary = _get_selected_map_settings()

	var team_count: int = GameSession.team_count
	if team_count_option != null and team_count_option.item_count > 0:
		team_count = team_count_option.get_selected_id()

	var credits: int = GameSession.starting_credits
	if starting_credits_spinbox != null:
		credits = int(round(starting_credits_spinbox.value))

	var income: float = GameSession.base_credit_income_per_second
	if income_spinbox != null:
		income = float(income_spinbox.value)

	return {
		"map_path": str(map_settings.get("map_path", "")),
		"map_name": str(map_settings.get("map_name", "No Map")),
		"team_count": team_count,
		"starting_credits": credits,
		"income_per_second": income,
	}


func _push_current_settings_to_lobby() -> void:
	_push_settings_to_lobby(_collect_pending_host_settings())


func _push_settings_to_lobby(settings: Dictionary) -> void:
	if not NetworkHub.is_host:
		return

	var map_path: String = str(settings.get("map_path", ""))
	var map_name: String = str(settings.get("map_name", "No Map"))

	if map_path == "" and not _map_entries.is_empty():
		var first_entry: Dictionary = _map_entries[0]
		map_path = str(first_entry.get("path", ""))
		map_name = str(first_entry.get("name", "Unnamed Map"))

	if map_path != "":
		GameSession.set_selected_map(map_path, map_name)
		if NetworkHub.has_method("set_lobby_map"):
			NetworkHub.set_lobby_map(map_path, map_name)

	var team_count: int = clamp(int(settings.get("team_count", GameSession.team_count)), 2, GameSession.MAX_TEAMS)
	GameSession.set_team_count(team_count)

	if NetworkHub.has_method("set_lobby_team_count"):
		NetworkHub.set_lobby_team_count(team_count)

	var credits: int = int(settings.get("starting_credits", GameSession.starting_credits))
	GameSession.set_starting_credits(credits)

	if NetworkHub.has_method("set_lobby_starting_credits"):
		NetworkHub.set_lobby_starting_credits(credits)

	var income: float = float(settings.get("income_per_second", GameSession.base_credit_income_per_second))
	GameSession.set_base_credit_income_per_second(income)

	if NetworkHub.has_method("set_lobby_income_per_second"):
		NetworkHub.set_lobby_income_per_second(income)


func _on_join_pressed() -> void:
	var ip: String = "127.0.0.1"
	if ip_line_edit != null:
		ip = ip_line_edit.text.strip_edges()

	var port: int = int(NetworkHub.DEFAULT_PORT)
	if port_spinbox != null:
		port = int(round(port_spinbox.value))

	var err: Error = NetworkHub.join_game(ip, port)

	if err != OK and connection_status_label != null:
		connection_status_label.text = "Join failed: %s" % error_string(err)
	else:
		if connection_status_label != null:
			connection_status_label.text = "Connecting..."


func _on_disconnect_pressed() -> void:
	NetworkHub.disconnect_from_session()


func _on_map_selected(index: int) -> void:
	if _is_refreshing_ui:
		return

	if map_option == null:
		return

	var entry_index: int = map_option.get_item_id(index)

	if entry_index < 0 or entry_index >= _map_entries.size():
		return

	_set_local_selected_map_from_entry(entry_index)

	var entry: Dictionary = _map_entries[entry_index]
	var map_path: String = str(entry.get("path", ""))
	var map_name: String = str(entry.get("name", "Unnamed Map"))

	if NetworkHub.is_host:
		NetworkHub.set_lobby_map(map_path, map_name)


func _on_team_count_selected(index: int) -> void:
	if _is_refreshing_ui:
		return

	var team_count: int = team_count_option.get_item_id(index)
	GameSession.set_team_count(team_count)

	if NetworkHub.is_host and NetworkHub.has_method("set_lobby_team_count"):
		NetworkHub.set_lobby_team_count(team_count)

	_refresh_from_lobby_state()


func _on_starting_credits_changed(value: float) -> void:
	if _is_refreshing_ui:
		return

	GameSession.set_starting_credits(int(round(value)))

	if not NetworkHub.is_host:
		return

	NetworkHub.set_lobby_starting_credits(int(round(value)))


func _on_income_changed(value: float) -> void:
	if _is_refreshing_ui:
		return

	GameSession.set_base_credit_income_per_second(value)

	if not NetworkHub.is_host:
		return

	NetworkHub.set_lobby_income_per_second(value)


func _on_seat_control_selected(_selected_index: int, option: OptionButton) -> void:
	if _is_refreshing_ui:
		return

	if not NetworkHub.is_host:
		return

	var seat_id: int = _find_seat_id_for_control_option(option)

	if seat_id == -1:
		return

	var control_type: int = option.get_selected_id()

	if NetworkHub.has_method("set_seat_control_type"):
		NetworkHub.set_seat_control_type(seat_id, control_type)
	else:
		GameSession.team_setups[seat_id]["control_type"] = control_type

	_refresh_from_lobby_state()


func _on_seat_team_selected(_selected_index: int, seat_id: int, option: OptionButton) -> void:
	if _is_refreshing_ui:
		return

	var team_id: int = option.get_selected_id()
	var lobby_state: Dictionary = NetworkHub.get_lobby_state()
	var seats: Array = lobby_state.get("seats", [])

	for i in range(seats.size()):
		if i == seat_id:
			continue

		var seat: Dictionary = seats[i]
		var control_type: int = int(seat.get("control_type", GameSession.ControlType.CLOSED))
		var peer_id: int = int(seat.get("peer_id", 0))
		var other_team_id: int = int(seat.get("team_id", -1))

		if control_type == GameSession.ControlType.PLAYER and peer_id != 0 and other_team_id == team_id:
			_refresh_from_lobby_state()
			return

	NetworkHub.set_seat_team(seat_id, team_id)


func _find_seat_id_for_control_option(option: OptionButton) -> int:
	for i in range(_seat_rows.size()):
		if _seat_rows[i]["control_option"] == option:
			return i

	return -1


func _on_start_match_pressed() -> void:
	if not NetworkHub.is_host:
		return

	_push_current_settings_to_lobby()

	if not _can_start_online_match():
		return

	NetworkHub.request_start_match()


func _on_back_pressed() -> void:
	if multiplayer.multiplayer_peer != null:
		NetworkHub.disconnect_from_session()

	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")


func _on_hosting_started() -> void:
	_refresh_from_lobby_state()


func _on_joined_lobby() -> void:
	_refresh_from_lobby_state()


func _on_join_failed() -> void:
	if connection_status_label != null:
		connection_status_label.text = "Connection failed"

	_refresh_from_lobby_state()


func _on_disconnected() -> void:
	_refresh_from_lobby_state()


func _on_lobby_state_changed() -> void:
	_refresh_from_lobby_state()


func _on_start_match_requested() -> void:
	GameSession.set_meta("last_menu_scene_path", return_scene_path)

	NetworkHub.apply_lobby_to_game_session()

	if GameSession.selected_map_path == "" and not _map_entries.is_empty():
		_set_local_selected_map_from_entry(0)

	get_tree().change_scene_to_file(match_scene_path)


func _refresh_button_states() -> void:
	var online_active: bool = multiplayer.multiplayer_peer != null
	var using_webrtc: bool = NetworkHub.transport_mode == NetworkHub.TransportMode.WEBRTC
	var host_can_edit: bool = NetworkHub.is_host
	var has_usable_map: bool = _get_effective_lobby_map_path() != ""

	if host_button != null:
		host_button.disabled = online_active

	if join_button != null:
		join_button.disabled = online_active

	if disconnect_button != null:
		disconnect_button.disabled = not online_active

	if transport_option != null:
		transport_option.disabled = online_active

	if signaling_url_line_edit != null:
		signaling_url_line_edit.editable = not online_active and using_webrtc

	if room_code_line_edit != null:
		room_code_line_edit.editable = not online_active and using_webrtc

	if ip_line_edit != null:
		ip_line_edit.editable = not online_active and not using_webrtc

	if port_spinbox != null:
		port_spinbox.editable = not online_active and not using_webrtc

	if map_option != null:
		map_option.disabled = _map_entries.is_empty() or not host_can_edit

	if team_count_option != null:
		team_count_option.disabled = not host_can_edit

	if starting_credits_spinbox != null:
		starting_credits_spinbox.editable = host_can_edit

	if income_spinbox != null:
		income_spinbox.editable = host_can_edit

	if start_match_button != null:
		start_match_button.disabled = not (NetworkHub.is_host and has_usable_map and _can_start_online_match())


func _get_effective_lobby_map_path() -> String:
	var lobby_state: Dictionary = NetworkHub.get_lobby_state()
	var map_path: String = str(lobby_state.get("map_path", ""))

	if map_path != "":
		return map_path

	var selected: Dictionary = _get_selected_map_settings()
	map_path = str(selected.get("map_path", ""))

	if map_path != "":
		return map_path

	return GameSession.selected_map_path


func _can_start_online_match() -> bool:
	var lobby_state: Dictionary = NetworkHub.get_lobby_state()

	var map_path: String = str(lobby_state.get("map_path", ""))
	if map_path == "":
		map_path = GameSession.selected_map_path

	if map_path == "":
		return false

	if not ResourceLoader.exists(map_path):
		return false

	var seats: Array = lobby_state.get("seats", [])
	var team_count: int = int(lobby_state.get("team_count", GameSession.team_count))

	var active_teams: Array[int] = []
	var human_seats: int = 0

	for i in range(min(seats.size(), team_count)):
		var seat: Dictionary = seats[i]
		var peer_id: int = int(seat.get("peer_id", 0))
		var team_id: int = int(seat.get("team_id", -1))

		var control_type: int
		if seat.has("control_type"):
			control_type = int(seat.get("control_type", GameSession.ControlType.CLOSED))
		else:
			control_type = GameSession.ControlType.PLAYER if peer_id != 0 else GameSession.ControlType.CLOSED

		if control_type == GameSession.ControlType.CLOSED:
			continue

		if team_id < 0 or team_id >= team_count:
			return false

		if team_id not in active_teams:
			active_teams.append(team_id)

		if control_type == GameSession.ControlType.PLAYER:
			human_seats += 1

	if human_seats < 2:
		return false

	return active_teams.size() >= 2


func _get_map_display_name(map_scene: PackedScene) -> String:
	if map_scene == null:
		return "Unknown Map"

	return _get_map_display_name_from_path(map_scene.resource_path)


func _get_map_display_name_from_path(path: String) -> String:
	if path == "":
		return "Unnamed Map"

	return path.get_file().get_basename()


func _apply_layout() -> void:
	if main_panel != null:
		var panel_size := Vector2(880.0, 760.0)
		main_panel.position = (size - panel_size) * 0.5
		main_panel.custom_minimum_size = panel_size


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range or control is OptionButton or control is LineEdit:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
