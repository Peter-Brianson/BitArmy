class_name MatchController
extends Node

@export_group("Managers")
@export var team_manager: TeamManager
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var selection_controller: SelectionController
@export var camera_pan_controller: CameraPanController
@export var ai_team_manager: AITeamManager
@export var game_manager: GameManager

@export_group("Match Content")
@export var hq_stats: StructureStats
@export var hq_scene: PackedScene
@export var starter_unit_stats: UnitStats
@export var queue_starter_unit_on_spawn: bool = false
@export var queue_starter_unit_count: int = 0

@export_group("Spawn Setup")
@export var team_spawn_markers: Array[NodePath] = []

@export_group("UI / Flow")
@export var match_end_controller: MatchEndController
@export var map_host: Node2D

@export_group("Map Reveal")
@export var map_reveal_update_interval: float = 0.25
@export var reveal_friendly_units: bool = true
@export var reveal_friendly_structures: bool = true
@export var max_unit_reveal_points: int = 600

var runtime_team_to_control_type: Dictionary = {}
var runtime_team_to_hq_id: Dictionary = {}
var session_team_to_runtime_team: Dictionary = {}
var local_player_runtime_team_id: int = -1
var local_player_hq_id: int = -1
var runtime_team_to_name: Dictionary = {}
var match_is_over: bool = false
var current_map_instance: Node = null

var runtime_team_to_alliance_team: Dictionary = {}
var alliance_team_to_runtime_teams: Dictionary = {}

var _map_reveal_timer: float = 0.0

const TEAM_DISPLAY_NAMES := [
	"Blue Team",
	"Red Team",
	"Green Team",
	"Yellow Team",
	"Purple Team",
	"Orange Team",
	"Cyan Team",
	"Pink Team",
	"White Team",
	"Gray Team"
]


func _ready() -> void:
	_load_selected_map()
	_build_match_from_game_session()


func _process(delta: float) -> void:
	if match_is_over:
		return

	_map_reveal_timer -= delta

	if _map_reveal_timer <= 0.0:
		_map_reveal_timer = map_reveal_update_interval
		_update_map_reveal_points()

	_check_match_end()


func _load_selected_map() -> void:
	if map_host == null:
		push_error("MatchController: map_host is not assigned.")
		return

	if current_map_instance != null and is_instance_valid(current_map_instance):
		current_map_instance.queue_free()
		current_map_instance = null

	if GameSession.selected_map_path == "":
		print("MatchController: no map selected.")
		return

	var map_scene: PackedScene = load(GameSession.selected_map_path) as PackedScene

	if map_scene == null:
		push_error("MatchController: failed to load selected map: %s" % GameSession.selected_map_path)
		return

	current_map_instance = map_scene.instantiate()
	map_host.add_child(current_map_instance)

	if current_map_instance.has_method("generate_map"):
		current_map_instance.call("generate_map")

	print("Loaded map: ", GameSession.selected_map_name, " | ", GameSession.selected_map_path)


func get_alive_runtime_team_count() -> int:
	var count: int = 0

	for runtime_team_id in runtime_team_to_hq_id.keys():
		var hq_id: int = int(runtime_team_to_hq_id[runtime_team_id])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq != null and hq.is_alive:
			count += 1

	return count


func center_camera_on_local_hq() -> void:
	_center_camera_on_local_hq()
	_update_map_reveal_points()
	_refresh_map_after_camera_jump()


func get_total_runtime_team_count() -> int:
	return runtime_team_to_hq_id.size()


func _get_runtime_team_display_name(runtime_team_id: int) -> String:
	if runtime_team_id >= 0 and runtime_team_id < TEAM_DISPLAY_NAMES.size():
		return TEAM_DISPLAY_NAMES[runtime_team_id]

	return "Team %d" % (runtime_team_id + 1)


