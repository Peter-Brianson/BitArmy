class_name AITeamManager
extends Node

@export var structure_manager: StructureSimulationManager
@export var unit_manager: UnitSimulationManager
@export var team_manager: TeamManager
@export var game_manager: GameManager

@export_group("Legacy Unit Options")
@export var soldier_unit_stats: UnitStats
@export var sniper_unit_stats: UnitStats
@export var heavy_unit_stats: UnitStats

@export_group("Legacy Trainer Structures")
@export var soldier_trainer_stats: StructureStats
@export var soldier_trainer_scene: PackedScene
@export var sniper_trainer_stats: StructureStats
@export var sniper_trainer_scene: PackedScene
@export var heavy_trainer_stats: StructureStats
@export var heavy_trainer_scene: PackedScene

@export_group("Generic Trainers")
@export var trainer_structure_stats: Array[StructureStats] = []
@export var trainer_structure_scenes: Array[PackedScene] = []

@export_group("Generic Economy Structures")
@export var economy_structure_stats: Array[StructureStats] = []
@export var economy_structure_scenes: Array[PackedScene] = []

@export_group("Generic Support Structures")
@export var support_structure_stats: Array[StructureStats] = []
@export var support_structure_scenes: Array[PackedScene] = []

@export_group("Generic Defense Structures")
@export var defense_structure_stats: Array[StructureStats] = []
@export var defense_structure_scenes: Array[PackedScene] = []

@export_group("Production")
@export var max_queue_size: int = 4
@export var production_check_interval: float = 1.10
@export var minimum_total_units_before_full_mix: int = 8

@export_group("Build Planning")
@export var build_check_interval: float = 2.0
@export var placement_padding: float = 8.0
@export var base_build_distance_from_hq: float = 110.0
@export var build_ring_step: float = 70.0
@export var desired_economy_structures: int = 2
@export var desired_support_structures: int = 2
@export var desired_defense_structures: int = 3
@export var bonus_defense_structures_under_attack: int = 2
@export var army_per_extra_support_structure: int = 10
@export var army_per_extra_defense_structure: int = 8

@export_group("Defense")
@export var defense_check_interval: float = 0.50
@export var base_defense_radius: float = 220.0
@export var defense_response_radius: float = 360.0

@export_group("Squads")
@export var squad_launch_interval: float = 2.5
@export var squad_gather_radius: float = 180.0
@export var squad_min_unit_count: int = 4
@export var squad_max_unit_count: int = 8
@export var staging_distance_from_hq: float = 100.0

@export_group("World Bounds")
@export var world_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# runtime_team_id -> state dictionary
var _ai_teams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if structure_manager == null or team_manager == null or unit_manager == null:
		return

	for runtime_team_id in _ai_teams.keys():
		var state: Dictionary = _ai_teams[runtime_team_id]

		state["production_timer"] = float(state["production_timer"]) - delta
		state["build_timer"] = float(state["build_timer"]) - delta
		state["defense_timer"] = float(state["defense_timer"]) - delta
		state["squad_timer"] = float(state["squad_timer"]) - delta
		state["rally_timer"] = float(state["rally_timer"]) - delta

		var hq_id: int = int(state["hq_id"])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq == null or not hq.is_alive:
			continue

		var base_under_attack: bool = false

		if float(state["defense_timer"]) <= 0.0:
			base_under_attack = _handle_base_defense_for_team(int(runtime_team_id), hq)
			state["defense_timer"] = defense_check_interval
		else:
			base_under_attack = _is_base_under_attack(int(runtime_team_id), hq)

		if float(state["build_timer"]) <= 0.0:
			_handle_build_planning_for_team(int(runtime_team_id), hq, base_under_attack)
			state["build_timer"] = build_check_interval

		if float(state["production_timer"]) <= 0.0:
			_handle_production_for_team(int(runtime_team_id), hq)
			state["production_timer"] = production_check_interval

		if float(state["rally_timer"]) <= 0.0:
			_update_rally_for_team(int(runtime_team_id), hq, base_under_attack)
			state["rally_timer"] = 1.0

		if not base_under_attack and float(state["squad_timer"]) <= 0.0:
			_try_launch_squad(int(runtime_team_id), hq)
			state["squad_timer"] = squad_launch_interval

		_ai_teams[runtime_team_id] = state


