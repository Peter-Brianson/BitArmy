class_name SelectionController
extends Node2D

@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var match_net_controller: MatchNetController
@export var team_manager: TeamManager

@export_group("Selection")
@export var player_team_id: int = 0
@export var drag_threshold: float = 10.0
@export var drag_fill_color: Color = Color(0.2, 0.8, 1.0, 0.12)
@export var drag_outline_color: Color = Color(0.5, 0.9, 1.0, 0.9)

var selected_structure_ids: Array[int] = []

@export_group("Double Click")
@export var double_click_time_seconds: float = 0.32
@export var double_click_max_world_distance: float = 28.0

var _last_click_kind: String = ""
var _last_click_stats: Resource = null
var _last_click_world_pos: Vector2 = Vector2.INF
var _last_click_msec: int = -999999

@export_group("Debug")
@export var debug_external_input: bool = false

var selected_unit_ids: Array[int] = []
var selected_structure_id: int = -1

var is_left_dragging: bool = false
var is_drag_selecting: bool = false
var drag_start_world: Vector2 = Vector2.ZERO
var drag_current_world: Vector2 = Vector2.ZERO

var _has_external_pointer_world: bool = false
var _external_pointer_world: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	if is_left_dragging:
		drag_current_world = _get_pointer_world()

		if not is_drag_selecting and drag_start_world.distance_to(drag_current_world) >= drag_threshold:
			is_drag_selecting = true

	queue_redraw()


