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
@export var preview_z_index: int = 200
@export var preview_use_nearest_filter: bool = true
@export var preview_show_footprint_outline: bool = false
@export var preview_outline_width: float = 2.0
@export var preview_scale_sprite_to_footprint: bool = false

@export_group("Placement")
@export var grid_snap_enabled: bool = false
@export var grid_size: float = 8.0
@export var placement_padding: float = 8.0

var is_placing: bool = false
var placement_owner_team_id: int = -1
var placement_owner_player_index: int = -1
var placement_builder_structure_id: int = -1
var placement_stats: StructureStats = null
var placement_scene: PackedScene = null

var preview_instance: Node2D = null
var preview_sprite: Sprite2D = null
var preview_outline: Line2D = null
var preview_is_valid: bool = false
var preview_world_pos: Vector2 = Vector2.ZERO

var _has_external_pointer_world: bool = false
var _external_pointer_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not is_placing:
		return

	preview_world_pos = _get_snapped_world_position(_get_current_pointer_world())
	preview_is_valid = _can_place_at(preview_world_pos)
	_update_preview_visual()


func _unhandled_input(event: InputEvent) -> void:
	if _has_external_pointer_world:
		return

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


func begin_placement(
	owner_team_id: int,
	build_stats: StructureStats,
	build_scene: PackedScene,
	builder_structure_id: int = -1,
	owner_player_index: int = -1
) -> void:
	if build_stats == null or build_scene == null:
		return

	placement_owner_team_id = owner_team_id
	placement_owner_player_index = owner_player_index
	placement_stats = build_stats
	placement_scene = build_scene
	placement_builder_structure_id = builder_structure_id

	if placement_builder_structure_id == -1 and selection_controller != null:
		placement_builder_structure_id = selection_controller.selected_structure_id

	is_placing = true
	preview_world_pos = _get_snapped_world_position(_get_current_pointer_world())
	preview_is_valid = _can_place_at(preview_world_pos)

	_create_preview()


func handle_virtual_pointer(pointer: VirtualPointerState) -> bool:
	if not is_placing:
		return false

	if placement_owner_player_index != -1 and pointer.player_index != placement_owner_player_index:
		return false

	set_external_pointer_world(pointer.world_pos)

	if pointer.primary_just_pressed:
		_confirm_placement()
		return true

	if pointer.secondary_just_pressed or pointer.cancel_just_pressed:
		cancel_placement()
		return true

	return true


func set_external_pointer_world(world_pos: Vector2) -> void:
	_has_external_pointer_world = true
	_external_pointer_world = world_pos


func clear_external_pointer_world() -> void:
	_has_external_pointer_world = false
	_external_pointer_world = Vector2.ZERO


func cancel_placement() -> void:
	is_placing = false
	placement_owner_team_id = -1
	placement_owner_player_index = -1
	placement_builder_structure_id = -1
	placement_stats = null
	placement_scene = null
	preview_is_valid = false
	preview_world_pos = Vector2.ZERO
	_has_external_pointer_world = false
	_external_pointer_world = Vector2.ZERO

	if preview_instance != null and is_instance_valid(preview_instance):
		preview_instance.queue_free()

	preview_instance = null
	preview_sprite = null
	preview_outline = null


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

	if structure_manager == null:
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

	preview_sprite = null
	preview_outline = null

	if placement_stats == null:
		return

	var parent_node: Node = preview_root if preview_root != null else self

	var root := Node2D.new()
	root.name = "StructurePlacementPreview"
	root.z_index = preview_z_index
	root.global_position = preview_world_pos

	parent_node.add_child(root)
	preview_instance = root

	_create_preview_sprite(root)
	_create_preview_outline(root)

	_apply_preview_tint(valid_color)


func _create_preview_sprite(root: Node2D) -> void:
	if placement_stats == null:
		return

	var texture_to_use: Texture2D = placement_stats.sprite_normal

	if texture_to_use == null:
		return

	var sprite := Sprite2D.new()
	sprite.name = "ShapeSprite"
	sprite.texture = texture_to_use
	sprite.centered = true
	sprite.z_index = 1

	if preview_use_nearest_filter:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if preview_scale_sprite_to_footprint:
		_apply_sprite_footprint_scale(sprite, texture_to_use)

	root.add_child(sprite)
	preview_sprite = sprite


func _create_preview_outline(root: Node2D) -> void:
	if not preview_show_footprint_outline:
		return

	if placement_stats == null:
		return

	var size: Vector2 = placement_stats.footprint_size

	if size.x <= 0.0 or size.y <= 0.0:
		return

	var half: Vector2 = size * 0.5

	var outline := Line2D.new()
	outline.name = "FootprintOutline"
	outline.width = preview_outline_width
	outline.closed = true
	outline.z_index = 0
	outline.points = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])

	root.add_child(outline)
	preview_outline = outline


func _apply_sprite_footprint_scale(sprite: Sprite2D, texture: Texture2D) -> void:
	if placement_stats == null:
		return

	if texture == null:
		return

	var texture_size: Vector2 = texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var target_size: Vector2 = placement_stats.footprint_size

	if target_size.x <= 0.0 or target_size.y <= 0.0:
		return

	var scale_x: float = target_size.x / texture_size.x
	var scale_y: float = target_size.y / texture_size.y
	var uniform_scale: float = min(scale_x, scale_y)

	sprite.scale = Vector2(uniform_scale, uniform_scale)


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

	if preview_sprite != null and is_instance_valid(preview_sprite):
		preview_sprite.modulate = tint

	if preview_outline != null and is_instance_valid(preview_outline):
		preview_outline.default_color = tint
		preview_outline.modulate = Color.WHITE


func _get_current_pointer_world() -> Vector2:
	if _has_external_pointer_world:
		return _external_pointer_world

	return get_global_mouse_position()


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

	var candidate_rect := Rect2(
		world_pos - placement_stats.footprint_size * 0.5,
		placement_stats.footprint_size
	)

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

		if candidate_rect.intersects(existing_rect):
			return false

	return true


func _should_use_network_commands() -> bool:
	return (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and match_net_controller != null
		and match_net_controller.online_enabled
	)