func register_ai_team(runtime_team_id: int, hq_id: int) -> void:
	_ai_teams[runtime_team_id] = {
		"hq_id": hq_id,
		"production_timer": _rng.randf_range(0.1, production_check_interval),
		"build_timer": _rng.randf_range(0.1, build_check_interval),
		"defense_timer": _rng.randf_range(0.1, defense_check_interval),
		"squad_timer": _rng.randf_range(0.5, squad_launch_interval),
		"rally_timer": 0.1
	}


func unregister_ai_team(runtime_team_id: int) -> void:
	if _ai_teams.has(runtime_team_id):
		_ai_teams.erase(runtime_team_id)


func clear_all_ai_teams() -> void:
	_ai_teams.clear()


func is_ai_team(runtime_team_id: int) -> bool:
	return _ai_teams.has(runtime_team_id)


func _handle_build_planning_for_team(runtime_team_id: int, hq: StructureRuntime, base_under_attack: bool) -> void:
	var total_units: int = _count_alive_units_for_team(runtime_team_id)

	# 1) Build every trainer eventually so all unit types become available.
	for entry in _get_all_trainer_entries():
		var trainer_stats: StructureStats = entry["stats"]
		var trainer_scene: PackedScene = entry["scene"]

		if trainer_stats == null or trainer_scene == null:
			continue

		if _count_alive_structures_of_stats(runtime_team_id, trainer_stats) <= 0:
			if _try_build_structure_near_hq(runtime_team_id, hq, trainer_stats, trainer_scene):
				return

	# 2) Economy structures early and steadily.
	var desired_econ: int = desired_economy_structures + int(floor(float(total_units) / 12.0))
	for entry in _get_structure_entries(economy_structure_stats, economy_structure_scenes):
		var econ_stats: StructureStats = entry["stats"]
		var econ_scene: PackedScene = entry["scene"]

		if econ_stats == null or econ_scene == null:
			continue

		if _count_alive_structures_of_stats(runtime_team_id, econ_stats) < desired_econ:
			if _try_build_structure_near_hq(runtime_team_id, hq, econ_stats, econ_scene):
				return

	# 3) Support/buff structures scale with army size.
	var desired_support: int = desired_support_structures + int(floor(float(total_units) / max(1.0, float(army_per_extra_support_structure))))
	for entry in _get_structure_entries(support_structure_stats, support_structure_scenes):
		var support_stats: StructureStats = entry["stats"]
		var support_scene: PackedScene = entry["scene"]

		if support_stats == null or support_scene == null:
			continue

		if _count_alive_structures_of_stats(runtime_team_id, support_stats) < desired_support:
			if _try_build_structure_near_hq(runtime_team_id, hq, support_stats, support_scene):
				return

	# 4) Defense structures scale with pressure and army size.
	var desired_defense: int = desired_defense_structures + int(floor(float(total_units) / max(1.0, float(army_per_extra_defense_structure))))
	if base_under_attack:
		desired_defense += bonus_defense_structures_under_attack

	for entry in _get_structure_entries(defense_structure_stats, defense_structure_scenes):
		var defense_stats: StructureStats = entry["stats"]
		var defense_scene: PackedScene = entry["scene"]

		if defense_stats == null or defense_scene == null:
			continue

		if _count_alive_structures_of_stats(runtime_team_id, defense_stats) < desired_defense:
			if _try_build_structure_near_hq(runtime_team_id, hq, defense_stats, defense_scene):
				return


func _handle_production_for_team(runtime_team_id: int, _hq: StructureRuntime) -> void:
	var producers: Array = _get_all_alive_producers_for_team(runtime_team_id)
	if producers.is_empty():
		return

	var total_units: int = _count_alive_units_for_team(runtime_team_id)
	var trained_unit_types: Array = _get_trained_unit_types_from_producers(producers)

	for producer_item in producers:
		var producer: StructureRuntime = producer_item
		if producer == null:
			continue
		if not producer.is_alive:
			continue
		if not producer.can_produce():
			continue
		if not producer.can_train_units():
			continue

		var unit_stats: UnitStats = producer.get_trained_unit_stats()
		if unit_stats == null:
			continue

		var unit_count: int = _count_alive_units_of_type(runtime_team_id, unit_stats)

		var desired_count_for_type: int = 0
		if total_units < minimum_total_units_before_full_mix:
			# Early game: keep everything producing, but favor the cheapest/frontline options naturally by count.
			desired_count_for_type = 2
		else:
			var type_count: int = max(trained_unit_types.size(), 1)
			desired_count_for_type = max(2, int(ceil(float(total_units + type_count) / float(type_count))))

		if unit_count <= desired_count_for_type:
			_try_queue_unit_from_structure(runtime_team_id, producer, unit_stats)
			continue

		# If this type is slightly above target, still occasionally queue it so all types stay in rotation.
		if _rng.randf() < 0.20:
			_try_queue_unit_from_structure(runtime_team_id, producer, unit_stats)


