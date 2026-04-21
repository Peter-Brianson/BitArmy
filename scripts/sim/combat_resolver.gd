class_name CombatResolver
extends Node

@export var team_manager: TeamManager
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var default_attack_windup: float = 0.10


func process_unit_attack(attacker: UnitRuntime, delta: float) -> void:
	attacker.previous_position = attacker.position
	attacker.velocity = Vector2.ZERO

	if not attacker.is_alive:
		return

	if not validate_or_refresh_target(attacker):
		match attacker.order_mode:
			UnitRuntime.OrderMode.MOVE:
				if attacker.has_move_target:
					attacker.state = UnitRuntime.UnitState.WALK
				else:
					attacker.state = UnitRuntime.UnitState.IDLE

			UnitRuntime.OrderMode.ATTACK_UNIT, UnitRuntime.OrderMode.ATTACK_STRUCTURE:
				attacker.clear_all_orders()

			UnitRuntime.OrderMode.ATTACK_MOVE:
				if attacker.has_attack_move_destination:
					attacker.move_target = attacker.attack_move_destination
					attacker.has_move_target = true
					attacker.state = UnitRuntime.UnitState.WALK
				else:
					attacker.state = UnitRuntime.UnitState.IDLE

			UnitRuntime.OrderMode.NONE:
				if attacker.has_move_target:
					attacker.state = UnitRuntime.UnitState.WALK
				else:
					attacker.state = UnitRuntime.UnitState.IDLE
		return

	if not is_current_target_in_attack_range(attacker):
		attacker.state = UnitRuntime.UnitState.WALK
		attacker.has_move_target = true
		attacker.move_target = get_current_target_approach_position(attacker)
		return

	attacker.state = UnitRuntime.UnitState.ATTACK
	attacker.velocity = Vector2.ZERO

	if attacker.attack_windup_left <= 0.0 and attacker.attack_cooldown_left <= 0.0:
		attacker.begin_attack_cycle(default_attack_windup)

	if attacker.attack_windup_left > 0.0:
		attacker.attack_windup_left -= delta

	if attacker.attack_windup_left <= 0.0 and not attacker.attack_has_landed:
		_land_attack(attacker)
		attacker.attack_has_landed = true

	attacker.attack_cooldown_left = max(attacker.attack_cooldown_left - delta, 0.0)


func try_find_target_for_unit(attacker: UnitRuntime) -> bool:
	if attacker == null or not attacker.is_alive:
		return false
	if unit_manager == null:
		return false

	var best_unit_id: int = -1
	var best_structure_id: int = -1
	var best_distance_sq: float = INF

	var search_radius: float = attacker.stats.aggro_range + attacker.get_radius()

	if attacker.can_target_units():
		var nearby_unit_ids: Array[int] = unit_manager.spatial_hash.query_unit_ids_in_radius(attacker.position, search_radius)

		for target_id: int in nearby_unit_ids:
			if target_id == attacker.id:
				continue

			var target: UnitRuntime = unit_manager.get_unit(target_id)
			if not _is_valid_unit_target(attacker, target):
				continue

			var max_distance: float = search_radius + target.get_radius()
			var dist_sq: float = attacker.position.distance_squared_to(target.position)

			if dist_sq <= max_distance * max_distance and dist_sq < best_distance_sq:
				best_distance_sq = dist_sq
				best_unit_id = target.id
				best_structure_id = -1

	if attacker.can_target_structures() and structure_manager != null:
		var nearby_structure_ids: Array[int] = unit_manager.spatial_hash.query_structure_ids_in_radius(attacker.position, search_radius)

		for structure_id: int in nearby_structure_ids:
			var target: StructureRuntime = structure_manager.get_structure(structure_id)
			if not _is_valid_structure_target(attacker, target):
				continue

			var dist_sq: float = attacker.position.distance_squared_to(target.position)
			if dist_sq < best_distance_sq:
				best_distance_sq = dist_sq
				best_unit_id = -1
				best_structure_id = target.id

	attacker.target_unit_id = best_unit_id
	attacker.target_structure_id = best_structure_id

	return attacker.has_valid_target()


