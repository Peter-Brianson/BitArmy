class_name TeamManager
extends Node

@export var structure_manager: StructureSimulationManager

var team_count: int = 0

# Runtime member id -> alliance/team-color id.
var member_to_alliance: Dictionary = {}

# Runtime member id -> visual palette id.
var member_to_visual_team: Dictionary = {}

# team_id/member_id -> keyword bitmask.
var team_keywords: Dictionary = {}

# "a:b" -> bool.
var enemy_map: Dictionary = {}

# member_id -> float.
var team_income_bonus_by_team: Dictionary = {}

# member_id -> { unit_tag_bit: bonus_amount }.
var team_damage_bonus_by_team: Dictionary = {}
var team_health_bonus_by_team: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(_delta: float) -> void:
	_refresh_team_structure_bonuses()


func setup_free_for_all(p_team_count: int) -> void:
	var default_alliances: Dictionary = {}

	for i in range(max(p_team_count, 0)):
		default_alliances[i] = i

	setup_alliances(p_team_count, default_alliances)


func setup_alliances(p_member_count: int, p_member_to_alliance: Dictionary) -> void:
	team_count = max(p_member_count, 0)

	member_to_alliance.clear()
	member_to_visual_team.clear()
	team_keywords.clear()
	enemy_map.clear()
	team_income_bonus_by_team.clear()
	team_damage_bonus_by_team.clear()
	team_health_bonus_by_team.clear()

	for member_id in range(team_count):
		var alliance_id: int = int(p_member_to_alliance.get(member_id, member_id))

		member_to_alliance[member_id] = alliance_id
		member_to_visual_team[member_id] = alliance_id
		team_keywords[member_id] = 0

	for a in range(team_count):
		for b in range(team_count):
			var same_alliance: bool = get_alliance_id(a) == get_alliance_id(b)
			enemy_map[_pair_key(a, b)] = not same_alliance


func get_alliance_id(member_id: int) -> int:
	return int(member_to_alliance.get(member_id, member_id))


func get_visual_team_id(member_id: int) -> int:
	return int(member_to_visual_team.get(member_id, get_alliance_id(member_id)))


func are_allied(team_a: int, team_b: int) -> bool:
	return get_alliance_id(team_a) == get_alliance_id(team_b)


func is_enemy(team_a: int, team_b: int) -> bool:
	if team_a == team_b:
		return false

	var key: String = _pair_key(team_a, team_b)

	if enemy_map.has(key):
		return bool(enemy_map[key])

	return get_alliance_id(team_a) != get_alliance_id(team_b)


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

		# Important: bonuses stay member/economy-local.
		var member_id: int = s.owner_team_id

		if not team_income_bonus_by_team.has(member_id):
			team_income_bonus_by_team[member_id] = 0.0

		team_income_bonus_by_team[member_id] = float(team_income_bonus_by_team[member_id]) + s.get_income_bonus_per_second()

		var buff_mask: int = s.get_teamwide_buff_unit_tags()

		if buff_mask == 0:
			continue

		if not team_damage_bonus_by_team.has(member_id):
			team_damage_bonus_by_team[member_id] = {}

		if not team_health_bonus_by_team.has(member_id):
			team_health_bonus_by_team[member_id] = {}

		var damage_dict: Dictionary = team_damage_bonus_by_team[member_id]
		var health_dict: Dictionary = team_health_bonus_by_team[member_id]

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

		team_damage_bonus_by_team[member_id] = damage_dict
		team_health_bonus_by_team[member_id] = health_dict


func _pair_key(team_a: int, team_b: int) -> String:
	return "%d:%d" % [team_a, team_b]
