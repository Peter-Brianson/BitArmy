class_name HUDController
extends Control

@export_group("References")
@export var selection_controller: SelectionController
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var game_manager: GameManager
@export var match_controller: MatchController
@export var match_net_controller: MatchNetController
@export var camera_pan_controller: CameraPanController
@export var structure_placement_controller: StructurePlacementController

@export_group("UI Scale")
@export var ui_scale: float = 1.0
@export var base_font_size: int = 16
@export var base_title_font_size: int = 18

@export_group("Panels")
@export var selection_panel: Control
@export var production_panel: Control
@export var resource_panel: Control
@export var status_panel: Control

@export_group("Selection Widgets")
@export var selection_icon: TextureRect
@export var type_label: Label
@export var name_label: Label
@export var description_label: Label
@export var health_label: Label
@export var stat_summary_label: Label
@export var unit_count_label: Label
@export var structure_count_label: Label

@export_group("Production Widgets")
@export var production_scroll: ScrollContainer
@export var production_grid: GridContainer
@export var queue_label: Label
@export var progress_label: Label

@export_group("Resources")
@export var credits_label: Label
@export var income_label: Label
@export var location_label: Label

@export_group("Status")
@export var match_timer_label: Label
@export var fps_label: Label
@export var teams_alive_label: Label

@export_group("Build Options")
@export var buildable_structure_stats: Array[StructureStats] = []
@export var buildable_structure_scenes: Array[PackedScene] = []

var credits: int = 999
var match_time_seconds: float = 0.0

var _last_production_structure_id: int = -999
var _dynamic_production_buttons: Array = []

var _has_last_virtual_pointer_world: bool = false
var _last_virtual_pointer_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	_apply_mouse_filter_fail_safe(self)

	if production_panel != null:
		production_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		production_panel.gui_input.connect(_on_production_ui_gui_input)

	if production_scroll != null:
		production_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		production_scroll.gui_input.connect(_on_production_ui_gui_input)

	_apply_layout()
	_refresh_all()


func _process(delta: float) -> void:
	if not get_tree().paused:
		match_time_seconds += delta

	_update_camera_ui_block_rect()
	_refresh_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func set_ui_scale(value: float) -> void:
	ui_scale = clamp(value, 0.75, 1.5)
	_apply_layout()


func handle_virtual_pointer(pointer: VirtualPointerState) -> bool:
	if not visible:
		return false

	_has_last_virtual_pointer_world = true
	_last_virtual_pointer_world = pointer.world_pos

	if structure_placement_controller != null:
		if structure_placement_controller.has_method("set_external_pointer_world"):
			structure_placement_controller.call("set_external_pointer_world", pointer.world_pos)

	if not pointer.primary_just_pressed:
		return false

	var button: BaseButton = _find_button_at_global_position(self, pointer.screen_pos)

	if button == null:
		return false

	if button.disabled:
		return true

	button.emit_signal("pressed")
	return true


func _find_button_at_global_position(node: Node, global_pos: Vector2) -> BaseButton:
	var best_button: BaseButton = null

	for child in node.get_children():
		var found: BaseButton = _find_button_at_global_position(child, global_pos)

		if found != null:
			best_button = found

	if node is BaseButton:
		var button := node as BaseButton

		if button.visible and button.is_visible_in_tree() and button.get_global_rect().has_point(global_pos):
			best_button = button

	return best_button


func _refresh_all() -> void:
	_refresh_selection_panel()
	_refresh_production_panel()
	_refresh_resource_panel()
	_refresh_location_label()
	_refresh_status_panel()


