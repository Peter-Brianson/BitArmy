class_name StructureRuntime
extends RefCounted

enum StructureState {
	ACTIVE,
	DESTROYED
}

var id: int = -1
var stats: StructureStats
var owner_team_id: int = 0

var state: StructureState = StructureState.ACTIVE
var is_alive: bool = true

var position: Vector2 = Vector2.ZERO
var rally_point: Vector2 = Vector2.ZERO
var current_health: int = 1
var death_timer_left: float = 0.0

# Optional combat support for attacking structures later.
var target_unit_id: int = -1
var attack_cooldown_left: float = 0.0
var attack_windup_left: float = 0.0
var attack_has_landed: bool = false

# Optional effect layers.
var personal_keywords: int = 0
var local_aura_keywords: int = 0

# Production.
var production_queue: Array[UnitStats] = []
var current_production: UnitStats = null
var production_progress: float = 0.0

func setup(p_id: int, p_stats: StructureStats, p_team_id: int, p_position: Vector2) -> void:
	id = p_id
	stats = p_stats
	owner_team_id = p_team_id
	position = p_position
	rally_point = p_position

	current_health = stats.max_health
	state = StructureState.ACTIVE
	is_alive = true
	death_timer_left = 0.0

	target_unit_id = -1
	attack_cooldown_left = 0.0
	attack_windup_left = 0.0
	attack_has_landed = false

	personal_keywords = 0
	local_aura_keywords = 0

	production_queue.clear()
	current_production = null
	production_progress = 0.0

func get_effective_keywords(team_manager: TeamManager) -> int:
	return stats.keywords | personal_keywords | local_aura_keywords | team_manager.get_team_keywords(owner_team_id)

func has_keyword(flag: int, team_manager: TeamManager) -> bool:
	return (get_effective_keywords(team_manager) & flag) != 0

func get_radius() -> float:
	return stats.radius

func can_produce() -> bool:
	return stats.can_produce


func can_place_structures() -> bool:
	return stats.can_place_structures


func get_trained_unit_stats() -> UnitStats:
	return stats.trained_unit_stats


func get_income_bonus_per_second() -> float:
	return stats.income_bonus_per_second


func get_teamwide_buff_unit_tags() -> int:
	return stats.teamwide_buff_unit_tags


func get_teamwide_bonus_damage() -> int:
	return stats.teamwide_bonus_damage


func get_teamwide_bonus_health() -> int:
	return stats.teamwide_bonus_health


func can_attack() -> bool:
	return stats.can_attack

func can_train_units() -> bool:
	return stats.can_train_units

func can_target_units() -> bool:
	return stats.can_target_units()

func can_target_structures() -> bool:
	return stats.can_target_structures()

func get_attack_range() -> float:
	return stats.attack_range

func get_attack_cooldown() -> float:
	if stats.attack_speed <= 0.0:
		return 99999.0
	return 1.0 / stats.attack_speed

func apply_damage(amount: int) -> void:
	if not is_alive:
		return

	current_health -= amount
	#print("Structure ", id, " took ", amount, " damage. Health now ", current_health)

	if current_health <= 0:
		current_health = 0
		enter_destroyed_state()

func enter_destroyed_state() -> void:
	if not is_alive:
		return

	is_alive = false
	state = StructureState.DESTROYED
	target_unit_id = -1
	attack_cooldown_left = 0.0
	attack_windup_left = 0.0
	attack_has_landed = false

	current_production = null
	production_queue.clear()
	production_progress = 0.0

	death_timer_left = stats.death_time

func is_ready_for_removal() -> bool:
	return state == StructureState.DESTROYED and death_timer_left <= 0.0

func queue_unit(stats_to_build: UnitStats) -> void:
	if not can_produce():
		return
	if stats_to_build == null:
		return

	production_queue.append(stats_to_build)

func clear_queue() -> void:
	production_queue.clear()
	current_production = null
	production_progress = 0.0

func has_production_pending() -> bool:
	return current_production != null or not production_queue.is_empty()

func start_next_production_if_needed() -> void:
	if not can_produce():
		return
	if current_production != null:
		return
	if production_queue.is_empty():
		return

	current_production = production_queue.pop_front()
	production_progress = 0.0

func finish_current_production() -> UnitStats:
	var finished: UnitStats = current_production
	current_production = null
	production_progress = 0.0
	return finished


func get_attack_damage() -> int:
	return stats.attack_damage


func get_attack_windup() -> float:
	return stats.attack_windup
