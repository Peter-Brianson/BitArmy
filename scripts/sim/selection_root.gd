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

var selected_unit_ids: Array[int] = []
var selected_structure_id: int = -1

var is_left_dragging: bool = false
var is_drag_selecting: bool = false
var drag_start_world: Vector2 = Vector2.ZERO
var drag_current_world: Vector2 = Vector2.ZERO

var use_external_pointer_world: bool = false
var external_pointer_world: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	if is_left_dragging:
		drag_current_world = get_pointer_world()

		if not is_drag_selecting and drag_start_world.distance_to(drag_current_world) >= drag_threshold:
			is_drag_selecting = true

		queue_redraw()


func _draw() -> void:
	if not is_left_dragging or not is_drag_selecting:
		return

	var rect_world := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()
	var rect_local := Rect2(to_local(rect_world.position), rect_world.size)

	draw_rect(rect_local, drag_fill_color, true)
	draw_rect(rect_local, drag_outline_color, false, 2.0)


func set_external_pointer_world(world_pos: Vector2) -> void:
	use_external_pointer_world = true
	external_pointer_world = world_pos


func clear_external_pointer_world() -> void:
	use_external_pointer_world = false


func get_pointer_world() -> Vector2:
	if use_external_pointer_world:
		return external_pointer_world

	return get_global_mouse_position()


func primary_pointer_pressed(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	is_left_dragging = true
	is_drag_selecting = false
	drag_start_world = world_pos
	drag_current_world = world_pos

	queue_redraw()


func primary_pointer_released(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	drag_current_world = world_pos

	if is_drag_selecting:
		_finish_drag_selection()
	else:
		_select_at(world_pos)

	is_left_dragging = false
	is_drag_selecting = false

	queue_redraw()


func secondary_pointer_pressed(world_pos: Vector2) -> void:
	set_external_pointer_world(world_pos)

	if not selected_unit_ids.is_empty():
		_issue_context_command(world_pos)
		return

	if selected_structure_id != -1:
		_issue_structure_rally_command(world_pos)
		return


func clear_selection() -> void:
	selected_unit_ids.clear()
	selected_structure_id = -1
	is_left_dragging = false
	is_drag_selecting = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("select_all_units"):
			select_all_player_units()
			get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_left_dragging = true
			is_drag_selecting = false
			drag_start_world = get_pointer_world()
			drag_current_world = drag_start_world
		else:
			var release_world: Vector2 = get_pointer_world()

			if is_drag_selecting:
				_finish_drag_selection()
			else:
				_select_at(release_world)

			is_left_dragging = false
			is_drag_selecting = false

		queue_redraw()

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var world_target: Vector2 = get_pointer_world()

		if not selected_unit_ids.is_empty():
			_issue_context_command(world_target)
			get_viewport().set_input_as_handled()
			return

		if selected_structure_id != -1:
			_issue_structure_rally_command(world_target)
			get_viewport().set_input_as_handled()
			return


func _finish_drag_selection() -> void:
	selected_structure_id = -1
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

		if u.owner_team_id != player_team_id:
			continue

		if rect.has_point(u.position):
			selected_unit_ids.append(u.id)


func _select_at(world_pos: Vector2) -> void:
	var own_unit_id: int = _find_own_unit_at(world_pos)

	if own_unit_id != -1:
		selected_structure_id = -1
		selected_unit_ids.clear()
		selected_unit_ids.append(own_unit_id)
		return

	var own_structure_id: int = _find_own_structure_at(world_pos)

	if own_structure_id != -1:
		selected_unit_ids.clear()
		selected_structure_id = own_structure_id
		return

	selected_unit_ids.clear()
	selected_structure_id = -1

func _is_enemy_team(target_team_id: int) -> bool:
	if team_manager == null:
		return target_team_id != player_team_id

	return team_manager.is_enemy(player_team_id, target_team_id)

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
	if selected_structure_id == -1:
		return

	if structure_manager == null:
		return

	if _should_use_network_commands():
		match_net_controller.request_set_rally(selected_structure_id, world_pos)
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null:
		return

	if not structure.is_alive:
		return

	structure.rally_point = world_pos


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

		if u.owner_team_id != player_team_id:
			continue

		var radius: float = max(u.get_radius(), 6.0)
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

		if not _is_enemy_team(u.owner_team_id):
			continue

		var radius: float = max(u.get_radius(), 6.0)
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

		if s.owner_team_id != player_team_id:
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

		if not _is_enemy_team(s.owner_team_id):
			continue

		var half: Vector2 = s.stats.footprint_size * 0.5
		var rect := Rect2(s.position - half, s.stats.footprint_size)

		if rect.has_point(world_pos):
			var dist_sq: float = world_pos.distance_squared_to(s.position)

			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_id = s.id

	return best_id


func select_all_player_units() -> void:
	selected_structure_id = -1
	selected_unit_ids.clear()

	if unit_manager == null:
		return

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit

		if u == null:
			continue

		if not u.is_alive:
			continue

		if u.owner_team_id != player_team_id:
			continue

		selected_unit_ids.append(u.id)


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
