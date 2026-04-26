class_name UnitBatchRenderer2D
extends Node2D

@export var team_manager: TeamManager
@export var camera_pan_controller: CameraPanController
@export var unit_manager: UnitSimulationManager

@export_group("Fallback")
@export var fallback_unit_texture: Texture2D
@export var fallback_color: Color = Color.WHITE

@export_group("Rendering")
@export var cull_margin: float = 128.0
@export var use_body_size_as_sprite_size: bool = false
@export var render_dead_units_until_removed: bool = true
@export var use_nearest_filter: bool = true
@export var batch_z_index: int = 0

@export_group("Walk Animation")
@export var stagger_walk_animation: bool = true

var _instances_by_texture_key: Dictionary = {}
var _multimesh_by_texture_key: Dictionary = {}
var _texture_by_key: Dictionary = {}
var _elapsed_time: float = 0.0

var _flash_color_by_unit_id: Dictionary = {}
var _flash_timer_by_unit_id: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_elapsed_time += delta
	_update_flash_timers(delta)
	_render_all_units()


func notify_attack_flash(unit_id: int) -> void:
	_start_flash(unit_id, Color(1.2, 1.2, 0.8, 1.0), 0.08)


func notify_hit_flash(unit_id: int) -> void:
	_start_flash(unit_id, Color(1.3, 0.8, 0.8, 1.0), 0.10)


func notify_death_flash(unit_id: int) -> void:
	_start_flash(unit_id, Color(0.7, 0.7, 0.7, 1.0), 0.20)


func forget_unit(unit_id: int) -> void:
	_flash_color_by_unit_id.erase(unit_id)
	_flash_timer_by_unit_id.erase(unit_id)


func clear_flash_state() -> void:
	_flash_color_by_unit_id.clear()
	_flash_timer_by_unit_id.clear()


func _start_flash(unit_id: int, color: Color, duration: float) -> void:
	_flash_color_by_unit_id[unit_id] = color
	_flash_timer_by_unit_id[unit_id] = duration


func _update_flash_timers(delta: float) -> void:
	var remove_ids: Array[int] = []

	for unit_id in _flash_timer_by_unit_id.keys():
		var timer: float = float(_flash_timer_by_unit_id[unit_id]) - delta

		if timer <= 0.0:
			remove_ids.append(int(unit_id))
		else:
			_flash_timer_by_unit_id[unit_id] = timer

	for unit_id in remove_ids:
		_flash_timer_by_unit_id.erase(unit_id)
		_flash_color_by_unit_id.erase(unit_id)


func _render_all_units() -> void:
	if unit_manager == null:
		_hide_all_batches()
		return

	var visible_units_by_texture_key: Dictionary = {}
	var cull_rect: Rect2 = _get_cull_rect()

	for unit_value in unit_manager.units.values():
		var unit: UnitRuntime = unit_value

		if not _should_render_unit(unit, cull_rect):
			continue

		var texture: Texture2D = _get_texture_for_unit(unit)

		if texture == null:
			texture = fallback_unit_texture

		if texture == null:
			continue

		var texture_key: String = _get_texture_key(texture)

		if not visible_units_by_texture_key.has(texture_key):
			visible_units_by_texture_key[texture_key] = []
			_get_or_create_batch(texture_key, texture)

		visible_units_by_texture_key[texture_key].append(unit)

	for texture_key in _multimesh_by_texture_key.keys():
		var units_for_texture: Array = visible_units_by_texture_key.get(texture_key, [])
		var mm: MultiMesh = _multimesh_by_texture_key[texture_key]
		var inst: MultiMeshInstance2D = _instances_by_texture_key[texture_key]

		mm.instance_count = units_for_texture.size()
		inst.visible = units_for_texture.size() > 0

		for i in range(units_for_texture.size()):
			var unit: UnitRuntime = units_for_texture[i]
			var texture: Texture2D = _texture_by_key[texture_key]

			mm.set_instance_transform_2d(
				i,
				_get_transform_for_unit(unit, texture)
			)

			mm.set_instance_color(
				i,
				_get_unit_render_color(unit)
			)


func _hide_all_batches() -> void:
	for key in _multimesh_by_texture_key.keys():
		var mm: MultiMesh = _multimesh_by_texture_key[key]
		var inst: MultiMeshInstance2D = _instances_by_texture_key[key]

		mm.instance_count = 0
		inst.visible = false


