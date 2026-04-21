class_name AITeamManager
extends Node

@export var structure_manager: StructureSimulationManager
@export var unit_manager: UnitSimulationManager
@export var team_manager: TeamManager
@export var game_manager: GameManager

@export_group("Unit Options")
@export var soldier_unit_stats: UnitStats
@export var sniper_unit_stats: UnitStats
@export var heavy_unit_stats: UnitStats

@export_group("Trainer Structures")
@export var soldier_trainer_stats: StructureStats
@export var soldier_trainer_scene: PackedScene

@export var sniper_trainer_stats: StructureStats
@export var sniper_trainer_scene: PackedScene

@export var heavy_trainer_stats: StructureStats
@export var heavy_trainer_scene: PackedScene

@export_group("Production")
@export var max_queue_size: int = 4
@export var production_check_interval: float = 1.25
@export var soldier_threshold_for_advanced_trainers: int = 10

@export_group("Trainer Placement")
@export var trainer_check_interval: float = 2.0
@export var placement_padding: float = 8.0
@export var trainer_distance_from_hq: float = 110.0

@export_group("Defense")
@export var defense_check_interval: float = 0.50
@export var base_defense_radius: float = 220.0
@export var defense_response_radius: float = 360.0

@export_group("Squads")
@export var squad_launch_interval: float = 2.5
@export var squad_gather_radius: float = 180.0
@export var squad_soldier_count: int = 2
@export var squad_heavy_count: int = 1
@export var squad_sniper_count: int = 1
@export var staging_distance_from_hq: float = 100.0
@export var rally_distance_padding: float = 80.0

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
		state["trainer_timer"] = float(state["trainer_timer"]) - delta
		state["defense_timer"] = float(state["defense_timer"]) - delta
		state["squad_timer"] = float(state["squad_timer"]) - delta
		state["rally_timer"] = float(state["rally_timer"]) - delta

		var hq_id: int = int(state["hq_id"])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq == null or not hq.is_alive:
			continue

		if float(state["trainer_timer"]) <= 0.0:
			_handle_trainers_for_team(int(runtime_team_id), hq, state)
			state["trainer_timer"] = trainer_check_interval

		if float(state["production_timer"]) <= 0.0:
			_handle_production_for_team(int(runtime_team_id), hq, state)
			state["production_timer"] = production_check_interval

		var base_under_attack: bool = false

		if float(state["defense_timer"]) <= 0.0:
			base_under_attack = _handle_base_defense_for_team(int(runtime_team_id), hq, state)
			state["defense_timer"] = defense_check_interval
		else:
			base_under_attack = _is_base_under_attack(int(runtime_team_id), hq)

		if float(state["rally_timer"]) <= 0.0:
			_update_rally_for_team(int(runtime_team_id), hq, state, base_under_attack)
			state["rally_timer"] = 1.0

		if not base_under_attack and float(state["squad_timer"]) <= 0.0:
			_try_launch_squad(int(runtime_team_id), hq, state)
			state["squad_timer"] = squad_launch_interval

		_ai_teams[runtime_team_id] = state


