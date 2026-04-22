class_name StructurePlacementController
extends Node2D

@export_group("References")
@export var selection_controller: SelectionController
@export var structure_manager: StructureSimulationManager
@export var game_manager: GameManager
@export var camera_pan_controller: CameraPanController
@export var match_net_controller: MatchNetController

@export_group("Preview")
@export var preview_root: Node2D
@export var valid_color: Color = Color(0.4, 1.0, 0.4, 0.65)
@export var invalid_color: Color = Color(1.0, 0.35, 0.35, 0.65)
@export var grid_snap_enabled: bool = false
@export var grid_size: float = 8.0
@export var placement_padding: float = 8.0

var is_placing: bool = false
var placement_owner_team_id: int = -1
var placement_builder_structure_id: int = -1
var placement_stats: StructureStats = null
var placement_scene: PackedScene = null

var preview_instance: Node2D = null
var preview_is_valid: bool = false
var preview_world_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not is_placing:
		return

	preview_world_pos = _get_snapped_world_position(get_global_mouse_position())
	preview_is_valid = _can_place_at(preview_world_pos)
	_update_preview_visual()


func _unhandled_input(event: InputEvent) -> void:
	if not is_placing:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement()
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()


func begin_placement(owner_team_id: int, build_stats: StructureStats, build_scene: PackedScene) -> void:
	if build_stats == null or build_scene == null:
		return

	placement_owner_team_id = owner_team_id
	placement_stats = build_stats
	placement_scene = build_scene
	placement_builder_structure_id = -1

	if selection_controller != null:
		placement_builder_structure_id = selection_controller.selected_structure_id

	is_placing = true
	preview_world_pos = _get_snapped_world_position(get_global_mouse_position())
	preview_is_valid = _can_place_at(preview_world_pos)

	_create_preview()


func cancel_placement() -> void:
	is_placing = false
	placement_owner_team_id = -1
	placement_builder_structure_id = -1
	placement_stats = null
	placement_scene = null
	preview_is_valid = false
	preview_world_pos = Vector2.ZERO

	if preview_instance != null and is_instance_valid(preview_instance):
		preview_instance.queue_free()
	preview_instance = null


func _confirm_placement() -> void:
	if not is_placing:
		return
	if placement_stats == null:
		cancel_placement()
		return
	if placement_scene == null:
		cancel_placement()
		return
	if not preview_is_valid:
		return

	if _should_use_network_commands():
		if placement_builder_structure_id == -1:
			return

		match_net_controller.request_place_structure(
			placement_builder_structure_id,
			placement_stats,
			preview_world_pos
		)

		cancel_placement()
		return

	# Offline/local placement.
	if game_manager != null:
		if not game_manager.spend_credits(placement_owner_team_id, placement_stats.cost):
			return

	structure_manager.spawn_structure(
		placement_stats,
		placement_owner_team_id,
		preview_world_pos,
		placement_scene
	)

	cancel_placement()


func _create_preview() -> void:
	if preview_instance != null and is_instance_valid(preview_instance):
		preview_instance.queue_free()

	var parent_node: Node = preview_root if preview_root != null else self
	var instance := placement_scene.instantiate() as Node2D
	if instance == null:
		return

	parent_node.add_child(instance)
	instance.global_position = preview_world_pos
	preview_instance = instance

	_apply_preview_tint(valid_color)


func _update_preview_visual() -> void:
	if preview_instance == null or not is_instance_valid(preview_instance):
		return

	preview_instance.global_position = preview_world_pos

	if preview_is_valid:
		_apply_preview_tint(valid_color)
	else:
		_apply_preview_tint(invalid_color)


func _apply_preview_tint(tint: Color) -> void:
	if preview_instance == null or not is_instance_valid(preview_instance):
		return

	_apply_tint_recursive(preview_instance, tint)


func _apply_tint_recursive(node: Node, tint: Color) -> void:
	if node is CanvasItem:
		(node as CanvasItem).modulate = tint

	for child in node.get_children():
		_apply_tint_recursive(child, tint)


func _get_snapped_world_position(world_pos: Vector2) -> Vector2:
	if not grid_snap_enabled or grid_size <= 0.0:
		return world_pos

	return Vector2(
		round(world_pos.x / grid_size) * grid_size,
		round(world_pos.y / grid_size) * grid_size
	)


func _can_place_at(world_pos: Vector2) -> bool:
	if placement_stats == null:
		return false
	if structure_manager == null:
		return false

	if camera_pan_controller != null:
		var half: Vector2 = placement_stats.footprint_size * 0.5
		var placement_rect := Rect2(world_pos - half, placement_stats.footprint_size)

		if not camera_pan_controller.world_rect.encloses(placement_rect):
			return false

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue

		var existing_rect := Rect2(
			s.position - s.stats.footprint_size * 0.5 - Vector2(placement_padding, placement_padding),
			s.stats.footprint_size + Vector2(placement_padding * 2.0, placement_padding * 2.0)
		)

		var candidate_rect := Rect2(
			world_pos - placement_stats.footprint_size * 0.5,
			placement_stats.footprint_size
		)

		if candidate_rect.intersects(existing_rect):
			return false

	return true


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
