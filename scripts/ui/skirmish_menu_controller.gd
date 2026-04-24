class_name SkirmishMenuController
extends Control

@export var match_scene_path: String = "res://scenes/main/MainMatch.tscn"

@export var main_panel: Control
@export var team_count_option: OptionButton
@export var team_rows_container: VBoxContainer
@export var local_players_container: VBoxContainer

@export var start_button: Button
@export var back_button: Button

@export var starting_credits_spinbox: SpinBox
@export var income_spinbox: SpinBox

@export var map_option: OptionButton
@export var available_maps: Array[PackedScene] = []

@export_group("Local Players")
@export var max_local_human_players: int = 4
@export var auto_join_connected_controllers: bool = false
@export var auto_assign_joined_players: bool = true

var _team_option_buttons: Array[OptionButton] = []
var _last_player_signature: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_apply_mouse_filter_fail_safe(self)

	if InputHub != null:
		InputHub.player_joined.connect(_on_input_player_changed)
		InputHub.player_left.connect(_on_input_player_changed)
		InputHub.player_team_changed.connect(_on_input_player_team_changed)

	if team_count_option != null:
		_setup_team_count_option()

	if starting_credits_spinbox != null:
		_setup_starting_credits_spinbox()

	if income_spinbox != null:
		_setup_income_spinbox()

	if map_option != null:
		_setup_map_option()

	if start_button != null:
		start_button.pressed.connect(_on_start_pressed)

	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)

	_ensure_joined_player_team_assignments()
	_rebuild_team_rows()
	_rebuild_local_player_rows()
	_apply_layout()

	if start_button != null:
		start_button.grab_focus()


func _process(_delta: float) -> void:
	if auto_join_connected_controllers:
		InputHub.join_connected_controllers(max_local_human_players)

	var signature: String = _get_player_signature()

	if signature != _last_player_signature:
		_last_player_signature = signature
		_ensure_joined_player_team_assignments()
		_rebuild_team_rows()
		_rebuild_local_player_rows()

	if start_button != null:
		start_button.disabled = not GameSession.can_start_skirmish()

	InputHub.begin_frame()


func _setup_starting_credits_spinbox() -> void:
	starting_credits_spinbox.min_value = 0
	starting_credits_spinbox.max_value = 100000
	starting_credits_spinbox.step = 10
	starting_credits_spinbox.value = GameSession.starting_credits
	starting_credits_spinbox.value_changed.connect(_on_starting_credits_changed)


func _setup_income_spinbox() -> void:
	income_spinbox.min_value = 1
	income_spinbox.max_value = 1000
	income_spinbox.step = 1
	income_spinbox.value = GameSession.base_credit_income_per_second
	income_spinbox.value_changed.connect(_on_income_changed)


func _setup_map_option() -> void:
	map_option.clear()

	for i in range(available_maps.size()):
		var map_scene: PackedScene = available_maps[i]

		if map_scene == null:
			continue

		var display_name: String = _get_map_display_name(map_scene)
		map_option.add_item(display_name, i)

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


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= available_maps.size():
		return

	var map_scene: PackedScene = available_maps[index]

	if map_scene == null:
		return

	GameSession.set_selected_map(
		map_scene.resource_path,
		_get_map_display_name(map_scene)
	)


func _get_map_display_name(map_scene: PackedScene) -> String:
	if map_scene == null:
		return "Unknown Map"

	var path: String = map_scene.resource_path

	if path == "":
		return "Unnamed Map"

	return path.get_file().get_basename()


func _on_starting_credits_changed(value: float) -> void:
	GameSession.set_starting_credits(int(round(value)))


func _on_income_changed(value: float) -> void:
	GameSession.set_base_credit_income_per_second(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _on_team_count_selected(index: int) -> void:
	var team_count: int = team_count_option.get_item_id(index)

	GameSession.set_team_count(team_count)

	_ensure_joined_player_team_assignments()
	_rebuild_team_rows()
	_rebuild_local_player_rows()


func _rebuild_team_rows() -> void:
	if team_rows_container == null:
		return

	for child in team_rows_container.get_children():
		child.queue_free()

	_team_option_buttons.clear()

	for member_id in range(GameSession.team_count):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.text = "Slot %d" % (member_id + 1)
		label.custom_minimum_size = Vector2(90, 28)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)

		var option := OptionButton.new()
		option.custom_minimum_size = Vector2(150, 32)

		option.add_item("Closed", GameSession.ControlType.CLOSED)
		option.add_item("Player", GameSession.ControlType.PLAYER)
		option.add_item("AI", GameSession.ControlType.AI)

		var control_type: int = GameSession.get_team_control_type(member_id)

		match control_type:
			GameSession.ControlType.CLOSED:
				option.select(0)
			GameSession.ControlType.PLAYER:
				option.select(1)
			GameSession.ControlType.AI:
				option.select(2)

		option.item_selected.connect(_on_team_control_selected.bind(member_id, option))
		row.add_child(option)

		var alliance_option := OptionButton.new()
		alliance_option.custom_minimum_size = Vector2(170, 32)

		for alliance_id in range(GameSession.team_count):
			alliance_option.add_item("Team %d" % (alliance_id + 1), alliance_id)

		var selected_alliance_id: int = GameSession.get_team_assignment(member_id)
		alliance_option.select(clamp(selected_alliance_id, 0, GameSession.team_count - 1))
		alliance_option.item_selected.connect(_on_member_alliance_selected.bind(member_id, alliance_option))

		row.add_child(alliance_option)

		team_rows_container.add_child(row)
		_team_option_buttons.append(option)

