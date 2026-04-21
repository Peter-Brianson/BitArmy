class_name UnitRuntime
extends RefCounted

enum UnitState {
	IDLE,
	WALK,
	ATTACK,
	DEAD
}

enum OrderMode {
	NONE,
	MOVE,
	ATTACK_MOVE,
	ATTACK_UNIT,
	ATTACK_STRUCTURE
}

var id: int = -1
var stats: UnitStats
var owner_team_id: int = 0

var state: UnitState = UnitState.IDLE
var order_mode: OrderMode = OrderMode.NONE
var is_alive: bool = true

var position: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing_dir: Vector2 = Vector2.RIGHT

var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false

var current_health: int = 1

var cached_effective_max_health: int = 1

var target_unit_id: int = -1
var target_structure_id: int = -1

var attack_cooldown_left: float = 0.0
var attack_windup_left: float = 0.0
var attack_has_landed: bool = false
var death_timer_left: float = 0.0

var personal_keywords: int = 0
var local_aura_keywords: int = 0

var retarget_timer_left: float = 0.0

var attack_move_destination: Vector2 = Vector2.ZERO
var has_attack_move_destination: bool = false

func setup(p_id: int, p_stats: UnitStats, p_team_id: int, p_position: Vector2) -> void:
	id = p_id
	stats = p_stats
	owner_team_id = p_team_id

	position = p_position
	previous_position = p_position
	move_target = p_position
	facing_dir = Vector2.RIGHT

	current_health = stats.max_health
	cached_effective_max_health = stats.max_health
	state = UnitState.IDLE
	order_mode = OrderMode.NONE
	is_alive = true

	velocity = Vector2.ZERO
	has_move_target = false

	target_unit_id = -1
	target_structure_id = -1

	attack_cooldown_left = 0.0
	attack_windup_left = 0.0
	attack_has_landed = false
	death_timer_left = 0.0

	personal_keywords = 0
	local_aura_keywords = 0
	retarget_timer_left = 0.0


func reset_for_reuse(p_id: int, p_stats: UnitStats, p_team_id: int, p_position: Vector2) -> void:
	setup(p_id, p_stats, p_team_id, p_position)


func get_effective_keywords(team_manager: TeamManager) -> int:
	return stats.keywords | personal_keywords | local_aura_keywords | team_manager.get_team_keywords(owner_team_id)


func has_keyword(flag: int, team_manager: TeamManager) -> bool:
	return (get_effective_keywords(team_manager) & flag) != 0


func get_radius() -> float:
	return stats.radius


func get_attack_range() -> float:
	return stats.attack_range


func get_attack_cooldown() -> float:
	return stats.get_attack_cooldown()


func can_target_units() -> bool:
	return stats.can_target_units()


func can_target_structures() -> bool:
	return stats.can_target_structures()

func get_unit_type_tags() -> int:
	return stats.unit_type_tags


func get_effective_damage(team_manager: TeamManager) -> int:
	if team_manager == null:
		return stats.damage

	return stats.damage + team_manager.get_team_bonus_damage_for_unit(owner_team_id, stats.unit_type_tags)


func get_effective_max_health(team_manager: TeamManager) -> int:
	if team_manager == null:
		return stats.max_health

	return stats.max_health + team_manager.get_team_bonus_health_for_unit(owner_team_id, stats.unit_type_tags)


func set_move_order(world_target: Vector2) -> void:
	move_target = world_target
	has_move_target = true
	order_mode = OrderMode.MOVE

	target_unit_id = -1
	target_structure_id = -1

	if state != UnitState.DEAD:
		state = UnitState.WALK


func set_attack_unit_order(p_target_unit_id: int) -> void:
	target_unit_id = p_target_unit_id
	target_structure_id = -1
	order_mode = OrderMode.ATTACK_UNIT

	move_target = position
	has_move_target = false
	velocity = Vector2.ZERO

	if state != UnitState.DEAD:
		state = UnitState.WALK


func set_attack_structure_order(p_target_structure_id: int) -> void:
	target_unit_id = -1
	target_structure_id = p_target_structure_id
	order_mode = OrderMode.ATTACK_STRUCTURE

	move_target = position
	has_move_target = false
	velocity = Vector2.ZERO

	if state != UnitState.DEAD:
		state = UnitState.WALK


func clear_move_order() -> void:
	has_move_target = false
	velocity = Vector2.ZERO

	if order_mode == OrderMode.MOVE:
		order_mode = OrderMode.NONE

	if state != UnitState.DEAD and not has_valid_target():
		state = UnitState.IDLE


func has_valid_target() -> bool:
	return target_unit_id != -1 or target_structure_id != -1


func clear_target() -> void:
	target_unit_id = -1
	target_structure_id = -1

	if order_mode == OrderMode.ATTACK_UNIT or order_mode == OrderMode.ATTACK_STRUCTURE:
		order_mode = OrderMode.NONE

	if state != UnitState.DEAD and not has_move_target:
		state = UnitState.IDLE


func clear_all_orders() -> void:
	target_unit_id = -1
	target_structure_id = -1
	has_move_target = false
	velocity = Vector2.ZERO
	order_mode = OrderMode.NONE

	if state != UnitState.DEAD:
		state = UnitState.IDLE

	has_attack_move_destination = false
	attack_move_destination = position

func begin_attack_cycle(windup_time: float) -> void:
	state = UnitState.ATTACK
	velocity = Vector2.ZERO
	attack_windup_left = windup_time
	attack_cooldown_left = get_attack_cooldown()
	attack_has_landed = false


func apply_damage(amount: int) -> void:
	if not is_alive:
		return

	current_health -= amount
	#print("Unit ", id, " took ", amount, " damage. Health now ", current_health)

	if current_health <= 0:
		current_health = 0
		enter_death_state()


func enter_death_state() -> void:
	if not is_alive:
		return

	is_alive = false
	state = UnitState.DEAD
	velocity = Vector2.ZERO
	has_move_target = false
	target_unit_id = -1
	target_structure_id = -1
	order_mode = OrderMode.NONE

	attack_cooldown_left = 0.0
	attack_windup_left = 0.0
	attack_has_landed = false

	death_timer_left = stats.death_time


func is_ready_for_removal() -> bool:
	return state == UnitState.DEAD and death_timer_left <= 0.0
