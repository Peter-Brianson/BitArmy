class_name UnitSimulationManager
extends Node

@export var render_root: Node2D
@export var unit_preview_scene: PackedScene
@export var combat_resolver: CombatResolver
@export var structure_manager: StructureSimulationManager
@export var camera_pan_controller: CameraPanController
@export var team_manager: TeamManager

@export_group("Manual Culling")
@export var cull_margin: float = 128.0
@export var cull_update_interval: float = 0.12

@export_group("Broadphase")
@export var spatial_hash_cell_size: float = 128.0
@export var retarget_interval: float = 0.20

@export_group("Formation")
@export var formation_spacing: float = 18.0
@export var formation_row_width: int = 6

var units: Dictionary = {}
var unit_views: Dictionary = {}
var unit_death_flash_played: Dictionary = {}
var next_unit_id: int = 1

var _cull_timer: float = 0.0
var _current_cull_rect: Rect2 = Rect2(-1000000, -1000000, 2000000, 2000000)

var spatial_hash: SpatialHash2D = SpatialHash2D.new()


func _ready() -> void:
	spatial_hash.cell_size = spatial_hash_cell_size


func _physics_process(delta: float) -> void:
	spatial_hash.cell_size = spatial_hash_cell_size
	_rebuild_spatial_hash()

	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_update_cull_rect()
		_cull_timer = cull_update_interval

	var remove_ids: Array[int] = []

	for unit_id in units.keys():
		var unit: UnitRuntime = units[unit_id]

		match unit.state:
			UnitRuntime.UnitState.IDLE:
				_update_idle(unit, delta)
			UnitRuntime.UnitState.WALK:
				_update_walk(unit, delta)
			UnitRuntime.UnitState.ATTACK:
				_update_attack(unit, delta)
			UnitRuntime.UnitState.DEAD:
				_update_dead(unit, delta)

		_apply_team_bonus_health_adjustment(unit)
		_sync_view_with_culling(unit)

		if unit.is_ready_for_removal():
			remove_ids.append(unit_id)

	for unit_id in remove_ids:
		_remove_unit(unit_id)


func spawn_unit(stats: UnitStats, team_id: int, spawn_position: Vector2) -> int:
	var unit_id: int = next_unit_id
	next_unit_id += 1

	var unit := UnitRuntime.new()
	unit.setup(unit_id, stats, team_id, spawn_position)
	units[unit_id] = unit
	unit_death_flash_played[unit_id] = false

	_create_view(unit)

	return unit_id


func get_unit(unit_id: int) -> UnitRuntime:
	if units.has(unit_id):
		return units[unit_id]
	return null


func issue_move_order(unit_id: int, target_position: Vector2) -> void:
	var unit: UnitRuntime = get_unit(unit_id)
	if unit == null:
		return
	if unit.state == UnitRuntime.UnitState.DEAD:
		return

	unit.set_move_order(target_position)


func issue_move_order_many(unit_ids: Array[int], target_position: Vector2) -> void:
	var formation_targets: Dictionary = _build_formation_targets(unit_ids, target_position)

	for unit_id in unit_ids:
		var final_target: Vector2 = target_position
		if formation_targets.has(unit_id):
			final_target = formation_targets[unit_id]

		issue_move_order(unit_id, final_target)

