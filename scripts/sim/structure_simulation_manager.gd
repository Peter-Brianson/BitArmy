class_name StructureSimulationManager
extends Node

@export var structure_root: Node2D
@export var default_structure_scene: PackedScene
@export var match_net_controller: MatchNetController
@export var unit_manager: UnitSimulationManager
@export var camera_pan_controller: CameraPanController
@export var cull_margin: float = 192.0
@export var cull_update_interval: float = 0.12
@export var team_manager: TeamManager
@export var ai_team_manager: AITeamManager

var structures: Dictionary = {}
var structure_views: Dictionary = {}
var structure_death_flash_played: Dictionary = {}
var structure_death_fx_played: Dictionary = {}
var next_structure_id: int = 1

var _cull_timer: float = 0.0
var _current_cull_rect: Rect2 = Rect2(-1000000, -1000000, 2000000, 2000000)


func _physics_process(delta: float) -> void:
	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_update_cull_rect()
		_cull_timer = cull_update_interval

	var remove_ids: Array[int] = []

	for structure_id in structures.keys():
		var structure: StructureRuntime = structures[structure_id]

		match structure.state:
			StructureRuntime.StructureState.ACTIVE:
				_update_active_structure(structure, delta)
			StructureRuntime.StructureState.DESTROYED:
				_update_destroyed_structure(structure, delta)

		_sync_view_with_culling(structure)

		if structure.is_ready_for_removal():
			remove_ids.append(structure_id)

	for structure_id in remove_ids:
		_remove_structure(structure_id)


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


func _sync_view_with_culling(structure: StructureRuntime) -> void:
	if not structure_views.has(structure.id):
		return

	var view: Node2D = structure_views[structure.id]
	if not is_instance_valid(view):
		return

	var half_size: Vector2 = structure.stats.footprint_size * 0.5
	var rect := Rect2(structure.position - half_size, structure.stats.footprint_size)
	var is_visible_now: bool = _current_cull_rect.intersects(rect)

	if view is CanvasItem:
		(view as CanvasItem).visible = is_visible_now

	if not is_visible_now:
		return

	view.global_position = structure.position

	if view.has_method("apply_structure_runtime_state"):
		view.call(
			"apply_structure_runtime_state",
			structure.state,
			structure.current_health,
			structure.is_alive
		)


func spawn_structure(
	stats: StructureStats,
	team_id: int,
	spawn_position: Vector2,
	scene_override: PackedScene = null
) -> int:
	var structure_id: int = next_structure_id
	next_structure_id += 1

	var structure := StructureRuntime.new()
	structure.setup(structure_id, stats, team_id, spawn_position)
	structures[structure_id] = structure
	structure_death_flash_played[structure_id] = false
	structure_death_fx_played[structure_id] = false

	structure.rally_point = _get_structure_spawn_position(structure)
	_create_view(structure, scene_override)

	return structure_id


func register_existing_structure(view: Node2D, stats: StructureStats, team_id: int) -> int:
	if view == null:
		return -1

	var structure_id: int = next_structure_id
	next_structure_id += 1

	var structure := StructureRuntime.new()
	structure.setup(structure_id, stats, team_id, view.global_position)
	structures[structure_id] = structure
	structure_views[structure_id] = view
	structure_death_flash_played[structure_id] = false
	structure_death_fx_played[structure_id] = false
	structure.rally_point = _get_structure_spawn_position(structure)

	if view.has_method("apply_structure_runtime_setup"):
		var visual_team_id: int = team_id

		if team_manager != null:
			visual_team_id = team_manager.get_visual_team_id(team_id)

		view.call("apply_structure_runtime_setup", structure_id, stats, visual_team_id)

	return structure_id


func get_structure(structure_id: int) -> StructureRuntime:
	if structures.has(structure_id):
		return structures[structure_id]
	return null


func queue_unit_production(structure_id: int, unit_stats: UnitStats) -> void:
	var structure: StructureRuntime = get_structure(structure_id)
	if structure == null:
		return
	if not structure.is_alive:
		return

	structure.queue_unit(unit_stats)