func _should_render_unit(unit: UnitRuntime, cull_rect: Rect2) -> bool:
	if unit == null:
		return false

	if unit.stats == null:
		return false

	if unit.state == UnitRuntime.UnitState.DEAD:
		if not render_dead_units_until_removed:
			return false

		if unit.death_timer_left <= 0.0:
			return false

	if unit_manager != null and unit_manager.has_method("is_unit_visible_for_batch_render"):
		return bool(unit_manager.call("is_unit_visible_for_batch_render", unit, cull_rect))

	return cull_rect.has_point(unit.position)


func _get_or_create_batch(texture_key: String, texture: Texture2D) -> void:
	if _multimesh_by_texture_key.has(texture_key):
		return

	var quad := QuadMesh.new()

	if use_body_size_as_sprite_size:
		quad.size = Vector2.ONE
	else:
		quad.size = Vector2(
			max(float(texture.get_width()), 1.0),
			max(float(texture.get_height()), 1.0)
		)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 0

	var inst := MultiMeshInstance2D.new()
	inst.name = "UnitBatch_%s" % texture_key.md5_text().substr(0, 8)
	inst.multimesh = mm
	inst.texture = texture
	inst.z_index = batch_z_index
	inst.visible = false

	if use_nearest_filter:
		inst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	add_child(inst)

	_multimesh_by_texture_key[texture_key] = mm
	_instances_by_texture_key[texture_key] = inst
	_texture_by_key[texture_key] = texture


func _get_texture_key(texture: Texture2D) -> String:
	if texture == null:
		return ""

	if texture.resource_path != "":
		return texture.resource_path

	return str(texture.get_instance_id())


func _get_texture_for_unit(unit: UnitRuntime) -> Texture2D:
	if unit == null:
		return null

	if unit.stats == null:
		return null

	var stats: UnitStats = unit.stats

	match unit.state:
		UnitRuntime.UnitState.WALK:
			if stats.sprite_walk_a != null or stats.sprite_walk_b != null:
				return stats.get_walk_frame(_get_walk_frame_for_unit(unit))

			if stats.sprite_walk != null:
				return stats.sprite_walk

			return stats.sprite_idle

		UnitRuntime.UnitState.ATTACK:
			if stats.sprite_attack != null:
				return stats.sprite_attack

			return stats.sprite_idle

		UnitRuntime.UnitState.DEAD:
			if stats.sprite_dead != null:
				return stats.sprite_dead

			return stats.sprite_idle

		_:
			return stats.sprite_idle


func _get_walk_frame_for_unit(unit: UnitRuntime) -> int:
	if unit == null or unit.stats == null:
		return 0

	var fps: float = max(unit.stats.walk_anim_fps, 0.001)
	var time: float = _elapsed_time

	if stagger_walk_animation:
		time += float(unit.id % 7) * 0.061

	return int(floor(time * fps)) % 2


func _get_transform_for_unit(unit: UnitRuntime, texture: Texture2D) -> Transform2D:
	var flip_x: bool = unit.facing_dir.x < 0.0
	var x_scale: float = -1.0 if flip_x else 1.0

	if use_body_size_as_sprite_size:
		var size: Vector2 = unit.stats.body_size
		return Transform2D(
			Vector2(size.x * x_scale, 0.0),
			Vector2(0.0, size.y),
			unit.position
		)

	return Transform2D(
		Vector2(x_scale, 0.0),
		Vector2(0.0, 1.0),
		unit.position
	)


func _get_unit_render_color(unit: UnitRuntime) -> Color:
	if _flash_color_by_unit_id.has(unit.id):
		return _flash_color_by_unit_id[unit.id]

	var visual_team_id: int = unit.owner_team_id

	if team_manager != null:
		visual_team_id = team_manager.get_visual_team_id(unit.owner_team_id)

	return TeamPalette.get_team_color(visual_team_id)


func _get_cull_rect() -> Rect2:
	if camera_pan_controller == null or camera_pan_controller.camera == null:
		return Rect2(-1000000, -1000000, 2000000, 2000000)

	var cam: Camera2D = camera_pan_controller.camera
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = cam.get_screen_center_position()

	var zoom: Vector2 = cam.zoom

	if zoom.x <= 0.0:
		zoom.x = 1.0

	if zoom.y <= 0.0:
		zoom.y = 1.0

	var half_extents := Vector2(
		(viewport_size.x / zoom.x) * 0.5,
		(viewport_size.y / zoom.y) * 0.5
	)

	var margin_vec := Vector2(cull_margin, cull_margin)

	return Rect2(
		center - half_extents - margin_vec,
		half_extents * 2.0 + margin_vec * 2.0
	)
