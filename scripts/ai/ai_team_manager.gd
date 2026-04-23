class_name AITeamManager
extends Node

enum AiStrategy {
	BALANCED,
	RUSH,
	TURTLE,
	MACRO,
	TECH
}

@export var structure_manager: StructureSimulationManager
@export var unit_manager: UnitSimulationManager
@export var team_manager: TeamManager
@export var game_manager: GameManager

@export_group("Structure Scene Fallback")
@export var default_structure_scene: PackedScene

@export_group("Trainer Structures")
@export var trainer_structure_stats: Array[StructureStats] = []
@export var trainer_structure_scenes: Array[PackedScene] = []

@export_group("Economy Structures")
@export var economy_structure_stats: Array[StructureStats] = []
@export var economy_structure_scenes: Array[PackedScene] = []

@export_group("Support Structures")
@export var support_structure_stats: Array[StructureStats] = []
@export var support_structure_scenes: Array[PackedScene] = []

@export_group("Defense Structures")
@export var defense_structure_stats: Array[StructureStats] = []
@export var defense_structure_scenes: Array[PackedScene] = []

@export_group("Strategy")
@export var use_rotating_strategies: bool = true
@export var default_strategy: AiStrategy = AiStrategy.BALANCED
@export var production_check_interval: float = 1.0
@export var build_check_interval: float = 2.0
@export var defense_check_interval: float = 0.5
@export var squad_launch_interval: float = 2.5

@export_group("Production")
@export var max_queue_size: int = 4
@export var minimum_total_units_before_full_mix: int = 8
@export var desired_units_per_type_floor: int = 2

@export_group("Building")
@export var placement_padding: float = 8.0
@export var base_build_distance_from_hq: float = 110.0
@export var build_ring_step: float = 70.0
@export var build_ring_count: int = 4
@export var build_points_per_ring: int = 12
@export var world_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000)

@export_group("Defense")
@export var base_defense_radius: float = 220.0
@export var defense_response_radius: float = 360.0

@export_group("Squads")
@export var squad_gather_radius: float = 180.0
@export var squad_min_unit_count: int = 4
@export var squad_max_unit_count: int = 8
@export var staging_distance_from_hq: float = 100.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# runtime_team_id -> state dictionary
var _ai_teams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if structure_manager == null or team_manager == null or unit_manager == null or game_manager == null:
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

		var strategy: int = int(state["strategy"])
		var base_under_attack: bool = false

		if float(state["defense_timer"]) <= 0.0:
			base_under_attack = _handle_base_defense_for_team(int(runtime_team_id), hq)
			state["defense_timer"] = defense_check_interval
		else:
			base_under_attack = _is_base_under_attack(int(runtime_team_id), hq)

		if float(state["build_timer"]) <= 0.0:
			_handle_build_planning_for_team(int(runtime_team_id), hq, strategy, base_under_attack)
			state["build_timer"] = build_check_interval

		if float(state["production_timer"]) <= 0.0:
			_handle_production_for_team(int(runtime_team_id), hq, strategy)
			state["production_timer"] = production_check_interval

		if float(state["rally_timer"]) <= 0.0:
			_update_rally_for_team(int(runtime_team_id), hq, base_under_attack, strategy)
			state["rally_timer"] = 1.0

		if not base_under_attack and float(state["squad_timer"]) <= 0.0:
			_try_launch_squad(int(runtime_team_id), hq, strategy)
			state["squad_timer"] = squad_launch_interval

		_ai_teams[runtime_team_id] = state


