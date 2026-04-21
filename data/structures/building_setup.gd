extends Node2D

var runtime_id: int = -1
var stats: StructureStats
var owner_team_id: int = -1

func apply_structure_runtime_setup(p_runtime_id: int, p_stats: StructureStats, p_team_id: int) -> void:
	runtime_id = p_runtime_id
	stats = p_stats
	owner_team_id = p_team_id

func apply_structure_runtime_state(_state: int, _health: int, _is_alive: bool) -> void:
	pass