func _refresh_selection_panel() -> void:
	if selection_panel == null:
		return

	if selection_controller == null:
		selection_panel.visible = false
		return

	var selected_structure_id: int = selection_controller.selected_structure_id
	var selected_units: Array[int] = selection_controller.selected_unit_ids

	if selected_structure_id != -1:
		var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

		if structure != null and structure.is_alive:
			selection_panel.visible = true

			if selection_icon != null:
				selection_icon.texture = structure.stats.icon_texture
				selection_icon.visible = structure.stats.icon_texture != null

			if type_label != null:
				type_label.text = "Structure"

			if name_label != null:
				name_label.text = structure.stats.structure_name

			if description_label != null:
				description_label.text = str(structure.stats.description)
				description_label.visible = description_label.text != ""

			if health_label != null:
				health_label.text = "HP: %d / %d" % [
					structure.current_health,
					structure.stats.max_health
				]

			if stat_summary_label != null:
				stat_summary_label.text = ""
				stat_summary_label.visible = false

			if unit_count_label != null:
				unit_count_label.text = "Units: %d" % _count_alive_units_for_team(structure.owner_team_id)

			if structure_count_label != null:
				structure_count_label.text = "Structures: %d" % _count_alive_structures_for_team(structure.owner_team_id)

			return

	if not selected_units.is_empty():
		selection_panel.visible = true

		if selected_units.size() == 1:
			var unit: UnitRuntime = unit_manager.get_unit(selected_units[0])

			if unit != null and unit.is_alive:
				if selection_icon != null:
					selection_icon.texture = unit.stats.icon_texture
					selection_icon.visible = unit.stats.icon_texture != null

				if type_label != null:
					type_label.text = "Unit"

				if name_label != null:
					name_label.text = unit.stats.unit_name

				if description_label != null:
					description_label.text = str(unit.stats.description)
					description_label.visible = description_label.text != ""

				if health_label != null:
					var effective_max: int = unit.get_effective_max_health(unit_manager.team_manager)
					health_label.text = "HP: %d / %d" % [
						unit.current_health,
						effective_max
					]

				if stat_summary_label != null:
					var attacks_per_second: float = 0.0

					if unit.get_attack_cooldown() > 0.0:
						attacks_per_second = 1.0 / unit.get_attack_cooldown()

					stat_summary_label.text = "Move %.1f | Dmg %d | APS %.2f | Rng %.1f" % [
						unit.stats.move_speed,
						unit.get_effective_damage(unit_manager.team_manager),
						attacks_per_second,
						unit.stats.attack_range
					]
					stat_summary_label.visible = true

				if unit_count_label != null:
					unit_count_label.text = ""

				if structure_count_label != null:
					structure_count_label.text = ""

				return

		if selection_icon != null:
			selection_icon.texture = null
			selection_icon.visible = false

		if type_label != null:
			type_label.text = "Units"

		if name_label != null:
			name_label.text = "%d selected" % selected_units.size()

		if description_label != null:
			description_label.text = ""
			description_label.visible = false

		if health_label != null:
			health_label.text = ""

		if stat_summary_label != null:
			stat_summary_label.text = ""
			stat_summary_label.visible = false

		if unit_count_label != null:
			unit_count_label.text = ""

		if structure_count_label != null:
			structure_count_label.text = ""

		return

	if selection_icon != null:
		selection_icon.texture = null
		selection_icon.visible = false

	if description_label != null:
		description_label.text = ""
		description_label.visible = false

	if stat_summary_label != null:
		stat_summary_label.text = ""
		stat_summary_label.visible = false

	selection_panel.visible = false


func _refresh_production_panel() -> void:
	if production_panel == null:
		return

	if selection_controller == null:
		production_panel.visible = false
		_clear_production_buttons_if_needed()
		return

	var selected_structure_id: int = selection_controller.selected_structure_id

	if selected_structure_id == -1:
		production_panel.visible = false
		_clear_production_buttons_if_needed()
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null or not structure.is_alive:
		production_panel.visible = false
		_clear_production_buttons_if_needed()
		return

	var show_train_button: bool = structure.can_train_units() and structure.get_trained_unit_stats() != null
	var show_build_options: bool = structure.can_place_structures()

	if not show_train_button and not show_build_options:
		production_panel.visible = false
		_clear_production_buttons_if_needed()
		return

	production_panel.visible = true

	if selected_structure_id != _last_production_structure_id:
		_rebuild_production_buttons(structure)
		_last_production_structure_id = selected_structure_id

	_update_production_buttons(structure)

	if queue_label != null:
		if structure.can_train_units():
			var queue_count: int = structure.production_queue.size()

			if structure.current_production != null:
				queue_count += 1

			queue_label.visible = true
			queue_label.text = "Queue: %d" % queue_count
		else:
			queue_label.visible = false

	if progress_label != null:
		if structure.can_train_units():
			progress_label.visible = true

			if structure.current_production != null:
				progress_label.text = "Building: %s %.1f / %.1f" % [
					structure.current_production.unit_name,
					structure.production_progress,
					structure.current_production.build_time
				]
			else:
				progress_label.text = "Idle"
		else:
			progress_label.visible = false