func _build_match_from_game_session() -> void:
	runtime_team_to_name.clear()
	runtime_team_to_alliance_team.clear()
	alliance_team_to_runtime_teams.clear()
	match_is_over = false
	_map_reveal_timer = 0.0

	if match_end_controller != null:
		match_end_controller.reset_menu()

	if team_manager == null:
		push_error("MatchController: team_manager is not assigned.")
		return

	if structure_manager == null:
		push_error("MatchController: structure_manager is not assigned.")
		return

	if hq_stats == null:
		push_error("MatchController: hq_stats is not assigned.")
		return

	if hq_scene == null:
		push_error("MatchController: hq_scene is not assigned.")
		return

	var active_members: Array[Dictionary] = GameSession.get_active_members()
	var active_runtime_team_ids: Array[int] = []
	var member_to_alliance: Dictionary = {}
	var player_base_positions_to_reveal: Array[Vector2] = []

	if active_members.is_empty():
		push_error("MatchController: GameSession returned no active members.")
		return

	runtime_team_to_control_type.clear()
	runtime_team_to_hq_id.clear()
	session_team_to_runtime_team.clear()

	local_player_runtime_team_id = -1
	local_player_hq_id = -1

	if ai_team_manager != null:
		ai_team_manager.clear_all_ai_teams()

	for member_data in active_members:
		var member_id: int = int(member_data.get("member_id", 0))
		var alliance_team_id: int = int(member_data.get("team_id", member_id))
		member_to_alliance[member_id] = alliance_team_id

	team_manager.setup_alliances(GameSession.team_count, member_to_alliance)

	var fallback_spawn_index: int = 0

	for member_data in active_members:
		var runtime_member_id: int = int(member_data.get("member_id", 0))
		var alliance_team_id: int = int(member_data.get("team_id", runtime_member_id))
		var control_type: int = int(member_data.get("control_type", GameSession.ControlType.CLOSED))
		var spawn_position: Vector2 = _get_spawn_position(runtime_member_id, fallback_spawn_index)

		fallback_spawn_index += 1

		session_team_to_runtime_team[runtime_member_id] = runtime_member_id
		runtime_team_to_control_type[runtime_member_id] = control_type
		runtime_team_to_alliance_team[runtime_member_id] = alliance_team_id

		if not alliance_team_to_runtime_teams.has(alliance_team_id):
			alliance_team_to_runtime_teams[alliance_team_id] = []

		var alliance_members: Array = alliance_team_to_runtime_teams[alliance_team_id]
		alliance_members.append(runtime_member_id)
		alliance_team_to_runtime_teams[alliance_team_id] = alliance_members

		runtime_team_to_name[runtime_member_id] = "%s Member %d" % [
			_get_alliance_display_name(alliance_team_id),
			runtime_member_id + 1
		]

		var hq_id: int = structure_manager.spawn_structure(
			hq_stats,
			runtime_member_id,
			spawn_position,
			hq_scene
		)

		runtime_team_to_hq_id[runtime_member_id] = hq_id
		active_runtime_team_ids.append(runtime_member_id)

		if control_type == GameSession.ControlType.PLAYER:
			player_base_positions_to_reveal.append(spawn_position)

		if queue_starter_unit_on_spawn and starter_unit_stats != null:
			for _i in range(queue_starter_unit_count):
				structure_manager.queue_unit_production(hq_id, starter_unit_stats)

		if control_type == GameSession.ControlType.AI:
			if ai_team_manager != null:
				ai_team_manager.register_ai_team(runtime_member_id, hq_id)

	local_player_runtime_team_id = GameSession.local_player_team_id

	if runtime_team_to_hq_id.has(local_player_runtime_team_id):
		local_player_hq_id = int(runtime_team_to_hq_id[local_player_runtime_team_id])
	else:
		for runtime_team_id in runtime_team_to_control_type.keys():
			if int(runtime_team_to_control_type[runtime_team_id]) == GameSession.ControlType.PLAYER:
				local_player_runtime_team_id = int(runtime_team_id)
				local_player_hq_id = int(runtime_team_to_hq_id[runtime_team_id])
				break

	if selection_controller != null and local_player_runtime_team_id != -1:
		selection_controller.player_team_id = local_player_runtime_team_id

	if game_manager != null:
		game_manager.configure_from_game_session(active_runtime_team_ids)

	_set_map_base_reveal_points(_collect_local_base_reveal_positions())
	_update_map_reveal_points()
	_center_camera_on_local_hq()
	_refresh_map_after_camera_jump()
	_print_match_summary()

func _collect_local_base_reveal_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []

	if structure_manager == null:
		return result

	for runtime_team_id in runtime_team_to_hq_id.keys():
		var team_id: int = int(runtime_team_id)

		if not _is_team_revealed_to_local_players(team_id):
			continue

		var hq_id: int = int(runtime_team_to_hq_id[team_id])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq == null:
			continue

		if not hq.is_alive:
			continue

		result.append(hq.position)

	return result

func _check_match_end() -> void:
	var alive_alliances: Array[int] = []

	for alliance_team_id in alliance_team_to_runtime_teams.keys():
		if _is_alliance_alive(int(alliance_team_id)):
			alive_alliances.append(int(alliance_team_id))

	if alive_alliances.size() > 1:
		return

	match_is_over = true

	if alive_alliances.size() == 1:
		var winner_alliance_id: int = alive_alliances[0]
		var winner_name: String = _get_alliance_display_name(winner_alliance_id)
		var winner_color: Color = TeamPalette.get_team_color(winner_alliance_id)

		print("MATCH END: ", winner_name, " wins")

		if match_end_controller != null:
			match_end_controller.show_match_end(winner_name, winner_color)
	else:
		print("MATCH END: draw")

		if match_end_controller != null:
			match_end_controller.show_draw()


