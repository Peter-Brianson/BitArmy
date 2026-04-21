class_name TeamManager
extends Node

@export var structure_manager: StructureSimulationManager

var team_count: int = 0

# team_id -> keyword bitmask
var team_keywords: Dictionary = {}

# "a:b" -> bool
var enemy_map: Dictionary = {}

# team_id -> float
var team_income_bonus_by_team: Dictionary = {}

# team_id -> { unit_tag_bit: bonus_amount }
var team_damage_bonus_by_team: Dictionary = {}
var team_health_bonus_by_team: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(_delta: float) -> void:
	_refresh_team_structure_bonuses()


func setup_free_for_all(p_team_count: int) -> void:
	team_count = max(p_team_count, 0)

	team_keywords.clear()
	enemy_map.clear()
	team_income_bonus_by_team.clear()
	team_damage_bonus_by_team.clear()
	team_health_bonus_by_team.clear()

	for a in range(team_count):
		team_keywords[a] = 0

		for b in range(team_count):
			enemy_map[_pair_key(a, b)] = a != b


func is_enemy(team_a: int, team_b: int) -> bool:
	if team_a == team_b:
		return false

	var key: String = _pair_key(team_a, team_b)
	if enemy_map.has(key):
		return bool(enemy_map[key])

	return team_a != team_b


func set_enemy(team_a: int, team_b: int, value: bool) -> void:
	if team_a == team_b:
		return

	enemy_map[_pair_key(team_a, team_b)] = value
	enemy_map[_pair_key(team_b, team_a)] = value


func get_team_keywords(team_id: int) -> int:
	return int(team_keywords.get(team_id, 0))


func set_team_keywords(team_id: int, keywords: int) -> void:
	team_keywords[team_id] = keywords


func add_team_keywords(team_id: int, keywords: int) -> void:
	var current: int = get_team_keywords(team_id)
	team_keywords[team_id] = current | keywords


func remove_team_keywords(team_id: int, keywords: int) -> void:
	var current: int = get_team_keywords(team_id)
	team_keywords[team_id] = current & ~keywords


func get_team_income_bonus(team_id: int) -> float:
	return float(team_income_bonus_by_team.get(team_id, 0.0))


func get_team_bonus_damage_for_unit(team_id: int, unit_type_tags: int) -> int:
	if not team_damage_bonus_by_team.has(team_id):
		return 0

	var damage_dict: Dictionary = team_damage_bonus_by_team[team_id]
	var total: int = 0

	for bit in damage_dict.keys():
		var tag_bit: int = int(bit)
		if (unit_type_tags & tag_bit) != 0:
			total += int(damage_dict[tag_bit])

	return total


func get_team_bonus_health_for_unit(team_id: int, unit_type_tags: int) -> int:
	if not team_health_bonus_by_team.has(team_id):
		return 0

	var health_dict: Dictionary = team_health_bonus_by_team[team_id]
	var total: int = 0

	for bit in health_dict.keys():
		var tag_bit: int = int(bit)
		if (unit_type_tags & tag_bit) != 0:
			total += int(health_dict[tag_bit])

	return total


func _refresh_team_structure_bonuses() -> void:
	team_income_bonus_by_team.clear()
	team_damage_bonus_by_team.clear()
	team_health_bonus_by_team.clear()

	if structure_manager == null:
		return

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue

		var team_id: int = s.owner_team_id

		if not team_income_bonus_by_team.has(team_id):
			team_income_bonus_by_team[team_id] = 0.0

		team_income_bonus_by_team[team_id] = float(team_income_bonus_by_team[team_id]) + s.get_income_bonus_per_second()

		var buff_mask: int = s.get_teamwide_buff_unit_tags()
		if buff_mask == 0:
			continue

		if not team_damage_bonus_by_team.has(team_id):
			team_damage_bonus_by_team[team_id] = {}
		if not team_health_bonus_by_team.has(team_id):
			team_health_bonus_by_team[team_id] = {}

		var damage_dict: Dictionary = team_damage_bonus_by_team[team_id]
		var health_dict: Dictionary = team_health_bonus_by_team[team_id]

		for bit in [
			UnitStats.TYPE_BASIC,
			UnitStats.TYPE_MYSTIC,
			UnitStats.TYPE_BEAST,
			UnitStats.TYPE_MACHINE,
			UnitStats.TYPE_ALIEN,
			UnitStats.TYPE_ELEMENTAL
		]:
			if (buff_mask & bit) == 0:
				continue

			damage_dict[bit] = int(damage_dict.get(bit, 0)) + s.get_teamwide_bonus_damage()
			health_dict[bit] = int(health_dict.get(bit, 0)) + s.get_teamwide_bonus_health()

		team_damage_bonus_by_team[team_id] = damage_dict
		team_health_bonus_by_team[team_id] = health_dict


func _pair_key(team_a: int, team_b: int) -> String:
	return "%d:%d" % [team_a, team_b]
