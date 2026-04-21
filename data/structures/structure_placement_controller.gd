class_name StructurePlacementController
extends Node2D

@export var structure_manager: StructureSimulationManager
@export var game_manager: GameManager
@export var selection_controller: SelectionController
@export var camera_pan_controller: CameraPanController

@export_group("Placement")
@export var placement_padding: float = 8.0
@export var valid_fill_color: Color = Color(0.3, 1.0, 0.3, 0.18)
@export var valid_outline_color: Color = Color(0.7, 1.0, 0.7, 0.95)
@export var invalid_fill_color: Color = Color(1.0, 0.2, 0.2, 0.18)
@export var invalid_outline_color: Color = Color(1.0, 0.5, 0.5, 0.95)

var is_active: bool = false
var pending_stats: StructureStats = null
var pending_scene: PackedScene = null
var pending_team_id: int = -1


func _ready() -> void:
	z_as_relative = true
	z_index = 50


func _process(_delta: float) -> void:
	if is_active:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	if event.is_action_pressed("ui_cancel"):
		cancel_placement()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos: Vector2 = get_global_mouse_position()

			if _can_place_at(world_pos):
				if pending_stats != null and game_manager != null:
					if not game_manager.spend_credits(pending_team_id, pending_stats.cost):
						get_viewport().set_input_as_handled()
						return

				var new_structure_id: int = structure_manager.spawn_structure(
					pending_stats,
					pending_team_id,
					world_pos,
					pending_scene
				)

				if selection_controller != null:
					selection_controller.selected_unit_ids.clear()
					selection_controller.selected_structure_id = new_structure_id

				cancel_placement()

			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return


func begin_placement(team_id: int, stats: StructureStats, scene_to_spawn: PackedScene) -> void:
	if stats == null:
		return
	if scene_to_spawn == null:
		return

	pending_team_id = team_id
	pending_stats = stats
	pending_scene = scene_to_spawn
	is_active = true
	queue_redraw()


func cancel_placement() -> void:
	is_active = false
	pending_team_id = -1
	pending_stats = null
	pending_scene = null
	queue_redraw()


func _draw() -> void:
	if not is_active or pending_stats == null:
		return

	var world_pos: Vector2 = get_global_mouse_position()
	var rect_world: Rect2 = _get_pending_rect(world_pos)
	var rect_local := Rect2(to_local(rect_world.position), rect_world.size)

	var is_valid: bool = _can_place_at(world_pos)

	var fill_color: Color = valid_fill_color if is_valid else invalid_fill_color
	var outline_color: Color = valid_outline_color if is_valid else invalid_outline_color

	draw_rect(rect_local, fill_color, true)
	draw_rect(rect_local, outline_color, false, 2.0)


func _can_place_at(world_pos: Vector2) -> bool:
	if structure_manager == null:
		return false
	if pending_stats == null:
		return false

	if not _is_inside_world_bounds(world_pos):
		return false

	if _overlaps_existing_structures(world_pos):
		return false

	return true


func _is_inside_world_bounds(world_pos: Vector2) -> bool:
	if camera_pan_controller == null:
		return true

	var world_rect: Rect2 = camera_pan_controller.world_rect
	var placement_rect: Rect2 = _get_pending_rect(world_pos)

	return world_rect.encloses(placement_rect)


func _overlaps_existing_structures(world_pos: Vector2) -> bool:
	var pending_rect: Rect2 = _get_pending_rect(world_pos)

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue

		var existing_half: Vector2 = s.stats.footprint_size * 0.5
		var existing_rect := Rect2(
			s.position - existing_half - Vector2(placement_padding, placement_padding),
			s.stats.footprint_size + Vector2(placement_padding * 2.0, placement_padding * 2.0)
		)

		if pending_rect.intersects(existing_rect):
			return true

	return false


func _get_pending_rect(world_pos: Vector2) -> Rect2:
	var half: Vector2 = pending_stats.footprint_size * 0.5
	return Rect2(
		world_pos - half,
		pending_stats.footprint_size
	)