func _on_member_alliance_selected(_index: int, member_id: int, option: OptionButton) -> void:
	var alliance_team_id: int = option.get_selected_id()
	GameSession.set_team_assignment(member_id, alliance_team_id)

	_rebuild_team_rows()
	_rebuild_local_player_rows()

func _rebuild_local_player_rows() -> void:
	if local_players_container == null:
		return

	for child in local_players_container.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Local Players — assign each player to a member slot"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	local_players_container.add_child(title)

	var players: Array = InputHub.get_players()
	var shown_count: int = min(players.size(), max_local_human_players)

	for i in range(shown_count):
		var player = players[i]

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var player_label := Label.new()
		player_label.custom_minimum_size = Vector2(190, 28)
		player_label.text = "P%d: %s" % [i + 1, InputHub.get_player_label(i)]
		player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(player_label)

		var slot_option := OptionButton.new()
		slot_option.custom_minimum_size = Vector2(180, 32)

		for member_id in range(GameSession.team_count):
			slot_option.add_item("Slot %d" % (member_id + 1), member_id)

		var selected_member_id: int = int(player.team_id)

		if selected_member_id < 0 or selected_member_id >= GameSession.team_count:
			selected_member_id = clamp(i, 0, GameSession.team_count - 1)

		slot_option.select(selected_member_id)
		slot_option.item_selected.connect(_on_local_player_slot_selected.bind(i, slot_option))

		row.add_child(slot_option)
		local_players_container.add_child(row)


func _on_team_control_selected(_index: int, team_id: int, option: OptionButton) -> void:
	var selected_item_id: int = option.get_selected_id()
	GameSession.set_team_control_type(team_id, selected_item_id)


func _on_local_player_slot_selected(_index: int, player_index: int, option: OptionButton) -> void:
	var member_id: int = option.get_selected_id()

	InputHub.assign_team(player_index, member_id)
	GameSession.set_team_control_type(member_id, GameSession.ControlType.PLAYER)

	if player_index == 0:
		GameSession.local_player_team_id = member_id

	_rebuild_team_rows()
	_rebuild_local_player_rows()


func _ensure_joined_player_team_assignments() -> void:
	if not auto_assign_joined_players:
		return

	var players: Array = InputHub.get_players()
	var human_count: int = min(players.size(), max_local_human_players)

	if human_count <= 0:
		return

	if GameSession.team_count < max(2, human_count):
		GameSession.set_team_count(max(2, human_count))

		if team_count_option != null:
			team_count_option.select(GameSession.team_count - 2)

	for i in range(human_count):
		var member_id: int = clamp(i, 0, GameSession.team_count - 1)

		InputHub.assign_team(i, member_id)
		GameSession.set_team_control_type(member_id, GameSession.ControlType.PLAYER)

		if GameSession.get_team_assignment(member_id) < 0:
			GameSession.set_team_assignment(member_id, member_id)

		if i == 0:
			GameSession.local_player_team_id = member_id


func _find_first_free_team_id(used_team_ids: Array[int]) -> int:
	for team_id in range(GameSession.team_count):
		if not used_team_ids.has(team_id):
			return team_id

	return 0


func _get_player_signature() -> String:
	var parts: Array[String] = []

	for player in InputHub.get_players():
		parts.append("%d:%d:%d" % [player.player_index, player.device_id, player.team_id])

	return "|".join(parts)


func _on_input_player_changed(_player_index: int, _device_id: int) -> void:
	_ensure_joined_player_team_assignments()
	_rebuild_team_rows()
	_rebuild_local_player_rows()


func _on_input_player_team_changed(_player_index: int, _team_id: int) -> void:
	_rebuild_team_rows()
	_rebuild_local_player_rows()


func _on_start_pressed() -> void:
	_ensure_joined_player_team_assignments()

	if not GameSession.can_start_skirmish():
		return

	GameSession.set_meta("last_menu_scene_path", scene_file_path)
	get_tree().change_scene_to_file(match_scene_path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")


func _apply_layout() -> void:
	if main_panel != null:
		var panel_size := Vector2(640.0, 620.0)

		main_panel.position = (size - panel_size) * 0.5
		main_panel.custom_minimum_size = panel_size


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range or control is OptionButton:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