func _rebuild_production_buttons(structure: StructureRuntime) -> void:
	_dynamic_production_buttons.clear()

	if production_grid == null:
		return

	for child in production_grid.get_children():
		child.queue_free()

	if structure.can_train_units() and structure.get_trained_unit_stats() != null:
		var train_button := Button.new()
		train_button.pressed.connect(_on_train_current_structure_pressed)
		production_grid.add_child(train_button)

		_dynamic_production_buttons.append({
			"kind": "train",
			"button": train_button
		})

	if structure.can_place_structures():
		var count: int = min(buildable_structure_stats.size(), buildable_structure_scenes.size())

		for i in range(count):
			var stats: StructureStats = buildable_structure_stats[i]
			var scene: PackedScene = buildable_structure_scenes[i]

			if stats == null or scene == null:
				continue

			var build_button := Button.new()
			build_button.pressed.connect(_on_build_structure_option_pressed.bind(i))
			production_grid.add_child(build_button)

			_dynamic_production_buttons.append({
				"kind": "build",
				"index": i,
				"button": build_button
			})

	_apply_dynamic_button_sizes()
	_apply_dynamic_button_fonts()


func _update_production_buttons(structure: StructureRuntime) -> void:
	for entry in _dynamic_production_buttons:
		var kind: String = entry["kind"]
		var button: Button = entry["button"]

		if button == null:
			continue

		if kind == "train":
			var trained_unit: UnitStats = structure.get_trained_unit_stats()

			if trained_unit == null:
				button.visible = false
				continue

			button.visible = true
			button.text = "%s (%d)" % [trained_unit.unit_name, trained_unit.cost]
			button.icon = trained_unit.icon_texture

			var can_afford_unit: bool = true

			if game_manager != null:
				can_afford_unit = game_manager.can_afford(structure.owner_team_id, trained_unit.cost)

			button.disabled = not can_afford_unit

		elif kind == "build":
			var structure_index: int = int(entry["index"])

			if structure_index < 0 or structure_index >= buildable_structure_stats.size():
				button.visible = false
				continue

			var build_stats: StructureStats = buildable_structure_stats[structure_index]

			if build_stats == null:
				button.visible = false
				continue

			button.visible = true
			button.text = "%s (%d)" % [build_stats.structure_name, build_stats.cost]
			button.icon = build_stats.icon_texture

			var can_afford_structure: bool = true

			if game_manager != null:
				can_afford_structure = game_manager.can_afford(structure.owner_team_id, build_stats.cost)

			button.disabled = not can_afford_structure


func _clear_production_buttons_if_needed() -> void:
	if _last_production_structure_id == -1:
		return

	_last_production_structure_id = -1
	_dynamic_production_buttons.clear()

	if production_grid != null:
		for child in production_grid.get_children():
			child.queue_free()


func _on_train_current_structure_pressed() -> void:
	if selection_controller == null:
		return

	if structure_manager == null:
		return

	var selected_structure_id: int = selection_controller.selected_structure_id

	if selected_structure_id == -1:
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null:
		return

	if not structure.is_alive:
		return

	if not structure.can_train_units():
		return

	var trained_unit: UnitStats = structure.get_trained_unit_stats()

	if trained_unit == null:
		return

	if _should_use_network_commands():
		match_net_controller.request_queue_unit(selected_structure_id, trained_unit)
		return

	if game_manager != null:
		if not game_manager.spend_credits(structure.owner_team_id, trained_unit.cost):
			return

	structure_manager.queue_unit_production(selected_structure_id, trained_unit)


func _on_build_structure_option_pressed(structure_index: int) -> void:
	if selection_controller == null:
		return

	if structure_manager == null:
		return

	if structure_placement_controller == null:
		return

	if structure_index < 0 or structure_index >= buildable_structure_stats.size():
		return

	if structure_index >= buildable_structure_scenes.size():
		return

	var build_stats: StructureStats = buildable_structure_stats[structure_index]
	var build_scene: PackedScene = buildable_structure_scenes[structure_index]

	if build_stats == null or build_scene == null:
		return

	var selected_structure_id: int = selection_controller.selected_structure_id

	if selected_structure_id == -1:
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null:
		return

	if not structure.is_alive:
		return

	if not structure.can_place_structures():
		return

	if game_manager != null:
		if not game_manager.can_afford(structure.owner_team_id, build_stats.cost):
			return

	if _has_last_virtual_pointer_world:
		if structure_placement_controller.has_method("set_external_pointer_world"):
			structure_placement_controller.call("set_external_pointer_world", _last_virtual_pointer_world)

	structure_placement_controller.begin_placement(
		structure.owner_team_id,
		build_stats,
		build_scene,
		selected_structure_id
	)