func _is_alliance_alive(alliance_team_id: int) -> bool:
	if not alliance_team_to_runtime_teams.has(alliance_team_id):
		return false

	var members: Array = alliance_team_to_runtime_teams[alliance_team_id]

	for runtime_member_id in members:
		var hq_id: int = get_hq_id_for_runtime_team(int(runtime_member_id))

		if hq_id == -1:
			continue

		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq != null and hq.is_alive:
			return true

	return false


func _get_alliance_display_name(alliance_team_id: int) -> String:
	if alliance_team_id >= 0 and alliance_team_id < TEAM_DISPLAY_NAMES.size():
		return TEAM_DISPLAY_NAMES[alliance_team_id]

	return "Team %d" % (alliance_team_id + 1)


func get_alliance_team_id_for_runtime_team(runtime_team_id: int) -> int:
	if runtime_team_to_alliance_team.has(runtime_team_id):
		return int(runtime_team_to_alliance_team[runtime_team_id])

	return runtime_team_id


func _get_spawn_position(session_team_id: int, fallback_index: int) -> Vector2:
	var generated_spawn_position: Vector2 = _get_spawn_position_from_current_map(session_team_id, fallback_index)

	if generated_spawn_position != Vector2.INF:
		return generated_spawn_position

	if session_team_id >= 0 and session_team_id < team_spawn_markers.size():
		var preferred: Vector2 = _get_spawn_position_from_marker_index(session_team_id)

		if preferred != Vector2.INF:
			return preferred

	if fallback_index >= 0 and fallback_index < team_spawn_markers.size():
		var fallback: Vector2 = _get_spawn_position_from_marker_index(fallback_index)

		if fallback != Vector2.INF:
			return fallback

	return Vector2.ZERO


func _get_spawn_position_from_current_map(session_team_id: int, fallback_index: int) -> Vector2:
	if current_map_instance == null:
		return Vector2.INF

	if not is_instance_valid(current_map_instance):
		return Vector2.INF

	if not current_map_instance.has_method("get_team_spawn_position"):
		return Vector2.INF

	var result: Variant = current_map_instance.call(
		"get_team_spawn_position",
		session_team_id,
		fallback_index
	)

	if result is Vector2:
		return result

	return Vector2.INF


func _get_spawn_position_from_marker_index(index: int) -> Vector2:
	if index < 0 or index >= team_spawn_markers.size():
		return Vector2.INF

	var marker_path: NodePath = team_spawn_markers[index]

	if marker_path == NodePath():
		return Vector2.INF

	var node: Node = get_node_or_null(marker_path)

	if node == null:
		push_error("MatchController: spawn marker path is invalid: %s" % [str(marker_path)])
		return Vector2.INF

	if node is Node2D:
		return node.global_position

	push_error("MatchController: spawn marker is not a Node2D: %s" % [str(marker_path)])
	return Vector2.INF


func _center_camera_on_local_hq() -> void:
	if local_player_hq_id == -1:
		return

	if structure_manager == null:
		return

	if camera_pan_controller == null:
		return

	var hq: StructureRuntime = structure_manager.get_structure(local_player_hq_id)

	if hq == null:
		return

	camera_pan_controller.position = hq.position


func _set_map_base_reveal_points(base_positions: Array[Vector2]) -> void:
	if current_map_instance == null:
		return

	if not is_instance_valid(current_map_instance):
		return

	if current_map_instance.has_method("set_base_reveal_points"):
		current_map_instance.call("set_base_reveal_points", base_positions, true)
		return

	if current_map_instance.has_method("pin_chunks_around_positions"):
		current_map_instance.call("pin_chunks_around_positions", base_positions, 1, true)


func _refresh_map_after_camera_jump() -> void:
	if current_map_instance == null:
		return

	if not is_instance_valid(current_map_instance):
		return

	if not current_map_instance.has_method("refresh_visible_chunks"):
		return

	current_map_instance.call_deferred("refresh_visible_chunks")