func _try_queue_unit_from_structure(runtime_team_id: int, producer: StructureRuntime, unit_stats: UnitStats) -> void:
	if producer == null:
		return
	if unit_stats == null:
		return
	if not producer.is_alive:
		return
	if not producer.can_produce():
		return
	if not producer.can_train_units():
		return

	var queue_count: int = producer.production_queue.size()
	if producer.current_production != null:
		queue_count += 1

	if queue_count >= max_queue_size:
		return

	if game_manager != null:
		if not game_manager.spend_credits(runtime_team_id, unit_stats.cost):
			return

	structure_manager.queue_unit_production(producer.id, unit_stats)


func _handle_base_defense_for_team(runtime_team_id: int, hq: StructureRuntime) -> bool:
	var intruders: Array = _get_enemy_units_near_position(runtime_team_id, hq.position, base_defense_radius)
	if intruders.is_empty():
		return false

	var responders: Array = _get_friendly_units_near_position(runtime_team_id, hq.position, defense_response_radius)

	for responder in responders:
		var unit: UnitRuntime = responder
		if unit == null:
			continue
		if not unit.is_alive:
			continue

		var closest_intruder: UnitRuntime = _get_closest_enemy_unit_to_position(unit.position, intruders)
		if closest_intruder == null:
			continue

		unit_manager.issue_attack_unit_order(unit.id, closest_intruder.id)

	return true


func _is_base_under_attack(runtime_team_id: int, hq: StructureRuntime) -> bool:
	return not _get_enemy_units_near_position(runtime_team_id, hq.position, base_defense_radius).is_empty()


func _update_rally_for_team(runtime_team_id: int, hq: StructureRuntime, base_under_attack: bool) -> void:
	var nearest_enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if nearest_enemy_hq == null:
		return

	var dir_to_enemy: Vector2 = hq.position.direction_to(nearest_enemy_hq.position)
	if dir_to_enemy.length_squared() <= 0.0001:
		dir_to_enemy = Vector2.RIGHT

	var staging_point: Vector2 = hq.position + dir_to_enemy * staging_distance_from_hq
	var defense_point: Vector2 = hq.position

	var target_rally: Vector2 = defense_point if base_under_attack else staging_point

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue
		if s.owner_team_id != runtime_team_id:
			continue
		if not s.can_produce():
			continue

		s.rally_point = target_rally

	hq.rally_point = target_rally


func _try_launch_squad(runtime_team_id: int, hq: StructureRuntime) -> void:
	var enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if enemy_hq == null:
		return

	var staging_point: Vector2 = _get_staging_point_for_team(runtime_team_id, hq)
	var available: Array = _get_available_units_near_position(runtime_team_id, staging_point, squad_gather_radius)

	if available.size() < squad_min_unit_count:
		return

	var squad: Array = _build_mixed_squad_from_available_units(available)
	if squad.is_empty():
		return

	_issue_squad_attack_move(squad, enemy_hq.position)


func _build_mixed_squad_from_available_units(available: Array) -> Array:
	var squad: Array = []
	var used_unit_type_paths: Dictionary = {}

	# First pass: try to include diverse unit types.
	for item in available:
		var unit: UnitRuntime = item
		if unit == null or not unit.is_alive:
			continue

		var stats_path: String = unit.stats.resource_path
		if not used_unit_type_paths.has(stats_path):
			squad.append(unit)
			used_unit_type_paths[stats_path] = true

		if squad.size() >= squad_max_unit_count:
			return squad

	# Second pass: fill remaining slots by nearest available units.
	for item in available:
		var unit: UnitRuntime = item
		if unit == null or not unit.is_alive:
			continue
		if unit in squad:
			continue

		squad.append(unit)

		if squad.size() >= squad_max_unit_count:
			break

	return squad