func validate_or_refresh_target(attacker: UnitRuntime) -> bool:
	if _validate_current_target(attacker):
		return true

	attacker.clear_target()
	return try_find_target_for_unit(attacker)


func is_current_target_in_attack_range(attacker: UnitRuntime) -> bool:
	if attacker.target_unit_id != -1:
		var target: UnitRuntime = unit_manager.get_unit(attacker.target_unit_id)
		if target == null:
			return false

		return _is_in_range(
			attacker.position,
			attacker.get_radius(),
			attacker.get_attack_range(),
			target.position,
			target.get_radius()
		)

	if attacker.target_structure_id != -1 and structure_manager != null:
		var target: StructureRuntime = structure_manager.get_structure(attacker.target_structure_id)
		if target == null:
			return false

		return _is_structure_in_attack_range(attacker, target)

	return false


func get_current_target_position(attacker: UnitRuntime) -> Vector2:
	if attacker.target_unit_id != -1:
		var unit_target: UnitRuntime = unit_manager.get_unit(attacker.target_unit_id)
		if unit_target != null:
			return unit_target.position

	if attacker.target_structure_id != -1 and structure_manager != null:
		var structure_target: StructureRuntime = structure_manager.get_structure(attacker.target_structure_id)
		if structure_target != null:
			return structure_target.position

	return attacker.position


func get_current_target_approach_position(attacker: UnitRuntime) -> Vector2:
	if attacker.target_unit_id != -1:
		var unit_target: UnitRuntime = unit_manager.get_unit(attacker.target_unit_id)
		if unit_target != null:
			return _get_circular_approach_position(
				attacker.position,
				attacker.get_radius(),
				attacker.get_attack_range(),
				unit_target.position,
				unit_target.get_radius()
			)

	if attacker.target_structure_id != -1 and structure_manager != null:
		var structure_target: StructureRuntime = structure_manager.get_structure(attacker.target_structure_id)
		if structure_target != null:
			return _get_structure_approach_position(attacker, structure_target)

	return attacker.position


func _validate_current_target(attacker: UnitRuntime) -> bool:
	if attacker.target_unit_id != -1:
		var unit_target: UnitRuntime = unit_manager.get_unit(attacker.target_unit_id)
		return _is_valid_unit_target(attacker, unit_target)

	if attacker.target_structure_id != -1 and structure_manager != null:
		var structure_target: StructureRuntime = structure_manager.get_structure(attacker.target_structure_id)
		return _is_valid_structure_target(attacker, structure_target)

	return false


func _is_valid_unit_target(attacker: UnitRuntime, target: UnitRuntime) -> bool:
	if target == null:
		return false
	if not target.is_alive:
		return false
	if attacker.id == target.id:
		return false
	if not attacker.can_target_units():
		return false
	if not _is_enemy(attacker.owner_team_id, target.owner_team_id):
		return false

	if target.has_keyword(UnitStats.KW_FLYING, team_manager) and not attacker.has_keyword(UnitStats.KW_ANTI_AIR, team_manager):
		return false

	if not _can_damage_target(attacker, target):
		return false

	return true


func _is_valid_structure_target(attacker: UnitRuntime, target: StructureRuntime) -> bool:
	if target == null:
		return false
	if not target.is_alive:
		return false
	if not attacker.can_target_structures():
		return false
	if not _is_enemy(attacker.owner_team_id, target.owner_team_id):
		return false

	if not _can_damage_target(attacker, target):
		return false

	return true


func _can_damage_target(attacker: UnitRuntime, target) -> bool:
	match attacker.stats.damage_type:
		UnitStats.DamageType.PHYSICAL:
			return not target.has_keyword(UnitStats.KW_PHYSICAL_IMMUNITY, team_manager)
		UnitStats.DamageType.MAGICAL:
			return not target.has_keyword(UnitStats.KW_MAGICAL_IMMUNITY, team_manager)
		UnitStats.DamageType.SIEGE:
			return true
		UnitStats.DamageType.TRUE:
			return true

	return true


