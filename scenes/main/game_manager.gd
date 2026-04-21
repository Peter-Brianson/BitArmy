class_name GameManager
extends Node

@export var team_manager: TeamManager
@export var debug_income: bool = false

var starting_credits: int = 0
var base_credit_income_per_second: float = 0.0

# team_id -> float credits
var credits_by_team: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	AudioHub.play_battle_music()


func _process(delta: float) -> void:
	if credits_by_team.is_empty():
		return

	for team_id in credits_by_team.keys():
		var income_delta: float = get_team_income_per_second(int(team_id)) * delta
		credits_by_team[team_id] = float(credits_by_team[team_id]) + income_delta

	if debug_income:
		for team_id in credits_by_team.keys():
			print(
				"GameManager income tick | team=",
				team_id,
				" credits=",
				credits_by_team[team_id],
				" income/sec=",
				get_team_income_per_second(int(team_id))
			)


func configure_from_game_session(active_runtime_team_ids: Array[int]) -> void:
	starting_credits = GameSession.starting_credits
	base_credit_income_per_second = GameSession.base_credit_income_per_second

	credits_by_team.clear()

	for team_id in active_runtime_team_ids:
		credits_by_team[team_id] = float(starting_credits)

	print(
		"GameManager configured | starting_credits=",
		starting_credits,
		" income/sec=",
		base_credit_income_per_second,
		" active_teams=",
		active_runtime_team_ids
	)


func get_team_income_per_second(team_id: int) -> float:
	var bonus: float = 0.0

	if team_manager != null:
		bonus = team_manager.get_team_income_bonus(team_id)

	return base_credit_income_per_second + bonus


func get_team_credits(team_id: int) -> float:
	if credits_by_team.has(team_id):
		return float(credits_by_team[team_id])
	return 0.0


func can_afford(team_id: int, amount: int) -> bool:
	return get_team_credits(team_id) >= amount


func spend_credits(team_id: int, amount: int) -> bool:
	if amount <= 0:
		return true

	if not can_afford(team_id, amount):
		return false

	credits_by_team[team_id] = float(credits_by_team[team_id]) - amount
	return true


func add_credits(team_id: int, amount: float) -> void:
	if not credits_by_team.has(team_id):
		return

	credits_by_team[team_id] = float(credits_by_team[team_id]) + amount