func _issue_squad_attack_move(squad: Array, world_target: Vector2) -> void:
	for member in squad:
		var unit: UnitRuntime = member
		if unit == null:
			continue
		if not unit.is_alive:
			continue

		unit_manager.issue_attack_move_order(unit.id, world_target)


func _get_staging_point_for_team(runtime_team_id: int, hq: StructureRuntime) -> Vector2:
	var enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if enemy_hq == null:
		return hq.position

	var dir_to_enemy: Vector2 = hq.position.direction_to(enemy_hq.position)
	if dir_to_enemy.length_squared() <= 0.0001:
		dir_to_enemy = Vector2.RIGHT

	return hq.position + dir_to_enemy * staging_distance_from_hq


func _find_nearest_enemy_hq(runtime_team_id: int, from_pos: Vector2) -> StructureRuntime:
	var best_target: StructureRuntime = null
	var best_distance_sq: float = INF

	for structure in structure_manager.structures.values():
		var target: StructureRuntime = structure

		if target == null:
			continue
		if not target.is_alive:
			continue
		if target.owner_team_id == runtime_team_id:
			continue
		if not team_manager.is_enemy(runtime_team_id, target.owner_team_id):
			continue

		var dist_sq: float = from_pos.distance_squared_to(target.position)
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_target = target

	return best_target


func _try_build_structure_near_hq(runtime_team_id: int, hq: StructureRuntime, stats: StructureStats, scene: PackedScene) -> bool:
	if stats == null or scene == null:
		return false
	if not hq.can_place_structures():
		return false

	if game_manager != null:
		if not game_manager.can_afford(runtime_team_id, stats.cost):
			return false

	var placement_pos: Vector2 = _find_structure_placement_position(hq, stats)
	if placement_pos == Vector2.INF:
		return false

	if game_manager != null:
		if not game_manager.spend_credits(runtime_team_id, stats.cost):
			return false

	structure_manager.spawn_structure(
		stats,
		runtime_team_id,
		placement_pos,
		scene
	)

	return true


func _find_structure_placement_position(hq: StructureRuntime, stats: StructureStats) -> Vector2:
	for ring in range(4):
		var radius: float = base_build_distance_from_hq + build_ring_step * float(ring)
		var candidates: Array = _get_candidate_positions_around_center(hq.position, radius)

		for pos in candidates:
			var p: Vector2 = pos
			if _can_place_structure_at(p, stats):
				return p

	return Vector2.INF


func _get_candidate_positions_around_center(center: Vector2, radius: float) -> Array:
	var results: Array = []
	var steps: int = 12

	for i in range(steps):
		var angle: float = TAU * (float(i) / float(steps))
		var dir := Vector2.RIGHT.rotated(angle)
		results.append(center + dir * radius)

	return results


func _can_place_structure_at(world_pos: Vector2, stats: StructureStats) -> bool:
	if stats == null:
		return false

	var pending_rect: Rect2 = _get_structure_rect(world_pos, stats.footprint_size)

	if not world_rect.encloses(pending_rect):
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

		if pending_rect.intersects(existing_rect):
			return false

	return true


func _get_structure_rect(world_pos: Vector2, footprint_size: Vector2) -> Rect2:
	return Rect2(
		world_pos - footprint_size * 0.5,
		footprint_size
	)


func _count_alive_units_for_team(runtime_team_id: int) -> int:
	var count: int = 0

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit
		if u == null:
			continue
		if not u.is_alive:
			continue
		if u.owner_team_id != runtime_team_id:
			continue

		count += 1

	return count


func _count_alive_units_of_type(runtime_team_id: int, unit_stats: UnitStats) -> int:
	if unit_stats == null:
		return 0

	var count: int = 0

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit
		if u == null:
			continue
		if not u.is_alive:
			continue
		if u.owner_team_id != runtime_team_id:
			continue
		if u.stats != unit_stats:
			continue

		count += 1

	return count


func _count_alive_structures_of_stats(runtime_team_id: int, structure_stats: StructureStats) -> int:
	if structure_stats == null:
		return 0

	var count: int = 0

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue
		if s.owner_team_id != runtime_team_id:
			continue
		if s.stats != structure_stats:
			continue

		count += 1

	return count