func damage_structure(structure_id: int, amount: int) -> void:
	var structure: StructureRuntime = get_structure(structure_id)
	if structure == null:
		return

	structure.apply_damage(amount)


func destroy_structure(structure_id: int) -> void:
	var structure: StructureRuntime = get_structure(structure_id)
	if structure == null:
		return

	structure.apply_damage(structure.current_health)


func clear_all_structures() -> void:
	for structure_id in structure_views.keys():
		var view: Node = structure_views[structure_id]
		if is_instance_valid(view):
			view.queue_free()

	structures.clear()
	structure_views.clear()
	structure_death_flash_played.clear()
	structure_death_fx_played.clear()
	next_structure_id = 1


func notify_attack_flash(structure_id: int) -> void:
	if not structure_views.has(structure_id):
		return

	var view: Node = structure_views[structure_id]
	if is_instance_valid(view) and view.has_method("play_attack_flash"):
		view.call("play_attack_flash")


func notify_hit_flash(structure_id: int) -> void:
	if not structure_views.has(structure_id):
		return

	var view: Node = structure_views[structure_id]
	if is_instance_valid(view) and view.has_method("play_hit_flash"):
		view.call("play_hit_flash")


func notify_death_flash(structure_id: int) -> void:
	if not structure_views.has(structure_id):
		return

	var view: Node = structure_views[structure_id]
	if is_instance_valid(view) and view.has_method("play_death_flash"):
		view.call("play_death_flash")


func _update_active_structure(structure: StructureRuntime, delta: float) -> void:
	_update_production(structure, delta)
	_update_structure_combat(structure, delta)


func _update_structure_combat(structure: StructureRuntime, delta: float) -> void:
	if unit_manager == null:
		return
	if team_manager == null:
		return
	if not structure.is_alive:
		return
	if not structure.can_attack():
		return

	if structure.attack_cooldown_left > 0.0:
		structure.attack_cooldown_left -= delta

	if structure.attack_windup_left > 0.0:
		structure.attack_windup_left -= delta

	var target: UnitRuntime = null

	if structure.target_unit_id != -1:
		target = unit_manager.get_unit(structure.target_unit_id)

	if not _is_valid_structure_target(structure, target):
		structure.target_unit_id = _find_best_structure_target(structure)
		target = unit_manager.get_unit(structure.target_unit_id)

	if not _is_valid_structure_target(structure, target):
		return

	if not _is_structure_target_in_range(structure, target):
		return

	if structure.attack_windup_left <= 0.0 and structure.attack_cooldown_left <= 0.0:
		structure.attack_windup_left = structure.get_attack_windup()
		structure.attack_cooldown_left = structure.get_attack_cooldown()
		structure.attack_has_landed = false

	if structure.attack_windup_left <= 0.0 and not structure.attack_has_landed:
		target.apply_damage(structure.get_attack_damage())
		structure.attack_has_landed = true

		notify_attack_flash(structure.id)
		if match_net_controller != null:
			match_net_controller.broadcast_structure_attack_flash(structure.id)

		unit_manager.notify_hit_flash(target.id)
		if match_net_controller != null:
			match_net_controller.broadcast_unit_hit_flash(target.id)

		if AudioHub != null:
			AudioHub.play_unit_shoot(structure.position, self)
		notify_attack_flash(structure.id)
		unit_manager.notify_hit_flash(target.id)

		if AudioHub != null:
			AudioHub.play_unit_shoot(structure.position, self)


func _is_valid_structure_target(structure: StructureRuntime, target: UnitRuntime) -> bool:
	if structure == null:
		return false
	if target == null:
		return false
	if not structure.can_target_units():
		return false
	if not structure.is_alive:
		return false
	if not target.is_alive:
		return false
	if not team_manager.is_enemy(structure.owner_team_id, target.owner_team_id):
		return false

	return true