func _refresh_resource_panel() -> void:
	if resource_panel != null:
		resource_panel.visible = true

	var local_team_id: int = -1

	if selection_controller != null:
		local_team_id = selection_controller.player_team_id

	var credit_value: int = credits
	var income_value: float = 0.0

	if game_manager != null and local_team_id != -1:
		credit_value = int(floor(game_manager.get_team_credits(local_team_id)))
		income_value = game_manager.get_team_income_per_second(local_team_id)

	if credits_label != null:
		credits_label.text = "Credits: %d" % credit_value

	if income_label != null:
		income_label.text = "Income/sec: %.1f" % income_value


func _refresh_location_label() -> void:
	if location_label == null:
		return

	var camera_pos: Vector2 = Vector2.ZERO

	if camera_pan_controller != null and camera_pan_controller.camera != null:
		camera_pos = camera_pan_controller.camera.get_screen_center_position()
	else:
		location_label.text = "X: 0 Y: 0"
		return

	location_label.text = "X: %d Y: %d" % [
		int(round(camera_pos.x)),
		int(round(camera_pos.y))
	]


func _refresh_status_panel() -> void:
	if status_panel != null:
		status_panel.visible = true

	if match_timer_label != null:
		match_timer_label.text = "Time: %s" % _format_match_time(match_time_seconds)

	if fps_label != null:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if teams_alive_label != null:
		if match_controller != null:
			var alive: int = match_controller.get_alive_runtime_team_count()
			var total: int = match_controller.get_total_runtime_team_count()

			teams_alive_label.text = "Teams: %d / %d" % [alive, total]
		else:
			teams_alive_label.text = "Teams: 0 / 0"


func _format_match_time(seconds: float) -> String:
	var total_seconds: int = int(floor(seconds))
	var mins: int = total_seconds / 60
	var secs: int = total_seconds % 60

	return "%02d:%02d" % [mins, secs]


func _count_alive_units_for_team(team_id: int) -> int:
	var count: int = 0

	if unit_manager == null:
		return count

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u != null and u.is_alive and u.owner_team_id == team_id:
			count += 1

	return count


func _count_alive_structures_for_team(team_id: int) -> int:
	var count: int = 0

	if structure_manager == null:
		return count

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure

		if s != null and s.is_alive and s.owner_team_id == team_id:
			count += 1

	return count


func _apply_layout() -> void:
	var s: float = ui_scale
	var margin: float = round(16.0 * s)
	var gap: float = round(16.0 * s)

	var selection_size: Vector2 = Vector2(round(360.0 * s), round(260.0 * s))
	var production_size: Vector2 = Vector2(round(660.0 * s), round(260.0 * s))
	var resource_size: Vector2 = Vector2(round(220.0 * s), round(88.0 * s))
	var status_size: Vector2 = Vector2(round(220.0 * s), round(100.0 * s))

	_place_bottom_left_panel(selection_panel, margin, margin, selection_size)
	_place_bottom_left_panel(production_panel, margin + selection_size.x + gap, margin, production_size)
	_place_top_left_panel(resource_panel, margin, margin, resource_size)
	_place_top_right_panel(status_panel, margin, margin, status_size)

	_apply_widget_sizes(s)
	_apply_font_sizes(s)


func _place_bottom_left_panel(
	panel_node: Control,
	left_margin: float,
	bottom_margin: float,
	panel_size: Vector2
) -> void:
	if panel_node == null:
		return

	panel_node.anchor_left = 0.0
	panel_node.anchor_right = 0.0
	panel_node.anchor_top = 1.0
	panel_node.anchor_bottom = 1.0
	panel_node.offset_left = left_margin
	panel_node.offset_right = left_margin + panel_size.x
	panel_node.offset_top = -bottom_margin - panel_size.y
	panel_node.offset_bottom = -bottom_margin
	panel_node.custom_minimum_size = panel_size


