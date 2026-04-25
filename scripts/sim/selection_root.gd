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

@export_group("Selection Visuals")
@export var draw_selection_visuals: bool = true
@export var use_procedural_fallbacks: bool = false
@export var draw_rally_line: bool = true
@export var rally_line_color: Color = Color(0.5, 1.0, 0.45, 0.85)
@export var rally_point_texture: Texture2D
@export var rally_point_texture_scale: float = 1.0
@export var rally_point_offset: Vector2 = Vector2.ZERO

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
	if draw_selection_visuals:
		_draw_selected_units_from_stats()
		_draw_selected_structure_from_stats()
		_draw_rally_visual()

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

	if selected_structure_id != -1:
		_issue_structure_rally_command(world_pos)
		return


func clear_selection() -> void:
	selected_unit_ids.clear()
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
		selected_structure_id = -1
		selected_unit_ids.clear()
		selected_unit_ids.append(own_unit_id)
		queue_redraw()
		return

	var own_structure_id: int = _find_own_structure_at(world_pos)

	if own_structure_id != -1:
		selected_unit_ids.clear()
		selected_structure_id = own_structure_id
		queue_redraw()
		return

	selected_unit_ids.clear()
	selected_structure_id = -1
	queue_redraw()


func _draw_selected_units_from_stats() -> void:
	if unit_manager == null:
		return

	for unit_id in selected_unit_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)

		if unit == null:
			continue

		if not unit.is_alive:
			continue

		if unit.stats == null:
			continue

		var texture: Texture2D = _get_texture_property(unit.stats, "selection_ring_texture")
		var scale_value: float = _get_float_property(unit.stats, "selection_ring_scale", 1.0)
		var offset_value: Vector2 = _get_vector2_property(unit.stats, "selection_ring_offset", Vector2.ZERO)
		var color_value: Color = _get_color_property(unit.stats, "selection_ring_color", Color.WHITE)

		if texture != null:
			var texture_size: Vector2 = texture.get_size() * scale_value
			var center: Vector2 = to_local(unit.position + offset_value)

			_draw_texture_centered(texture, center, texture_size, color_value)
		elif use_procedural_fallbacks:
			var radius: float = max(unit.get_radius(), 8.0)
			draw_arc(
				to_local(unit.position),
				radius + 3.0,
				0.0,
				TAU,
				32,
				Color(0.45, 0.95, 1.0, 0.95),
				2.0
			)


func _draw_selected_structure_from_stats() -> void:
	if selected_structure_id == -1:
		return

	if structure_manager == null:
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null:
		return

	if not structure.is_alive:
		return

	if structure.stats == null:
		return

	var texture: Texture2D = _get_texture_property(structure.stats, "selection_ring_texture")
	var scale_value: float = _get_float_property(structure.stats, "selection_ring_scale", 1.0)
	var offset_value: Vector2 = _get_vector2_property(structure.stats, "selection_ring_offset", Vector2.ZERO)
	var color_value: Color = _get_color_property(structure.stats, "selection_ring_color", Color.WHITE)

	if texture != null:
		var texture_size: Vector2 = texture.get_size() * scale_value
		var center: Vector2 = to_local(structure.position + offset_value)

		_draw_texture_centered(texture, center, texture_size, color_value)
	elif use_procedural_fallbacks:
		var half: Vector2 = structure.stats.footprint_size * 0.5
		var rect := Rect2(to_local(structure.position - half), structure.stats.footprint_size)

		draw_rect(rect, Color(1.0, 0.9, 0.35, 0.95), false, 2.0)


func _draw_rally_visual() -> void:
	if selected_structure_id == -1:
		return

	if structure_manager == null:
		return

	var structure: StructureRuntime = structure_manager.get_structure(selected_structure_id)

	if structure == null:
		return

	if not structure.is_alive:
		return

	var show_marker: bool = _get_bool_property(structure.stats, "show_rally_marker", true)

	if not show_marker:
		return

	if structure.rally_point.distance_squared_to(structure.position) <= 4.0:
		return

	var start_local: Vector2 = to_local(structure.position)
	var end_world: Vector2 = structure.rally_point + rally_point_offset
	var end_local: Vector2 = to_local(end_world)

	if draw_rally_line:
		draw_line(start_local, end_local, rally_line_color, 2.0)

	if rally_point_texture != null:
		var texture_size: Vector2 = rally_point_texture.get_size() * rally_point_texture_scale
		_draw_texture_centered(rally_point_texture, end_local, texture_size, Color.WHITE)
	elif use_procedural_fallbacks:
		draw_circle(end_local, 5.0, rally_line_color)


func _draw_texture_centered(texture: Texture2D, center: Vector2, size: Vector2, color: Color = Color.WHITE) -> void:
	if texture == null:
		return

	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_texture_rect(
		texture,
		Rect2(center - size * 0.5, size),
		false,
		color
	)


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
	queue_redraw()


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


func _get_texture_property(source: Object, property_name: String) -> Texture2D:
	if source == null:
		return null

	var value: Variant = source.get(property_name)

	if value is Texture2D:
		return value as Texture2D

	return null


func _get_float_property(source: Object, property_name: String, fallback: float) -> float:
	if source == null:
		return fallback

	var value: Variant = source.get(property_name)

	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)

	return fallback


func _get_bool_property(source: Object, property_name: String, fallback: bool) -> bool:
	if source == null:
		return fallback

	var value: Variant = source.get(property_name)

	if typeof(value) == TYPE_BOOL:
		return bool(value)

	return fallback


func _get_vector2_property(source: Object, property_name: String, fallback: Vector2) -> Vector2:
	if source == null:
		return fallback

	var value: Variant = source.get(property_name)

	if value is Vector2:
		return value as Vector2

	return fallback


func _get_color_property(source: Object, property_name: String, fallback: Color) -> Color:
	if source == null:
		return fallback

	var value: Variant = source.get(property_name)

	if value is Color:
		return value as Color

	return fallback


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
