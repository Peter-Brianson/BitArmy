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

var runtime_team_to_control_type: Dictionary = {}
var runtime_team_to_hq_id: Dictionary = {}
var session_team_to_runtime_team: Dictionary = {}

var local_player_runtime_team_id: int = -1
var local_player_hq_id: int = -1

@export var match_end_controller: MatchEndController

var runtime_team_to_name: Dictionary = {}
var match_is_over: bool = false

@export var map_host: Node2D

var current_map_instance: Node = null

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

func _process(_delta: float) -> void:
	if match_is_over:
		return

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

func get_total_runtime_team_count() -> int:
	return runtime_team_to_hq_id.size()

func _get_runtime_team_display_name(runtime_team_id: int) -> String:
	if runtime_team_id >= 0 and runtime_team_id < TEAM_DISPLAY_NAMES.size():
		return TEAM_DISPLAY_NAMES[runtime_team_id]

	return "Team %d" % (runtime_team_id + 1)

func _build_match_from_game_session() -> void:
	
	runtime_team_to_name.clear()
	match_is_over = false

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

	var active_teams: Array[Dictionary] = GameSession.get_active_teams()
	var active_runtime_team_ids: Array[int] = []

	if active_teams.is_empty():
		push_error("MatchController: GameSession returned no active teams.")
		return

	if team_spawn_markers.size() < active_teams.size():
		push_error("MatchController: not enough team_spawn_markers for active teams.")
		return

	# Clear previous runtime data.
	runtime_team_to_control_type.clear()
	runtime_team_to_hq_id.clear()
	session_team_to_runtime_team.clear()
	local_player_runtime_team_id = -1
	local_player_hq_id = -1

	if ai_team_manager != null:
		ai_team_manager.clear_all_ai_teams()

	# Runtime team IDs should be contiguous: 0..N-1
	team_manager.setup_free_for_all(active_teams.size())

	for runtime_team_id in range(active_teams.size()):
		var team_data: Dictionary = active_teams[runtime_team_id]

		var session_team_id: int = int(team_data["team_id"])
		var control_type: int = int(team_data["control_type"])
		var spawn_position: Vector2 = _get_spawn_position(runtime_team_id)

		session_team_to_runtime_team[session_team_id] = runtime_team_id
		runtime_team_to_control_type[runtime_team_id] = control_type
		var team_name: String = _get_runtime_team_display_name(runtime_team_id)
		runtime_team_to_name[runtime_team_id] = team_name

		var hq_id: int = structure_manager.spawn_structure(
			hq_stats,
			runtime_team_id,
			spawn_position,
			hq_scene
		)

		runtime_team_to_hq_id[runtime_team_id] = hq_id
		active_runtime_team_ids.append(runtime_team_id)

		if control_type == GameSession.ControlType.PLAYER and local_player_runtime_team_id == -1:
			local_player_runtime_team_id = runtime_team_id
			local_player_hq_id = hq_id
		elif control_type == GameSession.ControlType.AI:
			if ai_team_manager != null:
				ai_team_manager.register_ai_team(runtime_team_id, hq_id)

		if queue_starter_unit_on_spawn and starter_unit_stats != null:
			for _i in range(queue_starter_unit_count):
				structure_manager.queue_unit_production(hq_id, starter_unit_stats)

	# Assign the local human team to the existing selection/controller layer.
	if selection_controller != null and local_player_runtime_team_id != -1:
		selection_controller.player_team_id = local_player_runtime_team_id

	# Configure match economy from GameSession.
	if game_manager != null:
		game_manager.configure_from_game_session(active_runtime_team_ids)
		
	# Center the camera on the first player team's HQ.
	_center_camera_on_local_hq()

	_print_match_summary()

func _check_match_end() -> void:
	var alive_runtime_teams: Array[int] = []

	for runtime_team_id in runtime_team_to_hq_id.keys():
		var hq_id: int = int(runtime_team_to_hq_id[runtime_team_id])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq != null and hq.is_alive:
			alive_runtime_teams.append(int(runtime_team_id))

	if alive_runtime_teams.size() > 1:
		return

	match_is_over = true

	if alive_runtime_teams.size() == 1:
		var winner_team_id: int = alive_runtime_teams[0]
		var winner_name: String = _get_runtime_team_display_name(winner_team_id)

		if runtime_team_to_name.has(winner_team_id):
			winner_name = str(runtime_team_to_name[winner_team_id])

		var winner_color: Color = TeamPalette.get_team_color(winner_team_id)

		print("MATCH END: ", winner_name, " wins")

		if match_end_controller != null:
			match_end_controller.show_match_end(winner_name, winner_color)
		else:
			print("MATCH END: draw")
			if match_end_controller != null:
				match_end_controller.show_draw()

func _get_spawn_position(runtime_team_id: int) -> Vector2:
	if runtime_team_id < 0 or runtime_team_id >= team_spawn_markers.size():
		return Vector2.ZERO

	var marker_path: NodePath = team_spawn_markers[runtime_team_id]
	if marker_path == NodePath():
		return Vector2.ZERO

	var node: Node = get_node_or_null(marker_path)
	if node == null:
		push_error("MatchController: spawn marker path is invalid: %s" % [str(marker_path)])
		return Vector2.ZERO

	if node is Node2D:
		return node.global_position

	push_error("MatchController: spawn marker is not a Node2D: %s" % [str(marker_path)])
	return Vector2.ZERO


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
	print("Active runtime teams: ", runtime_team_to_control_type.size())

	for runtime_team_id in runtime_team_to_control_type.keys():
		var control_type: int = int(runtime_team_to_control_type[runtime_team_id])
		var hq_id: int = int(runtime_team_to_hq_id[runtime_team_id])

		print(
			"Runtime team ", runtime_team_id,
			" control_type=", control_type,
			" hq_id=", hq_id
		)

	if local_player_runtime_team_id != -1:
		print("Local player runtime team = ", local_player_runtime_team_id)
		print("Local player HQ = ", local_player_hq_id)