func _place_top_left_panel(
	panel_node: Control,
	left_margin: float,
	top_margin: float,
	panel_size: Vector2
) -> void:
	if panel_node == null:
		return

	panel_node.anchor_left = 0.0
	panel_node.anchor_right = 0.0
	panel_node.anchor_top = 0.0
	panel_node.anchor_bottom = 0.0
	panel_node.offset_left = left_margin
	panel_node.offset_right = left_margin + panel_size.x
	panel_node.offset_top = top_margin
	panel_node.offset_bottom = top_margin + panel_size.y
	panel_node.custom_minimum_size = panel_size


func _place_top_right_panel(
	panel_node: Control,
	right_margin: float,
	top_margin: float,
	panel_size: Vector2
) -> void:
	if panel_node == null:
		return

	panel_node.anchor_left = 1.0
	panel_node.anchor_right = 1.0
	panel_node.anchor_top = 0.0
	panel_node.anchor_bottom = 0.0
	panel_node.offset_left = -right_margin - panel_size.x
	panel_node.offset_right = -right_margin
	panel_node.offset_top = top_margin
	panel_node.offset_bottom = top_margin + panel_size.y
	panel_node.custom_minimum_size = panel_size


func _apply_widget_sizes(s: float) -> void:
	if selection_icon != null:
		selection_icon.custom_minimum_size = Vector2(round(64.0 * s), round(64.0 * s))

	if description_label != null:
		description_label.custom_minimum_size = Vector2(0.0, round(44.0 * s))

	if stat_summary_label != null:
		stat_summary_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if production_scroll != null:
		production_scroll.custom_minimum_size = Vector2(round(320.0 * s), round(120.0 * s))

	if queue_label != null:
		queue_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if progress_label != null:
		progress_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if income_label != null:
		income_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if location_label != null:
		location_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if match_timer_label != null:
		match_timer_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if fps_label != null:
		fps_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if teams_alive_label != null:
		teams_alive_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if type_label != null:
		type_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if name_label != null:
		name_label.custom_minimum_size = Vector2(0.0, round(28.0 * s))

	if health_label != null:
		health_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if unit_count_label != null:
		unit_count_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	if structure_count_label != null:
		structure_count_label.custom_minimum_size = Vector2(0.0, round(24.0 * s))

	_apply_dynamic_button_sizes()


func _apply_dynamic_button_sizes() -> void:
	var size_vec: Vector2 = Vector2(round(150.0 * ui_scale), round(54.0 * ui_scale))

	for entry in _dynamic_production_buttons:
		var button: Button = entry["button"]

		if button != null:
			button.custom_minimum_size = size_vec


func _apply_font_sizes(s: float) -> void:
	var normal_size: int = max(int(round(base_font_size * s)), 12)
	var title_size: int = max(int(round(base_title_font_size * s)), 13)

	_set_label_font_size(type_label, title_size)
	_set_label_font_size(name_label, title_size)
	_set_label_font_size(description_label, normal_size)
	_set_label_font_size(health_label, normal_size)
	_set_label_font_size(stat_summary_label, normal_size)
	_set_label_font_size(unit_count_label, normal_size)
	_set_label_font_size(structure_count_label, normal_size)
	_set_label_font_size(queue_label, normal_size)
	_set_label_font_size(progress_label, normal_size)
	_set_label_font_size(credits_label, normal_size)
	_set_label_font_size(income_label, normal_size)
	_set_label_font_size(location_label, normal_size)
	_set_label_font_size(match_timer_label, normal_size)
	_set_label_font_size(fps_label, normal_size)
	_set_label_font_size(teams_alive_label, normal_size)

	_apply_dynamic_button_fonts()


func _apply_dynamic_button_fonts() -> void:
	var font_size: int = max(int(round(base_font_size * ui_scale)), 12)

	for entry in _dynamic_production_buttons:
		var button: Button = entry["button"]

		if button != null:
			_set_button_font_size(button, font_size)


func _set_label_font_size(label_node: Label, font_size: int) -> void:
	if label_node == null:
		return

	label_node.add_theme_font_size_override("font_size", font_size)


func _set_button_font_size(button_node: Button, font_size: int) -> void:
	if button_node == null:
		return

	button_node.add_theme_font_size_override("font_size", font_size)


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range or control is ScrollContainer:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_production_ui_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()


func _update_camera_ui_block_rect() -> void:
	if camera_pan_controller == null:
		return

	if production_panel == null or not production_panel.visible:
		camera_pan_controller.clear_ui_mouse_block_rect()
		return

	camera_pan_controller.set_ui_mouse_block_rect(production_panel.get_global_rect())


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