func _draw() -> void:
	if is_left_dragging and is_drag_selecting:
		var rect_world := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()
		var rect_local := Rect2(to_local(rect_world.position), rect_world.size)

		draw_rect(rect_local, drag_fill_color, true)
		draw_rect(rect_local, drag_outline_color, false, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if _has_external_pointer_world:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("select_all_units"):
			select_all_player_units()
			get_viewport().set_input_as_handled()


func handle_virtual_pointer(pointer: VirtualPointerState) -> bool:
	set_external_pointer_world(pointer.world_pos)

	if pointer.primary_just_pressed:
		primary_pointer_pressed(pointer.world_pos)

	if pointer.primary_just_released:
		primary_pointer_released(pointer.world_pos)

	if pointer.secondary_just_pressed:
		secondary_pointer_pressed(pointer.world_pos)
		return true

	if pointer.cancel_just_pressed:
		clear_selection()
		return true

	return pointer.primary_just_pressed or pointer.primary_just_released or pointer.primary_pressed or is_left_dragging


func set_external_pointer_world(world_pos: Vector2) -> void:
	_has_external_pointer_world = true
	_external_pointer_world = world_pos

	if is_left_dragging:
		drag_current_world = world_pos


func clear_external_pointer_world() -> void:
	_has_external_pointer_world = false


func primary_pointer_pressed(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	is_left_dragging = true
	is_drag_selecting = false
	drag_start_world = world_pos
	drag_current_world = world_pos

	if debug_external_input:
		print("Selection pressed team=", player_team_id, " world=", world_pos)

	queue_redraw()


func primary_pointer_released(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	if not is_left_dragging:
		_select_at(world_pos)
		queue_redraw()
		return

	drag_current_world = world_pos

	if is_drag_selecting:
		_finish_drag_selection()
	else:
		_select_at(world_pos)

	is_left_dragging = false
	is_drag_selecting = false

	if debug_external_input:
		print(
			"Selection released team=",
			player_team_id,
			" world=",
			world_pos,
			" units=",
			selected_unit_ids,
			" structure=",
			selected_structure_id
		)

	queue_redraw()


func secondary_pointer_pressed(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	if not selected_unit_ids.is_empty():
		_issue_context_command(world_pos)
		return

	if not _get_selected_structure_ids().is_empty():
		_issue_structure_rally_command(world_pos)
		return


func clear_selection() -> void:
	selected_unit_ids.clear()
	selected_structure_ids.clear()
	selected_structure_id = -1
	is_left_dragging = false
	is_drag_selecting = false
	queue_redraw()


func _get_pointer_world() -> Vector2:
	if _has_external_pointer_world:
		return _external_pointer_world

	return get_global_mouse_position()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			primary_pointer_pressed(get_global_mouse_position())
		else:
			primary_pointer_released(get_global_mouse_position())

		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		secondary_pointer_pressed(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return


func _finish_drag_selection() -> void:
	selected_structure_id = -1
	selected_structure_ids.clear()
	selected_unit_ids.clear()

	var rect := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()

	if unit_manager == null:
		return

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if not _is_owner_friendly(u.owner_team_id):
			continue

		if rect.has_point(u.position):
			selected_unit_ids.append(u.id)

	queue_redraw()

func _select_at(world_pos: Vector2) -> void:
	var own_unit_id: int = _find_own_unit_at(world_pos)

	if own_unit_id != -1:
		var clicked_unit: UnitRuntime = unit_manager.get_unit(own_unit_id)

		if clicked_unit == null:
			clear_selection()
			return

		var is_double: bool = _is_double_click("unit", clicked_unit.stats, world_pos)

		selected_structure_id = -1
		selected_structure_ids.clear()
		selected_unit_ids.clear()

		if is_double:
			_select_all_units_of_stats(clicked_unit.stats)
		else:
			selected_unit_ids.append(own_unit_id)

		_remember_click("unit", clicked_unit.stats, world_pos)
		queue_redraw()
		return

	var own_structure_id: int = _find_own_structure_at(world_pos)

	if own_structure_id != -1:
		var clicked_structure: StructureRuntime = structure_manager.get_structure(own_structure_id)

		if clicked_structure == null:
			clear_selection()
			return

		var is_double_structure: bool = _is_double_click("structure", clicked_structure.stats, world_pos)

		selected_unit_ids.clear()
		selected_structure_ids.clear()

		if is_double_structure:
			_select_all_structures_of_stats(clicked_structure.stats)
		else:
			selected_structure_ids.append(own_structure_id)
			selected_structure_id = own_structure_id

		_remember_click("structure", clicked_structure.stats, world_pos)
		queue_redraw()
		return

	selected_unit_ids.clear()
	selected_structure_ids.clear()
	selected_structure_id = -1
	queue_redraw()

func _is_double_click(kind: String, stats: Resource, world_pos: Vector2) -> bool:
	if stats == null:
		return false

	if _last_click_kind != kind:
		return false

	if _last_click_stats != stats:
		return false

	var elapsed_seconds: float = float(Time.get_ticks_msec() - _last_click_msec) / 1000.0

	if elapsed_seconds > double_click_time_seconds:
		return false

	if _last_click_world_pos == Vector2.INF:
		return false

	var max_dist_sq: float = double_click_max_world_distance * double_click_max_world_distance

	return _last_click_world_pos.distance_squared_to(world_pos) <= max_dist_sq


func _remember_click(kind: String, stats: Resource, world_pos: Vector2) -> void:
	_last_click_kind = kind
	_last_click_stats = stats
	_last_click_world_pos = world_pos
	_last_click_msec = Time.get_ticks_msec()


func _select_all_units_of_stats(target_stats: UnitStats) -> void:
	selected_unit_ids.clear()
	selected_structure_ids.clear()
	selected_structure_id = -1

	if unit_manager == null:
		return

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if not _is_owner_friendly(u.owner_team_id):
			continue

		if u.stats != target_stats:
			continue

		selected_unit_ids.append(u.id)


func _select_all_structures_of_stats(target_stats: StructureStats) -> void:
	selected_unit_ids.clear()
	selected_structure_ids.clear()
	selected_structure_id = -1

	if structure_manager == null:
		return

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure

		if s == null:
			continue

		if not s.is_alive:
			continue

		if not _is_owner_friendly(s.owner_team_id):
			continue

		if s.stats != target_stats:
			continue

		selected_structure_ids.append(s.id)

	if not selected_structure_ids.is_empty():
		selected_structure_id = selected_structure_ids[0]

func _issue_context_command(world_pos: Vector2) -> void:
	if selected_unit_ids.is_empty():
		return

	var target_info: Dictionary = _resolve_right_click_target(world_pos)
	var attack_move_held: bool = Input.is_action_pressed("attack_move_modifier")

	match str(target_info.get("kind", "")):
		"enemy_unit":
			var target_unit_id: int = int(target_info.get("id", -1))

			if _should_use_network_commands():
				match_net_controller.request_attack_unit(selected_unit_ids, target_unit_id)
			else:
				unit_manager.issue_attack_unit_order_many(selected_unit_ids, target_unit_id)

		"enemy_structure":
			var target_structure_id: int = int(target_info.get("id", -1))

			if _should_use_network_commands():
				match_net_controller.request_attack_structure(selected_unit_ids, target_structure_id)
			else:
				unit_manager.issue_attack_structure_order_many(selected_unit_ids, target_structure_id)

		_:
			if attack_move_held:
				if _should_use_network_commands():
					match_net_controller.request_attack_move_units(selected_unit_ids, world_pos)
				else:
					unit_manager.issue_attack_move_order_many(selected_unit_ids, world_pos)
			else:
				if _should_use_network_commands():
					match_net_controller.request_move_units(selected_unit_ids, world_pos)
				else:
					unit_manager.issue_move_order_many(selected_unit_ids, world_pos)


func _issue_structure_rally_command(world_pos: Vector2) -> void:
	var ids: Array[int] = _get_selected_structure_ids()

	if ids.is_empty():
		return

	if structure_manager == null:
		return

	for structure_id in ids:
		if _should_use_network_commands():
			match_net_controller.request_set_rally(structure_id, world_pos)
			continue

		var structure: StructureRuntime = structure_manager.get_structure(structure_id)

		if structure == null:
			continue

		if not structure.is_alive:
			continue

		structure.rally_point = world_pos

	queue_redraw()

func _get_selected_structure_ids() -> Array[int]:
	var ids: Array[int] = []

	for structure_id in selected_structure_ids:
		if ids.has(structure_id):
			continue

		ids.append(structure_id)

	if ids.is_empty() and selected_structure_id != -1:
		ids.append(selected_structure_id)

	return ids

func _resolve_right_click_target(world_pos: Vector2) -> Dictionary:
	var enemy_unit_id: int = _find_enemy_unit_at(world_pos)

	if enemy_unit_id != -1:
		return {
			"kind": "enemy_unit",
			"id": enemy_unit_id
		}

	var enemy_structure_id: int = _find_enemy_structure_at(world_pos)

	if enemy_structure_id != -1:
		return {
			"kind": "enemy_structure",
			"id": enemy_structure_id
		}

	return {
		"kind": "",
		"id": -1
	}


func _find_own_unit_at(world_pos: Vector2) -> int:
	if unit_manager == null:
		return -1

	var best_id: int = -1
	var best_dist_sq: float = INF

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if not _is_owner_friendly(u.owner_team_id):
			continue

		var radius: float = max(u.get_radius(), 8.0)
		var dist_sq: float = world_pos.distance_squared_to(u.position)

		if dist_sq <= radius * radius and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = u.id

	return best_id


func _find_enemy_unit_at(world_pos: Vector2) -> int:
	if unit_manager == null:
		return -1

	var best_id: int = -1
	var best_dist_sq: float = INF

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if not _is_owner_enemy(u.owner_team_id):
			continue

		var radius: float = max(u.get_radius(), 8.0)
		var dist_sq: float = world_pos.distance_squared_to(u.position)

		if dist_sq <= radius * radius and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = u.id

	return best_id


func _find_own_structure_at(world_pos: Vector2) -> int:
	if structure_manager == null:
		return -1

	var best_id: int = -1
	var best_dist_sq: float = INF

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure

		if s == null:
			continue

		if not s.is_alive:
			continue

		if not _is_owner_friendly(s.owner_team_id):
			continue

		var half: Vector2 = s.stats.footprint_size * 0.5
		var rect := Rect2(s.position - half, s.stats.footprint_size)

		if rect.has_point(world_pos):
			var dist_sq: float = world_pos.distance_squared_to(s.position)

			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_id = s.id

	return best_id


func _find_enemy_structure_at(world_pos: Vector2) -> int:
	if structure_manager == null:
		return -1

	var best_id: int = -1
	var best_dist_sq: float = INF

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure

		if s == null:
			continue

		if not s.is_alive:
			continue

		if not _is_owner_enemy(s.owner_team_id):
			continue

		var half: Vector2 = s.stats.footprint_size * 0.5
		var rect := Rect2(s.position - half, s.stats.footprint_size)

		if rect.has_point(world_pos):
			var dist_sq: float = world_pos.distance_squared_to(s.position)

			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_id = s.id

	return best_id


func _is_owner_friendly(owner_team_id: int) -> bool:
	if team_manager == null:
		return owner_team_id == player_team_id

	return not team_manager.is_enemy(player_team_id, owner_team_id)


func _is_owner_enemy(owner_team_id: int) -> bool:
	if team_manager == null:
		return owner_team_id != player_team_id

	return team_manager.is_enemy(player_team_id, owner_team_id)


func select_all_player_units() -> void:
	selected_structure_id = -1
	selected_structure_ids.clear()
	selected_unit_ids.clear()

	if unit_manager == null:
		return

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if not _is_owner_friendly(u.owner_team_id):
			continue

		selected_unit_ids.append(u.id)

	queue_redraw()


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