func _find_best_structure_target(structure: StructureRuntime) -> int:
	var best_id: int = -1
	var best_distance_sq: float = INF

	var search_radius: float = structure.get_radius() + structure.get_attack_range()
	var nearby_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(structure.position, search_radius)

	for unit_id in nearby_ids:
		var target: UnitRuntime = unit_manager.get_unit(unit_id)
		if not _is_valid_structure_target(structure, target):
			continue

		var total_range: float = structure.get_radius() + structure.get_attack_range() + target.get_radius()
		var dist_sq: float = structure.position.distance_squared_to(target.position)

		if dist_sq <= total_range * total_range and dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_id = target.id

	return best_id


func _is_structure_target_in_range(structure: StructureRuntime, target: UnitRuntime) -> bool:
	if structure == null:
		return false
	if target == null:
		return false

	var total_range: float = structure.get_radius() + structure.get_attack_range() + target.get_radius()
	return structure.position.distance_squared_to(target.position) <= total_range * total_range


func _update_production(structure: StructureRuntime, delta: float) -> void:
	if unit_manager == null:
		return
	if not structure.can_produce():
		return

	structure.start_next_production_if_needed()

	if structure.current_production == null:
		return

	structure.production_progress += delta

	if structure.production_progress >= structure.current_production.build_time:
		var finished_unit: UnitStats = structure.finish_current_production()

		if finished_unit != null:
			var spawn_position: Vector2 = _get_structure_spawn_position(structure)
			var spawned_unit_id: int = unit_manager.spawn_unit(finished_unit, structure.owner_team_id, spawn_position)

			if structure.rally_point.distance_squared_to(spawn_position) > 1.0:
				if ai_team_manager != null and ai_team_manager.is_ai_team(structure.owner_team_id):
					unit_manager.issue_attack_move_order(spawned_unit_id, structure.rally_point)
				else:
					unit_manager.issue_move_order(spawned_unit_id, structure.rally_point)


func _get_structure_spawn_position(structure: StructureRuntime) -> Vector2:
	var half_size: Vector2 = structure.stats.footprint_size * 0.5

	var base_spawn := Vector2(
		structure.position.x,
		structure.position.y + half_size.y
	)

	var default_padding: float = 8.0
	var final_offset := Vector2(
		structure.stats.spawn_offset.x,
		max(structure.stats.spawn_offset.y, default_padding)
	)

	return base_spawn + final_offset


func _update_destroyed_structure(structure: StructureRuntime, delta: float) -> void:
	if not structure_death_fx_played.get(structure.id, false):
		notify_death_flash(structure.id)

		if AudioHub != null:
			AudioHub.play_structure_death(structure.position, self)

		structure_death_fx_played[structure.id] = true

	structure.death_timer_left -= delta


func _create_view(structure: StructureRuntime, scene_override: PackedScene = null) -> void:
	var scene_to_use: PackedScene = scene_override if scene_override != null else default_structure_scene
	if scene_to_use == null:
		return
	if structure_root == null:
		return

	var view := scene_to_use.instantiate() as Node2D
	if view == null:
		return

	structure_root.add_child(view)
	view.global_position = structure.position
	structure_views[structure.id] = view

	if view.has_method("apply_structure_runtime_setup"):
		var visual_team_id: int = structure.owner_team_id
		if team_manager != null:
			visual_team_id = team_manager.get_visual_team_id(structure.owner_team_id)
		view.call("apply_structure_runtime_setup", structure.id, structure.stats, visual_team_id)


func _remove_structure(structure_id: int) -> void:
	if structure_views.has(structure_id):
		var view: Node = structure_views[structure_id]
		if is_instance_valid(view):
			view.queue_free()
		structure_views.erase(structure_id)

	if structure_death_flash_played.has(structure_id):
		structure_death_flash_played.erase(structure_id)

	if structure_death_fx_played.has(structure_id):
		structure_death_fx_played.erase(structure_id)

	if structures.has(structure_id):
		structures.erase(structure_id)