func _land_attack(attacker: UnitRuntime) -> void:
	if attacker.target_unit_id != -1:
		var unit_target: UnitRuntime = unit_manager.get_unit(attacker.target_unit_id)
		if not _is_valid_unit_target(attacker, unit_target):
			return
		if not _is_in_range(
			attacker.position,
			attacker.get_radius(),
			attacker.get_attack_range(),
			unit_target.position,
			unit_target.get_radius()
		):
			return

		unit_manager.notify_attack_flash(attacker.id)

		var unit_damage: int = _get_final_damage(attacker, unit_target)
		unit_target.apply_damage(unit_damage)

		unit_manager.notify_hit_flash(unit_target.id)
		AudioHub.play_unit_shoot(attacker.position, get_tree().current_scene)
		return

	if attacker.target_structure_id != -1 and structure_manager != null:
		var structure_target: StructureRuntime = structure_manager.get_structure(attacker.target_structure_id)
		if not _is_valid_structure_target(attacker, structure_target):
			return
		if not _is_structure_in_attack_range(attacker, structure_target):
			return

		unit_manager.notify_attack_flash(attacker.id)
		AudioHub.play_unit_shoot(attacker.position, get_tree().current_scene)

		var structure_damage: int = _get_final_damage(attacker, structure_target)
		structure_target.apply_damage(structure_damage)

		structure_manager.notify_hit_flash(structure_target.id)


func _get_final_damage(attacker: UnitRuntime, target) -> int:
	var amount: int = attacker.get_effective_damage(team_manager)

	if target.has_keyword(UnitStats.KW_ARMORED, team_manager) and attacker.stats.damage_type == UnitStats.DamageType.PHYSICAL:
		amount = max(amount - 1, 1)

	return amount


func _is_in_range(
	attacker_position: Vector2,
	attacker_radius: float,
	attack_range: float,
	target_position: Vector2,
	target_radius: float
) -> bool:
	var total_range: float = attacker_radius + attack_range + target_radius
	return attacker_position.distance_squared_to(target_position) <= total_range * total_range


func _is_structure_in_attack_range(attacker: UnitRuntime, structure_target: StructureRuntime) -> bool:
	var padded_rect: Rect2 = _get_structure_padded_rect(attacker, structure_target)
	return padded_rect.has_point(attacker.position)


func _get_structure_padded_rect(attacker: UnitRuntime, structure_target: StructureRuntime) -> Rect2:
	var half_size: Vector2 = structure_target.stats.footprint_size * 0.5
	var padding: float = attacker.get_radius() + max(attacker.get_attack_range() - 2.0, 0.0)
	var padded_half_size: Vector2 = half_size + Vector2(padding, padding)

	return Rect2(
		structure_target.position - padded_half_size,
		padded_half_size * 2.0
	)


func _get_circular_approach_position(
	attacker_position: Vector2,
	attacker_radius: float,
	attack_range: float,
	target_position: Vector2,
	target_radius: float
) -> Vector2:
	var dir: Vector2 = attacker_position.direction_to(target_position)

	if dir.length_squared() <= 0.0001:
		dir = Vector2.RIGHT

	var desired_center_distance: float = target_radius + attacker_radius + max(attack_range - 2.0, 0.0)
	return target_position - dir * desired_center_distance


func _get_structure_approach_position(attacker: UnitRuntime, structure_target: StructureRuntime) -> Vector2:
	var padded_rect: Rect2 = _get_structure_padded_rect(attacker, structure_target)

	if padded_rect.has_point(attacker.position):
		return attacker.position

	var clamped_x: float = clamp(attacker.position.x, padded_rect.position.x, padded_rect.position.x + padded_rect.size.x)
	var clamped_y: float = clamp(attacker.position.y, padded_rect.position.y, padded_rect.position.y + padded_rect.size.y)

	return Vector2(clamped_x, clamped_y)


func _is_enemy(source_team_id: int, target_team_id: int) -> bool:
	if team_manager == null:
		return source_team_id != target_team_id

	return team_manager.is_enemy(source_team_id, target_team_id)
