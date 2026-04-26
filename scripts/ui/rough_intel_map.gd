class_name RoughIntelMap
extends Control

@export_group("Managers")
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var match_controller: MatchController
@export var team_manager: TeamManager
@export var camera_pan_controller: CameraPanController

@export_group("Map")
@export var world_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000)
@export var map_texture: Texture2D
@export var background_color: Color = Color(0.04, 0.055, 0.035, 0.95)
@export var border_color: Color = Color(0.9, 0.9, 0.75, 0.7)

@export_group("Dots")
@export var friendly_dot_radius: float = 2.0
@export var enemy_hq_dot_radius: float = 3.0
@export var camera_dot_radius: float = 2.0
@export var show_friendly_units: bool = true
@export var show_friendly_structures: bool = true
@export var show_enemy_hq_estimates: bool = true
@export var show_camera_position: bool = true

@export_group("Roughness")
@export var enemy_estimate_grid_pixels: float = 450.0
@export var update_interval: float = 0.75

var _timer: float = 0.0
var _friendly_unit_points: Array[Dictionary] = []
var _friendly_structure_points: Array[Dictionary] = []
var _enemy_hq_points: Array[Dictionary] = []
var _camera_position: Vector2 = Vector2.ZERO

@export var viewer_team_id: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = randf() * update_interval
	_refresh_points()


func _process(delta: float) -> void:
	if not visible:
		return

	if not is_visible_in_tree():
		return

	if size.x <= 1.0 or size.y <= 1.0:
		return

	_timer -= delta
	if _timer > 0.0:
		return

	_timer = update_interval
	_refresh_points()
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	draw_rect(rect, background_color, true)

	if map_texture != null:
		draw_texture_rect(map_texture, rect, false)

	draw_rect(rect, border_color, false, 1.0)

	for item in _friendly_structure_points:
		_draw_dot(item, friendly_dot_radius + 1.0)

	for item in _friendly_unit_points:
		_draw_dot(item, friendly_dot_radius)

	for item in _enemy_hq_points:
		_draw_dot(item, enemy_hq_dot_radius)

	if show_camera_position:
		var camera_pos: Vector2 = _world_to_minimap(_camera_position)
		draw_circle(camera_pos, camera_dot_radius, Color.WHITE)


func _draw_dot(item: Dictionary, radius: float) -> void:
	var world_position: Vector2 = item.get("position", Vector2.ZERO)
	var color: Color = item.get("color", Color.WHITE)

	var minimap_position: Vector2 = _world_to_minimap(world_position)

	draw_circle(minimap_position, radius, color)


func _refresh_points() -> void:
	_friendly_unit_points.clear()
	_friendly_structure_points.clear()
	_enemy_hq_points.clear()

	if camera_pan_controller != null:
		_camera_position = camera_pan_controller.global_position

	if match_controller == null:
		return

	if show_friendly_units:
		_collect_friendly_units()

	if show_friendly_structures:
		_collect_friendly_structures()

	if show_enemy_hq_estimates:
		_collect_enemy_hq_estimates()


func _collect_friendly_units() -> void:
	if unit_manager == null:
		return

	for unit_value in unit_manager.units.values():
		var unit: UnitRuntime = unit_value as UnitRuntime

		if unit == null:
			continue

		if not unit.is_alive:
			continue

		if not _is_friendly_to_viewer(unit.owner_team_id):
			continue

		_friendly_unit_points.append({
			"position": unit.position,
			"color": _get_team_color(unit.owner_team_id)
		})


func _collect_friendly_structures() -> void:
	if structure_manager == null:
		return

	for structure_value in structure_manager.structures.values():
		var structure: StructureRuntime = structure_value as StructureRuntime

		if structure == null:
			continue

		if not structure.is_alive:
			continue

		if not _is_friendly_to_viewer(structure.owner_team_id):
			continue

		_friendly_structure_points.append({
			"position": structure.position,
			"color": _get_team_color(structure.owner_team_id)
		})


func _collect_enemy_hq_estimates() -> void:
	if match_controller == null:
		return

	for runtime_team_id in match_controller.runtime_team_to_hq_id.keys():
		var team_id: int = int(runtime_team_id)

		if _is_friendly_to_viewer(team_id):
			continue

		var hq_id: int = int(match_controller.runtime_team_to_hq_id[team_id])

		if structure_manager == null:
			continue

		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq == null:
			continue

		if not hq.is_alive:
			continue

		var rough_position: Vector2 = _quantize_world_position(hq.position)

		_enemy_hq_points.append({
			"position": rough_position,
			"color": _get_team_color(team_id)
		})


func _is_friendly_to_viewer(owner_team_id: int) -> bool:
	if viewer_team_id == -1:
		return _is_friendly_to_any_player(owner_team_id)

	if team_manager == null:
		return owner_team_id == viewer_team_id

	return not team_manager.is_enemy(viewer_team_id, owner_team_id)



func _is_friendly_to_any_player(owner_team_id: int) -> bool:
	if match_controller == null:
		return false

	for runtime_team_id in match_controller.runtime_team_to_control_type.keys():
		var control_type: int = int(match_controller.runtime_team_to_control_type[runtime_team_id])
		if control_type != GameSession.ControlType.PLAYER:
			continue

		var player_team_id: int = int(runtime_team_id)

		if team_manager == null:
			return owner_team_id == player_team_id

		if not team_manager.is_enemy(player_team_id, owner_team_id):
			return true

	return false


func _get_team_color(team_id: int) -> Color:
	if team_manager != null:
		var visual_team_id: int = team_manager.get_visual_team_id(team_id)
		return TeamPalette.get_team_color(visual_team_id)

	return TeamPalette.get_team_color(team_id)


func _quantize_world_position(world_position: Vector2) -> Vector2:
	var grid: float = max(enemy_estimate_grid_pixels, 1.0)

	return Vector2(
		round(world_position.x / grid) * grid,
		round(world_position.y / grid) * grid
	)


func _world_to_minimap(world_position: Vector2) -> Vector2:
	var local_x: float = inverse_lerp(
		world_rect.position.x,
		world_rect.position.x + world_rect.size.x,
		world_position.x
	)

	var local_y: float = inverse_lerp(
		world_rect.position.y,
		world_rect.position.y + world_rect.size.y,
		world_position.y
	)

	return Vector2(
		clamp(local_x, 0.0, 1.0) * size.x,
		clamp(local_y, 0.0, 1.0) * size.y
	)