func _get_enemy_units_near_position(runtime_team_id: int, center: Vector2, radius: float) -> Array:
	var results: Array = []

	var nearby_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(center, radius)

	for unit_id in nearby_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if not unit.is_alive:
			continue
		if unit.owner_team_id == runtime_team_id:
			continue
		if not team_manager.is_enemy(runtime_team_id, unit.owner_team_id):
			continue
		if unit.position.distance_squared_to(center) > radius * radius:
			continue

		results.append(unit)

	return results


func _get_friendly_units_near_position(runtime_team_id: int, center: Vector2, radius: float) -> Array:
	var results: Array = []

	var nearby_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(center, radius)

	for unit_id in nearby_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if not unit.is_alive:
			continue
		if unit.owner_team_id != runtime_team_id:
			continue
		if unit.position.distance_squared_to(center) > radius * radius:
			continue

		results.append(unit)

	return results


func _get_available_units_near_position(runtime_team_id: int, center: Vector2, radius: float) -> Array:
	var results: Array = []

	var nearby_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(center, radius)

	for unit_id in nearby_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if not unit.is_alive:
			continue
		if unit.owner_team_id != runtime_team_id:
			continue
		if unit.position.distance_squared_to(center) > radius * radius:
			continue
		if not _is_unit_available_for_squad(unit):
			continue

		results.append(unit)

	results.sort_custom(func(a, b): return a.position.distance_squared_to(center) < b.position.distance_squared_to(center))
	return results


func _is_unit_available_for_squad(unit: UnitRuntime) -> bool:
	if unit == null:
		return false
	if not unit.is_alive:
		return false

	return unit.order_mode == UnitRuntime.OrderMode.NONE or unit.order_mode == UnitRuntime.OrderMode.MOVE


func _get_closest_enemy_unit_to_position(from_pos: Vector2, enemies: Array) -> UnitRuntime:
	var best: UnitRuntime = null
	var best_distance_sq: float = INF

	for enemy in enemies:
		var u: UnitRuntime = enemy
		if u == null:
			continue
		if not u.is_alive:
			continue

		var dist_sq: float = from_pos.distance_squared_to(u.position)
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best = u

	return best


func _get_all_alive_producers_for_team(runtime_team_id: int) -> Array:
	var results: Array = []

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue
		if s.owner_team_id != runtime_team_id:
			continue
		if not s.can_produce():
			continue
		if not s.can_train_units():
			continue
		if s.get_trained_unit_stats() == null:
			continue

		results.append(s)

	return results


func _get_trained_unit_types_from_producers(producers: Array) -> Array:
	var results: Array = []
	var seen_paths: Dictionary = {}

	for producer in producers:
		var s: StructureRuntime = producer
		if s == null:
			continue

		var unit_stats: UnitStats = s.get_trained_unit_stats()
		if unit_stats == null:
			continue

		var path: String = unit_stats.resource_path
		if seen_paths.has(path):
			continue

		seen_paths[path] = true
		results.append(unit_stats)

	return results


func _get_all_trainer_entries() -> Array:
	var results: Array = []

	for entry in _get_structure_entries(trainer_structure_stats, trainer_structure_scenes):
		results.append(entry)

	# Legacy fallback support.
	if trainer_structure_stats.is_empty():
		if soldier_trainer_stats != null and soldier_trainer_scene != null:
			results.append({"stats": soldier_trainer_stats, "scene": soldier_trainer_scene})
		if sniper_trainer_stats != null and sniper_trainer_scene != null:
			results.append({"stats": sniper_trainer_stats, "scene": sniper_trainer_scene})
		if heavy_trainer_stats != null and heavy_trainer_scene != null:
			results.append({"stats": heavy_trainer_stats, "scene": heavy_trainer_scene})

	return results


func _get_structure_entries(stats_array: Array, scene_array: Array) -> Array:
	var results: Array = []
	var count: int = min(stats_array.size(), scene_array.size())

	for i in range(count):
		var stats: StructureStats = stats_array[i]
		var scene: PackedScene = scene_array[i]

		if stats == null or scene == null:
			continue

		results.append({
			"stats": stats,
			"scene": scene
		})

	return results