func _build_formation_targets(unit_ids: Array[int], target_position: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var valid_units: Array[UnitRuntime] = []

	for unit_id in unit_ids:
		var unit: UnitRuntime = get_unit(unit_id)
		if unit == null:
			continue
		if unit.state == UnitRuntime.UnitState.DEAD:
			continue

		valid_units.append(unit)

	if valid_units.is_empty():
		return result

	valid_units.sort_custom(func(a: UnitRuntime, b: UnitRuntime) -> bool:
		return a.position.x < b.position.x
	)

	var row_size: int = max(formation_row_width, 1)
	var spacing: float = max(formation_spacing, 1.0)

	var row_count: int = int(ceil(float(valid_units.size()) / float(row_size)))
	var center_row: float = (float(row_count - 1)) * 0.5

	for i in range(valid_units.size()):
		var unit: UnitRuntime = valid_units[i]

		var row: int = i / row_size
		var col: int = i % row_size

		var units_in_this_row: int = min(row_size, valid_units.size() - row * row_size)
		var center_col: float = (float(units_in_this_row - 1)) * 0.5

		var x_offset: float = (float(col) - center_col) * spacing
		var y_offset: float = (float(row) - center_row) * spacing

		result[unit.id] = target_position + Vector2(x_offset, y_offset)

	return result

func issue_attack_move_order_many(unit_ids: Array[int], target_position: Vector2) -> void:
	for unit_id in unit_ids:
		issue_attack_move_order(unit_id, target_position)

func issue_attack_move_order(unit_id: int, target_position: Vector2) -> void:
	var unit: UnitRuntime = get_unit(unit_id)
	if unit == null:
		return
	if unit.state == UnitRuntime.UnitState.DEAD:
		return

	unit.set_attack_move_order(target_position)


func issue_attack_unit_order(unit_id: int, target_unit_id: int) -> void:
	var unit: UnitRuntime = get_unit(unit_id)
	var target: UnitRuntime = get_unit(target_unit_id)

	if unit == null:
		return
	if target == null:
		return
	if unit.state == UnitRuntime.UnitState.DEAD:
		return
	if not target.is_alive:
		return

	unit.set_attack_unit_order(target_unit_id)


func issue_attack_structure_order(unit_id: int, target_structure_id: int) -> void:
	var unit: UnitRuntime = get_unit(unit_id)
	var target: StructureRuntime = null

	if structure_manager != null:
		target = structure_manager.get_structure(target_structure_id)

	if unit == null:
		return
	if target == null:
		return
	if unit.state == UnitRuntime.UnitState.DEAD:
		return
	if not target.is_alive:
		return

	unit.set_attack_structure_order(target_structure_id)


func issue_attack_unit_order_many(unit_ids: Array[int], target_unit_id: int) -> void:
	for unit_id in unit_ids:
		issue_attack_unit_order(unit_id, target_unit_id)


func issue_attack_structure_order_many(unit_ids: Array[int], target_structure_id: int) -> void:
	for unit_id in unit_ids:
		issue_attack_structure_order(unit_id, target_structure_id)


func kill_unit(unit_id: int) -> void:
	var unit: UnitRuntime = get_unit(unit_id)
	if unit == null:
		return

	unit.apply_damage(unit.current_health)


func clear_all_units() -> void:
	for unit_id in unit_views.keys():
		var view: Node = unit_views[unit_id]
		if is_instance_valid(view):
			view.queue_free()

	units.clear()
	unit_views.clear()
	unit_death_flash_played.clear()
	next_unit_id = 1


func notify_attack_flash(unit_id: int) -> void:
	if not unit_views.has(unit_id):
		return

	var view: Node = unit_views[unit_id]
	if is_instance_valid(view) and view.has_method("play_attack_flash"):
		view.call("play_attack_flash")


func notify_hit_flash(unit_id: int) -> void:
	if not unit_views.has(unit_id):
		return

	var view: Node = unit_views[unit_id]
	if is_instance_valid(view) and view.has_method("play_hit_flash"):
		view.call("play_hit_flash")


func notify_death_flash(unit_id: int) -> void:
	if not unit_views.has(unit_id):
		return

	var view: Node = unit_views[unit_id]
	if is_instance_valid(view) and view.has_method("play_death_flash"):
		view.call("play_death_flash")


func _rebuild_spatial_hash() -> void:
	spatial_hash.clear()

	for unit in units.values():
		var u: UnitRuntime = unit
		if not u.is_alive:
			continue
		spatial_hash.add_unit(u.id, u.position)

	if structure_manager != null:
		for structure in structure_manager.structures.values():
			var s: StructureRuntime = structure
			if not s.is_alive:
				continue
			spatial_hash.add_structure(s.id, s.position, s.stats.footprint_size)


func _update_idle(unit: UnitRuntime, delta: float) -> void:
	unit.previous_position = unit.position
	unit.velocity = Vector2.ZERO

	match unit.order_mode:
		UnitRuntime.OrderMode.MOVE:
			if unit.has_move_target:
				unit.state = UnitRuntime.UnitState.WALK
			return

		UnitRuntime.OrderMode.ATTACK_MOVE:
			unit.retarget_timer_left -= delta

			if unit.retarget_timer_left <= 0.0:
				if combat_resolver != null and combat_resolver.try_find_target_for_unit(unit):
					if combat_resolver.is_current_target_in_attack_range(unit):
						unit.state = UnitRuntime.UnitState.ATTACK
					else:
						unit.move_target = combat_resolver.get_current_target_approach_position(unit)
						unit.has_move_target = true
						unit.state = UnitRuntime.UnitState.WALK
					_schedule_next_retarget(unit)
					return

				_schedule_next_retarget(unit)

			if unit.has_attack_move_destination:
				unit.move_target = unit.attack_move_destination
				unit.has_move_target = true
				unit.state = UnitRuntime.UnitState.WALK
			else:
				unit.clear_attack_move_order()
			return

		UnitRuntime.OrderMode.ATTACK_UNIT, UnitRuntime.OrderMode.ATTACK_STRUCTURE:
			if combat_resolver != null and combat_resolver.validate_or_refresh_target(unit):
				if combat_resolver.is_current_target_in_attack_range(unit):
					unit.state = UnitRuntime.UnitState.ATTACK
				else:
					unit.move_target = combat_resolver.get_current_target_approach_position(unit)
					unit.has_move_target = true
					unit.state = UnitRuntime.UnitState.WALK
				return
			else:
				unit.clear_all_orders()
				return

		UnitRuntime.OrderMode.NONE:
			pass

	unit.retarget_timer_left -= delta
	if unit.retarget_timer_left <= 0.0:
		if combat_resolver != null and combat_resolver.try_find_target_for_unit(unit):
			if combat_resolver.is_current_target_in_attack_range(unit):
				unit.state = UnitRuntime.UnitState.ATTACK
			else:
				unit.move_target = combat_resolver.get_current_target_approach_position(unit)
				unit.has_move_target = true
				unit.state = UnitRuntime.UnitState.WALK
			_schedule_next_retarget(unit)
			return

		_schedule_next_retarget(unit)

	if unit.has_move_target:
		unit.state = UnitRuntime.UnitState.WALK


func _update_walk(unit: UnitRuntime, delta: float) -> void:
	unit.previous_position = unit.position

	if combat_resolver != null:
		match unit.order_mode:
			UnitRuntime.OrderMode.MOVE:
				pass

			UnitRuntime.OrderMode.ATTACK_MOVE:
				unit.retarget_timer_left -= delta

				if unit.retarget_timer_left <= 0.0:
					if unit.has_valid_target() or combat_resolver.try_find_target_for_unit(unit):
						if combat_resolver.is_current_target_in_attack_range(unit):
							unit.velocity = Vector2.ZERO
							unit.state = UnitRuntime.UnitState.ATTACK
							_schedule_next_retarget(unit)
							return

						unit.move_target = combat_resolver.get_current_target_approach_position(unit)
						unit.has_move_target = true
					else:
						if unit.has_attack_move_destination:
							unit.move_target = unit.attack_move_destination
							unit.has_move_target = true

					_schedule_next_retarget(unit)

			UnitRuntime.OrderMode.ATTACK_UNIT, UnitRuntime.OrderMode.ATTACK_STRUCTURE:
				if not combat_resolver.validate_or_refresh_target(unit):
					unit.clear_all_orders()
					return

				unit.move_target = combat_resolver.get_current_target_approach_position(unit)
				unit.has_move_target = true

				if combat_resolver.is_current_target_in_attack_range(unit):
					unit.velocity = Vector2.ZERO
					unit.state = UnitRuntime.UnitState.ATTACK
					return

			UnitRuntime.OrderMode.NONE:
				unit.retarget_timer_left -= delta

				if unit.retarget_timer_left <= 0.0:
					if unit.has_valid_target() or combat_resolver.try_find_target_for_unit(unit):
						unit.move_target = combat_resolver.get_current_target_approach_position(unit)
						unit.has_move_target = true

						if combat_resolver.is_current_target_in_attack_range(unit):
							unit.velocity = Vector2.ZERO
							unit.state = UnitRuntime.UnitState.ATTACK
							_schedule_next_retarget(unit)
							return

					_schedule_next_retarget(unit)

	if not unit.has_move_target:
		unit.velocity = Vector2.ZERO
		unit.state = UnitRuntime.UnitState.IDLE
		return

	var to_target: Vector2 = unit.move_target - unit.position
	var distance: float = to_target.length()
	var stop_distance: float = max(unit.stats.radius * 0.35, 1.0)

	if distance <= stop_distance:
		unit.position = unit.move_target
		unit.velocity = Vector2.ZERO

		if unit.order_mode == UnitRuntime.OrderMode.MOVE:
			unit.clear_move_order()
			unit.state = UnitRuntime.UnitState.IDLE
		elif unit.order_mode == UnitRuntime.OrderMode.ATTACK_MOVE:
			unit.clear_attack_move_order()
			unit.clear_move_order()
			unit.state = UnitRuntime.UnitState.IDLE
		elif unit.order_mode == UnitRuntime.OrderMode.ATTACK_UNIT or unit.order_mode == UnitRuntime.OrderMode.ATTACK_STRUCTURE:
			if combat_resolver != null and combat_resolver.is_current_target_in_attack_range(unit):
				unit.state = UnitRuntime.UnitState.ATTACK
			else:
				unit.has_move_target = false
		else:
			unit.clear_move_order()
			unit.state = UnitRuntime.UnitState.IDLE
		return

	var desired_velocity: Vector2 = to_target.normalized() * unit.stats.move_speed
	var separation: Vector2 = _get_separation_vector(unit)
	unit.velocity = desired_velocity + separation

	if unit.velocity.length() > unit.stats.move_speed:
		unit.velocity = unit.velocity.normalized() * unit.stats.move_speed

	if unit.velocity.length_squared() > 0.001:
		unit.facing_dir = unit.velocity.normalized()

	unit.position += unit.velocity * delta


func _update_attack(unit: UnitRuntime, delta: float) -> void:
	if combat_resolver == null:
		unit.state = UnitRuntime.UnitState.IDLE
		return

	_face_current_target(unit)
	combat_resolver.process_unit_attack(unit, delta)


func _update_dead(unit: UnitRuntime, delta: float) -> void:
	unit.previous_position = unit.position
	unit.velocity = Vector2.ZERO

	if not unit_death_flash_played.get(unit.id, false):
		notify_death_flash(unit.id)
		unit_death_flash_played[unit.id] = true

	unit.death_timer_left -= delta


func _face_current_target(unit: UnitRuntime) -> void:
	if combat_resolver == null:
		return

	var target_pos: Vector2 = combat_resolver.get_current_target_position(unit)
	var dir: Vector2 = target_pos - unit.position
	if dir.length_squared() > 0.001:
		unit.facing_dir = dir.normalized()


func _get_separation_vector(unit: UnitRuntime) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var check_radius: float = unit.stats.radius * 2.2

	var nearby_ids: Array[int] = spatial_hash.query_unit_ids_in_radius(unit.position, check_radius)

	for other_id in nearby_ids:
		if other_id == unit.id:
			continue

		var other: UnitRuntime = get_unit(other_id)
		if other == null:
			continue
		if other.state == UnitRuntime.UnitState.DEAD:
			continue

		var offset: Vector2 = unit.position - other.position
		var distance: float = offset.length()

		if distance <= 0.001:
			continue
		if distance > check_radius:
			continue

		var strength: float = (check_radius - distance) / check_radius
		push += offset.normalized() * strength * unit.stats.move_speed * 0.35

	return push


func _schedule_next_retarget(unit: UnitRuntime) -> void:
	unit.retarget_timer_left = retarget_interval + float(unit.id % 5) * 0.03


func _apply_team_bonus_health_adjustment(unit: UnitRuntime) -> void:
	if unit == null:
		return
	if not unit.is_alive:
		return
	if team_manager == null:
		return

	var new_effective_max: int = unit.get_effective_max_health(team_manager)
	var old_effective_max: int = unit.cached_effective_max_health
	var health_delta: int = new_effective_max - old_effective_max

	if health_delta > 0:
		unit.current_health += health_delta

	unit.cached_effective_max_health = new_effective_max
	unit.current_health = min(unit.current_health, new_effective_max)


func _create_view(unit: UnitRuntime) -> void:
	if unit_preview_scene == null:
		return
	if render_root == null:
		return

	var view := unit_preview_scene.instantiate() as Node2D
	if view == null:
		return

	render_root.add_child(view)
	view.global_position = unit.position

	if view.has_method("apply_unit_runtime_setup"):
		view.call("apply_unit_runtime_setup", unit.id, unit.stats, unit.owner_team_id)
	else:
		view.set("stats", unit.stats)
		if view is CanvasItem:
			view.queue_redraw()

	unit_views[unit.id] = view


func _update_cull_rect() -> void:
	if camera_pan_controller == null or camera_pan_controller.camera == null:
		_current_cull_rect = Rect2(-1000000, -1000000, 2000000, 2000000)
		return

	var cam: Camera2D = camera_pan_controller.camera
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = cam.get_screen_center_position()
	var half_extents: Vector2 = viewport_size * 0.5 * cam.zoom
	var margin_vec := Vector2(cull_margin, cull_margin)

	_current_cull_rect = Rect2(
		center - half_extents - margin_vec,
		half_extents * 2.0 + margin_vec * 2.0
	)


func _sync_view_with_culling(unit: UnitRuntime) -> void:
	if not unit_views.has(unit.id):
		return

	var view: Node2D = unit_views[unit.id]
	if not is_instance_valid(view):
		return

	var is_visible_now: bool = _current_cull_rect.has_point(unit.position)

	if view is CanvasItem:
		(view as CanvasItem).visible = is_visible_now

	if not is_visible_now:
		return

	view.global_position = unit.position

	if view.has_method("apply_unit_runtime_state"):
		view.call(
			"apply_unit_runtime_state",
			unit.state,
			unit.current_health,
			unit.is_alive,
			unit.owner_team_id,
			unit.facing_dir
		)


func _remove_unit(unit_id: int) -> void:
	if unit_views.has(unit_id):
		var view: Node = unit_views[unit_id]
		if is_instance_valid(view):
			view.queue_free()
		unit_views.erase(unit_id)

	if unit_death_flash_played.has(unit_id):
		unit_death_flash_played.erase(unit_id)

	if units.has(unit_id):
		units.erase(unit_id)
