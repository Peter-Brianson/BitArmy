class_name SkirmishMenuController
extends Control

@export var match_scene_path: String = "res://scenes/main/MainMatch.tscn"

@export var main_panel: Control
@export var team_count_option: OptionButton
@export var team_rows_container: VBoxContainer
@export var start_button: Button
@export var back_button: Button

var _team_option_buttons: Array[OptionButton] = []

@export var starting_credits_spinbox: SpinBox
@export var income_spinbox: SpinBox

@export var map_option: OptionButton
@export var available_maps: Array[PackedScene] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mouse_filter_fail_safe(self)

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

	_rebuild_team_rows()
	_apply_layout()

	if start_button != null:
		start_button.grab_focus()

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


func _process(_delta: float) -> void:
	if start_button != null:
		start_button.disabled = not GameSession.can_start_skirmish()


func _setup_team_count_option() -> void:
	team_count_option.clear()

	for count in range(2, GameSession.MAX_TEAMS + 1):
		team_count_option.add_item("%d Teams" % count, count)

	var selected_index: int = max(GameSession.team_count - 2, 0)
	team_count_option.select(selected_index)
	team_count_option.item_selected.connect(_on_team_count_selected)


func _on_team_count_selected(index: int) -> void:
	var team_count: int = team_count_option.get_item_id(index)
	GameSession.set_team_count(team_count)
	_rebuild_team_rows()


func _rebuild_team_rows() -> void:
	for child in team_rows_container.get_children():
		child.queue_free()

	_team_option_buttons.clear()

	for i in range(GameSession.team_count):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.text = "Team %d" % (i + 1)
		label.custom_minimum_size = Vector2(120, 28)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)

		var option := OptionButton.new()
		option.custom_minimum_size = Vector2(180, 32)
		option.add_item("Closed", GameSession.ControlType.CLOSED)
		option.add_item("Player", GameSession.ControlType.PLAYER)
		option.add_item("AI", GameSession.ControlType.AI)

		var control_type: int = GameSession.get_team_control_type(i)
		match control_type:
			GameSession.ControlType.CLOSED:
				option.select(0)
			GameSession.ControlType.PLAYER:
				option.select(1)
			GameSession.ControlType.AI:
				option.select(2)

		option.item_selected.connect(_on_team_control_selected.bind(i, option))
		row.add_child(option)

		team_rows_container.add_child(row)
		_team_option_buttons.append(option)


func _on_team_control_selected(_index: int, team_id: int, option: OptionButton) -> void:
	var selected_item_id: int = option.get_selected_id()
	GameSession.set_team_control_type(team_id, selected_item_id)


func _on_start_pressed() -> void:
	if not GameSession.can_start_skirmish():
		return

	get_tree().change_scene_to_file(match_scene_path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")


func _apply_layout() -> void:
	if main_panel != null:
		var panel_size := Vector2(540.0, 520.0)
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