func register_ai_team(runtime_team_id: int, hq_id: int, strategy_override: int = -1) -> void:
	var chosen_strategy: int = strategy_override
	if chosen_strategy == -1:
		chosen_strategy = _pick_strategy_for_team(runtime_team_id)

	_ai_teams[runtime_team_id] = {
		"hq_id": hq_id,
		"strategy": chosen_strategy,
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


func _pick_strategy_for_team(runtime_team_id: int) -> int:
	if use_rotating_strategies:
		return runtime_team_id % 5

	return int(default_strategy)


func _handle_build_planning_for_team(runtime_team_id: int, hq: StructureRuntime, strategy: int, base_under_attack: bool) -> void:
	var total_units: int = _count_alive_units_for_team(runtime_team_id)
	var profile: Dictionary = _get_strategy_profile(strategy, total_units, base_under_attack)

	# Phase 1: ensure every listed structure type gets used at least once.
	var category_order: Array = _get_structure_category_order_for_strategy(strategy)

	for category in category_order:
		var entries: Array = _get_entries_for_category_name(str(category))
		for entry in entries:
			var stats: StructureStats = entry["stats"]
			var scene: PackedScene = entry["scene"]

			if stats == null or scene == null:
				continue

			if _count_alive_structures_of_stats(runtime_team_id, stats) <= 0:
				if _try_build_structure_near_hq(runtime_team_id, hq, stats, scene):
					return

	# Phase 2: duplicate structures according to strategy.
	_process_category_duplicates(runtime_team_id, hq, "economy", int(profile["economy_target"]))
	_process_category_duplicates(runtime_team_id, hq, "support", int(profile["support_target"]))
	_process_category_duplicates(runtime_team_id, hq, "defense", int(profile["defense_target"]))


func _process_category_duplicates(runtime_team_id: int, hq: StructureRuntime, category_name: String, target_per_type: int) -> void:
	if target_per_type <= 0:
		return

	var entries: Array = _get_entries_for_category_name(category_name)
	for entry in entries:
		var stats: StructureStats = entry["stats"]
		var scene: PackedScene = entry["scene"]

		if stats == null or scene == null:
			continue

		if _count_alive_structures_of_stats(runtime_team_id, stats) < target_per_type:
			if _try_build_structure_near_hq(runtime_team_id, hq, stats, scene):
				return


func _handle_production_for_team(runtime_team_id: int, _hq: StructureRuntime, strategy: int) -> void:
	var producers: Array = _get_all_alive_producers_for_team(runtime_team_id)
	if producers.is_empty():
		return

	var total_units: int = _count_alive_units_for_team(runtime_team_id)
	var profile: Dictionary = _get_strategy_profile(strategy, total_units, false)

	# First: ensure every trainable unit type appears at least once.
	for producer_item in producers:
		var producer: StructureRuntime = producer_item
		var unit_stats: UnitStats = producer.get_trained_unit_stats()

		if unit_stats == null:
			continue

		if _count_alive_units_of_type(runtime_team_id, unit_stats) <= 0:
			_try_queue_unit_from_structure(runtime_team_id, producer, unit_stats)
			return

	# Then: queue using strategy weights.
	var best_score: float = -INF
	var best_producer: StructureRuntime = null
	var best_unit_stats: UnitStats = null

	for producer_item in producers:
		var producer: StructureRuntime = producer_item
		var unit_stats: UnitStats = producer.get_trained_unit_stats()

		if unit_stats == null:
			continue

		if not _can_queue_on_producer(producer):
			continue

		var score: float = _score_unit_for_strategy(runtime_team_id, unit_stats, total_units, profile)
		score += _rng.randf_range(0.0, 0.15)

		if score > best_score:
			best_score = score
			best_producer = producer
			best_unit_stats = unit_stats

	if best_producer != null and best_unit_stats != null:
		_try_queue_unit_from_structure(runtime_team_id, best_producer, best_unit_stats)


func _score_unit_for_strategy(runtime_team_id: int, unit_stats: UnitStats, total_units: int, profile: Dictionary) -> float:
	var current_count: int = _count_alive_units_of_type(runtime_team_id, unit_stats)
	var frontline_score: float = float(profile["frontline_weight"])
	var ranged_score: float = float(profile["ranged_weight"])
	var heavy_score: float = float(profile["heavy_weight"])

	var role_frontline: float = _get_frontline_value(unit_stats)
	var role_ranged: float = _get_ranged_value(unit_stats)
	var role_heavy: float = _get_heavy_value(unit_stats)

	var score: float = 0.0
	score += role_frontline * frontline_score
	score += role_ranged * ranged_score
	score += role_heavy * heavy_score

	# Favor underrepresented unit types.
	score += max(0.0, float(desired_units_per_type_floor - current_count)) * 0.6
	score += max(0.0, float(total_units / max(1, _get_trainable_unit_type_count(runtime_team_id)) - current_count)) * 0.15

	# Slight preference for lower cost in rush, higher cost in tech/turtle.
	var cost_bias: float = 0.0
	if int(profile["cost_mode"]) == 0:
		cost_bias = -float(unit_stats.cost) * 0.01
	else:
		cost_bias = float(unit_stats.cost) * 0.005

	score += cost_bias
	return score


func _get_frontline_value(unit_stats: UnitStats) -> float:
	if unit_stats == null:
		return 0.0

	var value: float = 0.0
	if unit_stats.attack_range <= 70.0:
		value += 1.0
	if unit_stats.move_speed >= 55.0:
		value += 0.3
	if unit_stats.max_health >= 5:
		value += 0.2
	return value


func _get_ranged_value(unit_stats: UnitStats) -> float:
	if unit_stats == null:
		return 0.0

	var value: float = 0.0
	if unit_stats.attack_range >= 90.0:
		value += 1.0
	if unit_stats.attack_range >= 120.0:
		value += 0.35
	return value


func _get_heavy_value(unit_stats: UnitStats) -> float:
	if unit_stats == null:
		return 0.0

	var value: float = 0.0
	if unit_stats.max_health >= 7:
		value += 1.0
	if unit_stats.move_speed <= 45.0:
		value += 0.25
	if unit_stats.cost >= 6:
		value += 0.25
	return value


func _get_strategy_profile(strategy: int, total_units: int, base_under_attack: bool) -> Dictionary:
	match strategy:
		AiStrategy.RUSH:
			return {
				"economy_target": 1,
				"support_target": 1,
				"defense_target": 1 if not base_under_attack else 2,
				"frontline_weight": 1.4,
				"ranged_weight": 0.55,
				"heavy_weight": 0.75,
				"cost_mode": 0
			}

		AiStrategy.TURTLE:
			return {
				"economy_target": 2,
				"support_target": 2,
				"defense_target": 2 + int(floor(float(total_units) / 8.0)) + (2 if base_under_attack else 0),
				"frontline_weight": 0.9,
				"ranged_weight": 1.25,
				"heavy_weight": 1.15,
				"cost_mode": 1
			}

		AiStrategy.MACRO:
			return {
				"economy_target": 2 + int(floor(float(total_units) / 10.0)),
				"support_target": 2,
				"defense_target": 1 + (1 if base_under_attack else 0),
				"frontline_weight": 1.0,
				"ranged_weight": 0.95,
				"heavy_weight": 0.95,
				"cost_mode": 0
			}

		AiStrategy.TECH:
			return {
				"economy_target": 2,
				"support_target": 3,
				"defense_target": 2 + (1 if base_under_attack else 0),
				"frontline_weight": 0.7,
				"ranged_weight": 1.2,
				"heavy_weight": 1.35,
				"cost_mode": 1
			}

		_:
			return {
				"economy_target": 2,
				"support_target": 2,
				"defense_target": 2 + (1 if base_under_attack else 0),
				"frontline_weight": 1.0,
				"ranged_weight": 1.0,
				"heavy_weight": 1.0,
				"cost_mode": 0
			}


func _get_structure_category_order_for_strategy(strategy: int) -> Array:
	match strategy:
		AiStrategy.RUSH:
			return ["trainers", "economy", "support", "defense"]
		AiStrategy.TURTLE:
			return ["economy", "defense", "trainers", "support"]
		AiStrategy.MACRO:
			return ["economy", "trainers", "support", "defense"]
		AiStrategy.TECH:
			return ["trainers", "support", "economy", "defense"]
		_:
			return ["trainers", "economy", "support", "defense"]


func _get_entries_for_category_name(category_name: String) -> Array:
	match category_name:
		"trainers":
			return _get_category_entries(trainer_structure_stats, trainer_structure_scenes)
		"economy":
			return _get_category_entries(economy_structure_stats, economy_structure_scenes)
		"support":
			return _get_category_entries(support_structure_stats, support_structure_scenes)
		"defense":
			return _get_category_entries(defense_structure_stats, defense_structure_scenes)

	return []


func _get_category_entries(stats_array: Array, scene_array: Array) -> Array:
	var results: Array = []

	for i in range(stats_array.size()):
		var stats: StructureStats = stats_array[i]
		if stats == null:
			continue

		var scene: PackedScene = default_structure_scene
		if i < scene_array.size() and scene_array[i] != null:
			scene = scene_array[i]

		if scene == null:
			continue

		results.append({
			"stats": stats,
			"scene": scene
		})

	return results


func _try_queue_unit_from_structure(runtime_team_id: int, producer: StructureRuntime, unit_stats: UnitStats) -> void:
	if producer == null:
		return
	if unit_stats == null:
		return
	if not _can_queue_on_producer(producer):
		return

	if not game_manager.can_afford(runtime_team_id, unit_stats.cost):
		return

	if not game_manager.spend_credits(runtime_team_id, unit_stats.cost):
		return

	structure_manager.queue_unit_production(producer.id, unit_stats)


func _can_queue_on_producer(producer: StructureRuntime) -> bool:
	if producer == null:
		return false
	if not producer.is_alive:
		return false
	if not producer.can_produce():
		return false
	if not producer.can_train_units():
		return false

	var queue_count: int = producer.production_queue.size()
	if producer.current_production != null:
		queue_count += 1

	return queue_count < max_queue_size


func _handle_base_defense_for_team(runtime_team_id: int, hq: StructureRuntime) -> bool:
	var intruders: Array = _get_enemy_units_near_position(runtime_team_id, hq.position, base_defense_radius)
	if intruders.is_empty():
		return false

	var responders: Array = _get_friendly_units_near_position(runtime_team_id, hq.position, defense_response_radius)

	for responder in responders:
		var unit: UnitRuntime = responder
		if unit == null or not unit.is_alive:
			continue

		var closest_intruder: UnitRuntime = _get_closest_enemy_unit_to_position(unit.position, intruders)
		if closest_intruder == null:
			continue

		unit_manager.issue_attack_unit_order(unit.id, closest_intruder.id)

	return true


func _is_base_under_attack(runtime_team_id: int, hq: StructureRuntime) -> bool:
	return not _get_enemy_units_near_position(runtime_team_id, hq.position, base_defense_radius).is_empty()


func _update_rally_for_team(runtime_team_id: int, hq: StructureRuntime, base_under_attack: bool, strategy: int) -> void:
	var nearest_enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if nearest_enemy_hq == null:
		return

	var dir_to_enemy: Vector2 = hq.position.direction_to(nearest_enemy_hq.position)
	if dir_to_enemy.length_squared() <= 0.0001:
		dir_to_enemy = Vector2.RIGHT

	var aggression_mult: float = 1.0
	match strategy:
		AiStrategy.RUSH:
			aggression_mult = 1.3
		AiStrategy.TURTLE:
			aggression_mult = 0.7
		AiStrategy.MACRO:
			aggression_mult = 0.9
		AiStrategy.TECH:
			aggression_mult = 1.0
		_:
			aggression_mult = 1.0

	var staging_point: Vector2 = hq.position + dir_to_enemy * staging_distance_from_hq * aggression_mult
	var target_rally: Vector2 = hq.position if base_under_attack else staging_point

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


func _try_launch_squad(runtime_team_id: int, hq: StructureRuntime, strategy: int) -> void:
	var enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if enemy_hq == null:
		return

	var staging_point: Vector2 = _get_staging_point_for_team(runtime_team_id, hq, strategy)
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
		if unit == null or not unit.is_alive:
			continue

		unit_manager.issue_attack_move_order(unit.id, world_target)


func _get_staging_point_for_team(runtime_team_id: int, hq: StructureRuntime, strategy: int) -> Vector2:
	var enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if enemy_hq == null:
		return hq.position

	var dir_to_enemy: Vector2 = hq.position.direction_to(enemy_hq.position)
	if dir_to_enemy.length_squared() <= 0.0001:
		dir_to_enemy = Vector2.RIGHT

	var mult: float = 1.0
	match strategy:
		AiStrategy.RUSH:
			mult = 1.3
		AiStrategy.TURTLE:
			mult = 0.8
		AiStrategy.MACRO:
			mult = 1.0
		AiStrategy.TECH:
			mult = 1.1
		_:
			mult = 1.0

	return hq.position + dir_to_enemy * staging_distance_from_hq * mult


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

	if not game_manager.can_afford(runtime_team_id, stats.cost):
		return false

	var placement_pos: Vector2 = _find_structure_placement_position(hq, stats)
	if placement_pos == Vector2.INF:
		return false

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
	for ring in range(build_ring_count):
		var radius: float = base_build_distance_from_hq + build_ring_step * float(ring)
		var candidates: Array = _get_candidate_positions_around_center(hq.position, radius)

		for pos in candidates:
			var p: Vector2 = pos
			if _can_place_structure_at(p, stats):
				return p

	return Vector2.INF


func _get_candidate_positions_around_center(center: Vector2, radius: float) -> Array:
	var results: Array = []

	for i in range(build_points_per_ring):
		var angle: float = TAU * (float(i) / float(build_points_per_ring))
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


func _get_trainable_unit_type_count(runtime_team_id: int) -> int:
	var types: Dictionary = {}

	for producer in _get_all_alive_producers_for_team(runtime_team_id):
		var s: StructureRuntime = producer
		if s == null:
			continue

		var unit_stats: UnitStats = s.get_trained_unit_stats()
		if unit_stats == null:
			continue

		types[unit_stats.resource_path] = true

	return max(types.size(), 1)


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
