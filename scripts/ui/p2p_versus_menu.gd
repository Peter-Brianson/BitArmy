class_name P2PVersusMenuController
extends Control

@export var match_scene_path: String = "res://scenes/main/MainMatch.tscn"

@export_group("Main")
@export var main_panel: Control

@export_group("Network")
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

var _seat_rows: Array[Dictionary] = []
var _is_refreshing_ui: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mouse_filter_fail_safe(self)

	# Always enter this menu in a disconnected state.
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
			"team_option": team_option
		})


func _setup_network_controls() -> void:
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
		help_label.text = "Host can configure map and economy. Connected players can choose their team."


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
	map_option.clear()

	for i in range(available_maps.size()):
		var map_scene: PackedScene = available_maps[i]
		if map_scene == null:
			continue

		map_option.add_item(_get_map_display_name(map_scene), i)

	if available_maps.size() > 0 and available_maps[0] != null:
		var first_name: String = _get_map_display_name(available_maps[0])
		GameSession.set_selected_map(available_maps[0].resource_path, first_name)
		map_option.select(0)

	map_option.item_selected.connect(_on_map_selected)


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
	var is_host: bool = NetworkHub.is_host
	var has_peer: bool = multiplayer.multiplayer_peer != null
	var local_peer_id: int = 1

	if has_peer:
		local_peer_id = multiplayer.get_unique_id()

	if connection_status_label != null:
		if not has_peer:
			connection_status_label.text = "Offline"
		elif is_host:
			connection_status_label.text = "Hosting on port %d" % int(port_spinbox.value if port_spinbox != null else NetworkHub.DEFAULT_PORT)
		else:
			connection_status_label.text = "Connected to host"

	var lobby_team_count: int = int(lobby_state.get("team_count", GameSession.team_count))
	GameSession.set_team_count(lobby_team_count)

	if team_count_option != null:
		var idx: int = max(lobby_team_count - 2, 0)
		if idx >= 0 and idx < team_count_option.item_count:
			team_count_option.select(idx)

	var map_path: String = str(lobby_state.get("map_path", GameSession.selected_map_path))
	var map_name: String = str(lobby_state.get("map_name", GameSession.selected_map_name))

	if map_path != "":
		GameSession.set_selected_map(map_path, map_name)

	if map_option != null:
		_select_map_option_by_path(map_path)

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
			if peer_id != 0:
				control_type = GameSession.ControlType.PLAYER
			else:
				control_type = GameSession.ControlType.CLOSED

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
			if is_host:
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
			if is_host:
				can_edit_team = true
			else:
				can_edit_team = peer_id == local_peer_id and peer_id != 0

			team_option.disabled = not can_edit_team

			_disconnect_item_selected_if_needed(team_option)
			team_option.item_selected.connect(_on_seat_team_selected.bind(i, team_option))

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


func _select_map_option_by_path(map_path: String) -> void:
	if map_option == null:
		return

	for i in range(available_maps.size()):
		var map_scene: PackedScene = available_maps[i]
		if map_scene == null:
			continue

		if map_scene.resource_path == map_path:
			for idx in range(map_option.item_count):
				if map_option.get_item_id(idx) == i:
					map_option.select(idx)
					return


func _on_host_pressed() -> void:
	var port: int = int(NetworkHub.DEFAULT_PORT)

	if port_spinbox != null:
		port = int(round(port_spinbox.value))

	var err: Error = NetworkHub.host_game(port)
	if err != OK and connection_status_label != null:
		connection_status_label.text = "Host failed: %s" % error_string(err)


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
	if not NetworkHub.is_host:
		return
	if index < 0 or index >= available_maps.size():
		return

	var map_scene: PackedScene = available_maps[index]
	if map_scene == null:
		return

	NetworkHub.set_lobby_map(map_scene.resource_path, _get_map_display_name(map_scene))


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
	if not NetworkHub.is_host:
		return

	NetworkHub.set_lobby_starting_credits(int(round(value)))


func _on_income_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
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

	# Temporary rule:
	# do not allow two PLAYER seats to use the same team yet,
	# because the current match architecture spawns one HQ per team.
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
	NetworkHub.apply_lobby_to_game_session()
	get_tree().change_scene_to_file(match_scene_path)


func _refresh_button_states() -> void:
	var online_active: bool = multiplayer.multiplayer_peer != null

	if host_button != null:
		host_button.disabled = online_active

	if join_button != null:
		join_button.disabled = online_active

	if disconnect_button != null:
		disconnect_button.disabled = not online_active

	var host_can_edit: bool = NetworkHub.is_host

	if map_option != null:
		map_option.disabled = not host_can_edit

	if team_count_option != null:
		team_count_option.disabled = not host_can_edit

	if starting_credits_spinbox != null:
		starting_credits_spinbox.editable = host_can_edit

	if income_spinbox != null:
		income_spinbox.editable = host_can_edit

	if start_match_button != null:
		start_match_button.disabled = not (NetworkHub.is_host and _can_start_online_match())


func _can_start_online_match() -> bool:
	var lobby_state: Dictionary = NetworkHub.get_lobby_state()
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
			if peer_id != 0:
				control_type = GameSession.ControlType.PLAYER
			else:
				control_type = GameSession.ControlType.CLOSED

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

	var path: String = map_scene.resource_path
	if path == "":
		return "Unnamed Map"

	return path.get_file().get_basename()


func _apply_layout() -> void:
	if main_panel != null:
		var panel_size := Vector2(880.0, 700.0)
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