func register_ai_team(runtime_team_id: int, hq_id: int) -> void:
	_ai_teams[runtime_team_id] = {
		"hq_id": hq_id,
		"soldier_trainer_id": -1,
		"sniper_trainer_id": -1,
		"heavy_trainer_id": -1,
		"production_timer": _rng.randf_range(0.1, production_check_interval),
		"trainer_timer": _rng.randf_range(0.1, trainer_check_interval),
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


func _handle_trainers_for_team(runtime_team_id: int, hq: StructureRuntime, state: Dictionary) -> void:
	var soldier_count: int = _count_alive_units_of_type(runtime_team_id, soldier_unit_stats)

	_ensure_trainer_exists(
		runtime_team_id,
		hq,
		state,
		"soldier_trainer_id",
		soldier_trainer_stats,
		soldier_trainer_scene,
		0.0
	)

	if soldier_count >= soldier_threshold_for_advanced_trainers:
		_ensure_trainer_exists(
			runtime_team_id,
			hq,
			state,
			"sniper_trainer_id",
			sniper_trainer_stats,
			sniper_trainer_scene,
			PI * 0.66
		)

		_ensure_trainer_exists(
			runtime_team_id,
			hq,
			state,
			"heavy_trainer_id",
			heavy_trainer_stats,
			heavy_trainer_scene,
			-PI * 0.66
		)


func _ensure_trainer_exists(
	runtime_team_id: int,
	hq: StructureRuntime,
	state: Dictionary,
	state_key: String,
	trainer_stats: StructureStats,
	trainer_scene: PackedScene,
	angle_offset: float
) -> void:
	var existing: StructureRuntime = _get_trainer_from_state_key(state, state_key)
	if existing != null and existing.is_alive:
		return

	state[state_key] = -1

	if trainer_stats == null or trainer_scene == null:
		return
	if not hq.can_place_structures():
		return

	if game_manager != null:
		if not game_manager.can_afford(runtime_team_id, trainer_stats.cost):
			return

	var placement_pos: Vector2 = _find_trainer_placement_position(hq, trainer_stats, angle_offset)
	if placement_pos == Vector2.INF:
		return

	if game_manager != null:
		if not game_manager.spend_credits(runtime_team_id, trainer_stats.cost):
			return

	var new_trainer_id: int = structure_manager.spawn_structure(
		trainer_stats,
		runtime_team_id,
		placement_pos,
		trainer_scene
	)

	state[state_key] = new_trainer_id


func _handle_production_for_team(runtime_team_id: int, _hq: StructureRuntime, state: Dictionary) -> void:
	var soldier_trainer: StructureRuntime = _get_trainer_from_state_key(state, "soldier_trainer_id")
	var sniper_trainer: StructureRuntime = _get_trainer_from_state_key(state, "sniper_trainer_id")
	var heavy_trainer: StructureRuntime = _get_trainer_from_state_key(state, "heavy_trainer_id")

	var soldier_count: int = _count_alive_units_of_type(runtime_team_id, soldier_unit_stats)
	var sniper_count: int = _count_alive_units_of_type(runtime_team_id, sniper_unit_stats)
	var heavy_count: int = _count_alive_units_of_type(runtime_team_id, heavy_unit_stats)

	var desired_soldiers: int = max(soldier_threshold_for_advanced_trainers, (sniper_count + heavy_count) * 2 + 2)
	var desired_snipers: int = max(1, int(floor(float(soldier_count) / 4.0)))
	var desired_heavies: int = max(1, int(floor(float(soldier_count) / 4.0)))

	if soldier_trainer != null and soldier_trainer.is_alive and soldier_count < desired_soldiers:
		_try_queue_unit_from_structure(runtime_team_id, soldier_trainer, soldier_unit_stats)

	if soldier_count >= soldier_threshold_for_advanced_trainers:
		if sniper_trainer != null and sniper_trainer.is_alive and sniper_count < desired_snipers:
			_try_queue_unit_from_structure(runtime_team_id, sniper_trainer, sniper_unit_stats)

		if heavy_trainer != null and heavy_trainer.is_alive and heavy_count < desired_heavies:
			_try_queue_unit_from_structure(runtime_team_id, heavy_trainer, heavy_unit_stats)


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


func _handle_base_defense_for_team(runtime_team_id: int, hq: StructureRuntime, _state: Dictionary) -> bool:
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


func _update_rally_for_team(runtime_team_id: int, hq: StructureRuntime, state: Dictionary, base_under_attack: bool) -> void:
	var nearest_enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if nearest_enemy_hq == null:
		return

	var dir_to_enemy: Vector2 = hq.position.direction_to(nearest_enemy_hq.position)
	if dir_to_enemy.length_squared() <= 0.0001:
		dir_to_enemy = Vector2.RIGHT

	var staging_point: Vector2 = hq.position + dir_to_enemy * staging_distance_from_hq
	var defense_point: Vector2 = hq.position

	var target_rally: Vector2 = defense_point if base_under_attack else staging_point

	var soldier_trainer: StructureRuntime = _get_trainer_from_state_key(state, "soldier_trainer_id")
	if soldier_trainer != null and soldier_trainer.is_alive:
		soldier_trainer.rally_point = target_rally

	var sniper_trainer: StructureRuntime = _get_trainer_from_state_key(state, "sniper_trainer_id")
	if sniper_trainer != null and sniper_trainer.is_alive:
		sniper_trainer.rally_point = target_rally

	var heavy_trainer: StructureRuntime = _get_trainer_from_state_key(state, "heavy_trainer_id")
	if heavy_trainer != null and heavy_trainer.is_alive:
		heavy_trainer.rally_point = target_rally

	hq.rally_point = target_rally


func _try_launch_squad(runtime_team_id: int, hq: StructureRuntime, _state: Dictionary) -> void:
	var enemy_hq: StructureRuntime = _find_nearest_enemy_hq(runtime_team_id, hq.position)
	if enemy_hq == null:
		return

	var staging_point: Vector2 = _get_staging_point_for_team(runtime_team_id, hq)

	var soldiers: Array = _get_available_units_of_type_near_position(
		runtime_team_id,
		soldier_unit_stats,
		staging_point,
		squad_gather_radius
	)

	var heavies: Array = _get_available_units_of_type_near_position(
		runtime_team_id,
		heavy_unit_stats,
		staging_point,
		squad_gather_radius
	)

	var snipers: Array = _get_available_units_of_type_near_position(
		runtime_team_id,
		sniper_unit_stats,
		staging_point,
		squad_gather_radius
	)

	if soldiers.size() >= squad_soldier_count and heavies.size() >= squad_heavy_count:
		var squad: Array = []
		for i in range(squad_soldier_count):
			squad.append(soldiers[i])
		for i in range(squad_heavy_count):
			squad.append(heavies[i])

		_issue_squad_attack_move(squad, enemy_hq.position)
		return

	if soldiers.size() >= squad_soldier_count and snipers.size() >= squad_sniper_count:
		var squad: Array = []
		for i in range(squad_soldier_count):
			squad.append(soldiers[i])
		for i in range(squad_sniper_count):
			squad.append(snipers[i])

		_issue_squad_attack_move(squad, enemy_hq.position)
		return

func _issue_squad_attack_move(squad: Array, world_target: Vector2) -> void:
	for member in squad:
		var unit: UnitRuntime = member
		if unit == null:
			continue
		if not unit.is_alive:
			continue

		unit_manager.issue_attack_move_order(unit.id, world_target)

func _issue_squad_attack_structure(squad: Array, target_structure_id: int) -> void:
	for member in squad:
		var unit: UnitRuntime = member
		if unit == null:
			continue
		if not unit.is_alive:
			continue

		unit_manager.issue_attack_structure_order(unit.id, target_structure_id)


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


func _get_trainer_from_state_key(state: Dictionary, state_key: String) -> StructureRuntime:
	if not state.has(state_key):
		return null

	var trainer_id: int = int(state[state_key])
	if trainer_id == -1:
		return null

	var trainer: StructureRuntime = structure_manager.get_structure(trainer_id)
	if trainer == null:
		return null
	if not trainer.is_alive:
		return null

	return trainer


func _find_trainer_placement_position(hq: StructureRuntime, stats: StructureStats, angle_offset: float) -> Vector2:
	var candidate_positions: Array[Vector2] = _get_candidate_trainer_positions(hq.position, angle_offset)

	for pos in candidate_positions:
		var p: Vector2 = pos
		if _can_place_structure_at(p, stats):
			return p

	return Vector2.INF


func _get_candidate_trainer_positions(center: Vector2, angle_offset: float) -> Array[Vector2]:
	var d: float = trainer_distance_from_hq
	var dirs: Array[Vector2] = [
		Vector2.RIGHT.rotated(angle_offset),
		Vector2.LEFT.rotated(angle_offset),
		Vector2.UP.rotated(angle_offset),
		Vector2.DOWN.rotated(angle_offset),
		Vector2(1, 1).normalized().rotated(angle_offset),
		Vector2(-1, 1).normalized().rotated(angle_offset),
		Vector2(1, -1).normalized().rotated(angle_offset),
		Vector2(-1, -1).normalized().rotated(angle_offset)
	]

	var results: Array[Vector2] = []
	for dir in dirs:
		results.append(center + dir * d)

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


func _get_available_units_of_type_near_position(runtime_team_id: int, unit_stats: UnitStats, center: Vector2, radius: float) -> Array:
	var results: Array = []

	if unit_stats == null:
		return results

	var nearby_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(center, radius)

	for unit_id in nearby_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if not unit.is_alive:
			continue
		if unit.owner_team_id != runtime_team_id:
			continue
		if unit.stats != unit_stats:
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