func _update_map_reveal_points() -> void:
	if current_map_instance == null:
		return

	if not is_instance_valid(current_map_instance):
		return

	var unit_points: Array[Vector2] = []
	var structure_points: Array[Vector2] = []

	if reveal_friendly_units:
		unit_points = _collect_friendly_unit_reveal_points()

	if reveal_friendly_structures:
		structure_points = _collect_friendly_structure_reveal_points()

	if current_map_instance.has_method("set_dynamic_reveal_points"):
		current_map_instance.call("set_dynamic_reveal_points", unit_points)

	if current_map_instance.has_method("set_structure_reveal_points"):
		current_map_instance.call("set_structure_reveal_points", structure_points)

	_apply_fog_visibility_context_to_sim_managers(unit_points, structure_points)

	if current_map_instance.has_method("refresh_visible_chunks"):
		current_map_instance.call("refresh_visible_chunks")

func _apply_fog_visibility_context_to_sim_managers(
	unit_points: Array[Vector2],
	structure_points: Array[Vector2]
) -> void:
	var fog_player_team_ids: Array[int] = _get_fog_player_runtime_team_ids()

	if unit_manager != null and unit_manager.has_method("set_fog_of_war_context"):
		unit_manager.call(
			"set_fog_of_war_context",
			unit_points,
			structure_points,
			fog_player_team_ids
		)

	if structure_manager != null and structure_manager.has_method("set_fog_of_war_context"):
		structure_manager.call(
			"set_fog_of_war_context",
			unit_points,
			structure_points,
			fog_player_team_ids
		)


func _get_fog_player_runtime_team_ids() -> Array[int]:
	var result: Array[int] = []

	if GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP:
		if local_player_runtime_team_id != -1:
			result.append(local_player_runtime_team_id)

		return result

	for runtime_team_id in runtime_team_to_control_type.keys():
		var control_type: int = int(runtime_team_to_control_type[runtime_team_id])

		if control_type == GameSession.ControlType.PLAYER:
			result.append(int(runtime_team_id))

	return result

func _collect_friendly_unit_reveal_points() -> Array[Vector2]:
	var result: Array[Vector2] = []

	if unit_manager == null:
		return result

	if local_player_runtime_team_id == -1:
		return result

	for unit_value in unit_manager.units.values():
		var unit: UnitRuntime = unit_value as UnitRuntime

		if unit == null:
			continue

		if not unit.is_alive:
			continue

		if not _is_team_revealed_to_local_players(unit.owner_team_id):
			continue

		result.append(unit.position)

		if max_unit_reveal_points > 0 and result.size() >= max_unit_reveal_points:
			break

	return result


func _collect_friendly_structure_reveal_points() -> Array[Vector2]:
	var result: Array[Vector2] = []

	if structure_manager == null:
		return result

	if local_player_runtime_team_id == -1:
		return result

	for structure_value in structure_manager.structures.values():
		var structure: StructureRuntime = structure_value as StructureRuntime

		if structure == null:
			continue

		if not structure.is_alive:
			continue

		if not _is_team_revealed_to_local_players(structure.owner_team_id):
			continue

		result.append(structure.position)

	return result


func _is_team_revealed_to_local_players(owner_team_id: int) -> bool:
	var fog_player_team_ids: Array[int] = _get_fog_player_runtime_team_ids()

	for player_team_id in fog_player_team_ids:
		if team_manager == null:
			if owner_team_id == player_team_id:
				return true
		else:
			if not team_manager.is_enemy(player_team_id, owner_team_id):
				return true

	return owner_team_id == local_player_runtime_team_id


func get_runtime_team_id_from_session_team_id(session_team_id: int) -> int:
	if session_team_to_runtime_team.has(session_team_id):
		return int(session_team_to_runtime_team[session_team_id])

	return -1


func get_hq_id_for_runtime_team(runtime_team_id: int) -> int:
	if runtime_team_to_hq_id.has(runtime_team_id):
		return int(runtime_team_to_hq_id[runtime_team_id])

	return -1


func get_control_type_for_runtime_team(runtime_team_id: int) -> int:
	if runtime_team_to_control_type.has(runtime_team_id):
		return int(runtime_team_to_control_type[runtime_team_id])

	return GameSession.ControlType.CLOSED


func _print_match_summary() -> void:
	print("--- MatchController _ready ---")
	print("Active runtime members: ", runtime_team_to_control_type.size())

	for runtime_team_id in runtime_team_to_control_type.keys():
		var control_type: int = int(runtime_team_to_control_type[runtime_team_id])
		var hq_id: int = int(runtime_team_to_hq_id[runtime_team_id])
		var alliance_id: int = get_alliance_team_id_for_runtime_team(int(runtime_team_id))

		print(
			"Runtime member ",
			runtime_team_id,
			" alliance=",
			alliance_id,
			" control_type=",
			control_type,
			" hq_id=",
			hq_id
		)

	if local_player_runtime_team_id != -1:
		print("Local player runtime member = ", local_player_runtime_team_id)
		print("Local player HQ = ", local_player_hq_id)
