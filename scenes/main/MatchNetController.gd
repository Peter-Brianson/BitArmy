class_name MatchNetController
extends Node

@export_group("Core References")
@export var match_controller: MatchController
@export var team_manager: TeamManager
@export var game_manager: GameManager
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var ai_team_manager: AITeamManager

@export_group("Snapshot")
@export var snapshot_interval: float = 0.10

@export_group("Structure Scene Registry")
@export var structure_scene_stats: Array[StructureStats] = []
@export var structure_scene_scenes: Array[PackedScene] = []

var online_enabled: bool = false
var is_host_authority: bool = false
var local_peer_id: int = 1

var _snapshot_timer: float = 0.0
var _sent_match_end: bool = false
var _received_match_end: bool = false

var _structure_scene_by_stats_path: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	online_enabled = (
		GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP
		and multiplayer.multiplayer_peer != null
	)

	if not online_enabled:
		return

	is_host_authority = multiplayer.is_server()
	local_peer_id = multiplayer.get_unique_id()

	_build_structure_scene_registry()
	_bind_match_disconnect_signals()

	if is_host_authority:
		_enable_host_mode()
	else:
		_enable_client_proxy_mode()
		call_deferred("_request_full_sync_from_host")


func _physics_process(delta: float) -> void:
	if not online_enabled:
		return

	if is_host_authority:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = snapshot_interval
			client_apply_snapshot.rpc(_build_snapshot())

		_check_and_broadcast_match_end()


func _enable_host_mode() -> void:
	if match_controller != null:
		match_controller.set_process(true)

	if team_manager != null:
		team_manager.set_physics_process(true)

	if unit_manager != null:
		unit_manager.set_physics_process(true)

	if structure_manager != null:
		structure_manager.set_physics_process(true)

	if ai_team_manager != null:
		ai_team_manager.set_physics_process(true)

	if game_manager != null:
		game_manager.set_process(true)


func _enable_client_proxy_mode() -> void:
	if unit_manager != null:
		unit_manager.clear_all_units()
		unit_manager.set_physics_process(false)

	if structure_manager != null:
		structure_manager.clear_all_structures()
		structure_manager.set_physics_process(false)

	if ai_team_manager != null:
		ai_team_manager.set_physics_process(false)

	if team_manager != null:
		team_manager.set_physics_process(false)

	if game_manager != null:
		game_manager.set_process(false)

	if match_controller != null:
		match_controller.set_process(false)


func _request_full_sync_from_host() -> void:
	if is_host_authority:
		return

	server_request_full_sync.rpc_id(1)


func _bind_match_disconnect_signals() -> void:
	var peer_disconnected_cb := Callable(self, "_on_match_peer_disconnected")
	if not multiplayer.peer_disconnected.is_connected(peer_disconnected_cb):
		multiplayer.peer_disconnected.connect(peer_disconnected_cb)

	var server_disconnected_cb := Callable(self, "_on_match_server_disconnected")
	if not multiplayer.server_disconnected.is_connected(server_disconnected_cb):
		multiplayer.server_disconnected.connect(server_disconnected_cb)


func _on_match_peer_disconnected(peer_id: int) -> void:
	if not online_enabled:
		return
	if not is_host_authority:
		return

	_destroy_disconnected_peer_hq(peer_id)


func _on_match_server_disconnected() -> void:
	if not online_enabled:
		return
	if is_host_authority:
		return

	if match_controller != null:
		match_controller.match_is_over = true

	if match_controller != null and match_controller.match_end_controller != null:
		match_controller.match_end_controller.show_match_end("Connection Lost", Color.WHITE)


func _destroy_disconnected_peer_hq(peer_id: int) -> void:
	if match_controller == null:
		return
	if structure_manager == null:
		return

	for i in range(GameSession.seat_setups.size()):
		var seat: Dictionary = GameSession.seat_setups[i]

		if int(seat.get("peer_id", 0)) != peer_id:
			continue
		if int(seat.get("control_type", GameSession.ControlType.CLOSED)) != GameSession.ControlType.PLAYER:
			continue

		var team_id: int = int(seat.get("team_id", -1))
		if team_id == -1:
			continue

		var runtime_team_id: int = match_controller.get_runtime_team_id_from_session_team_id(team_id)
		if runtime_team_id == -1:
			runtime_team_id = team_id

		var hq_id: int = match_controller.get_hq_id_for_runtime_team(runtime_team_id)
		if hq_id != -1:
			structure_manager.destroy_structure(hq_id)

		GameSession.seat_setups[i]["peer_id"] = 0
		GameSession.seat_setups[i]["control_type"] = GameSession.ControlType.CLOSED


func _build_structure_scene_registry() -> void:
	_structure_scene_by_stats_path.clear()

	var count: int = min(structure_scene_stats.size(), structure_scene_scenes.size())
	for i in range(count):
		var stats: StructureStats = structure_scene_stats[i]
		var scene: PackedScene = structure_scene_scenes[i]

		if stats == null or scene == null:
			continue
		if stats.resource_path == "":
			continue

		_structure_scene_by_stats_path[stats.resource_path] = scene


func _build_snapshot() -> Dictionary:
	return {
		"units": _build_units_snapshot(),
		"structures": _build_structures_snapshot(),
		"economy": _build_economy_snapshot(),
		"match_over": _is_match_over_on_host(),
		"winner_team_id": _get_winner_team_id_on_host()
	}


func _build_units_snapshot() -> Array:
	var result: Array = []

	if unit_manager == null:
		return result

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit
		if u == null:
			continue

		result.append({
			"id": u.id,
			"stats_path": u.stats.resource_path,
			"team_id": u.owner_team_id,
			"x": u.position.x,
			"y": u.position.y,
			"state": u.state,
			"current_health": u.current_health,
			"is_alive": u.is_alive,
			"facing_x": u.facing_dir.x,
			"facing_y": u.facing_dir.y,
			"death_timer_left": u.death_timer_left
		})

	return result


func _build_structures_snapshot() -> Array:
	var result: Array = []

	if structure_manager == null:
		return result

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue

		result.append({
			"id": s.id,
			"stats_path": s.stats.resource_path,
			"team_id": s.owner_team_id,
			"x": s.position.x,
			"y": s.position.y,
			"state": s.state,
			"current_health": s.current_health,
			"is_alive": s.is_alive,
			"rally_x": s.rally_point.x,
			"rally_y": s.rally_point.y,
			"death_timer_left": s.death_timer_left
		})

	return result


func _build_economy_snapshot() -> Dictionary:
	var credits: Dictionary = {}
	var income: Dictionary = {}

	if game_manager == null:
		return {
			"credits_by_team": credits,
			"income_by_team": income
		}

	for team_id in game_manager.credits_by_team.keys():
		credits[int(team_id)] = float(game_manager.credits_by_team[team_id])

	if match_controller != null:
		for runtime_team_id in match_controller.runtime_team_to_hq_id.keys():
			income[int(runtime_team_id)] = game_manager.get_team_income_per_second(int(runtime_team_id))

	return {
		"credits_by_team": credits,
		"income_by_team": income
	}


func _is_match_over_on_host() -> bool:
	if match_controller == null:
		return false
	return match_controller.match_is_over


func _get_winner_team_id_on_host() -> int:
	if match_controller == null or structure_manager == null:
		return -1

	var alive_runtime_teams: Array[int] = []

	for runtime_team_id in match_controller.runtime_team_to_hq_id.keys():
		var hq_id: int = int(match_controller.runtime_team_to_hq_id[runtime_team_id])
		var hq: StructureRuntime = structure_manager.get_structure(hq_id)

		if hq != null and hq.is_alive:
			alive_runtime_teams.append(int(runtime_team_id))

	if alive_runtime_teams.size() == 1:
		return alive_runtime_teams[0]

	return -1


func _check_and_broadcast_match_end() -> void:
	if _sent_match_end:
		return
	if not _is_match_over_on_host():
		return

	_sent_match_end = true
	client_match_end.rpc(_get_winner_team_id_on_host())


func _peer_controls_team(peer_id: int, team_id: int) -> bool:
	for seat in GameSession.seat_setups:
		var seat_data: Dictionary = seat
		if int(seat_data.get("control_type", GameSession.ControlType.CLOSED)) != GameSession.ControlType.PLAYER:
			continue
		if int(seat_data.get("peer_id", 0)) != peer_id:
			continue
		if int(seat_data.get("team_id", -1)) == team_id:
			return true

	return false


func _sender_owns_unit(sender_id: int, unit_id: int) -> bool:
	if unit_manager == null:
		return false

	var unit: UnitRuntime = unit_manager.get_unit(unit_id)
	if unit == null:
		return false

	return _peer_controls_team(sender_id, unit.owner_team_id)


func _sender_owns_structure(sender_id: int, structure_id: int) -> bool:
	if structure_manager == null:
		return false

	var structure: StructureRuntime = structure_manager.get_structure(structure_id)
	if structure == null:
		return false

	return _peer_controls_team(sender_id, structure.owner_team_id)


func _all_units_owned_by_sender(sender_id: int, unit_ids: Array[int]) -> bool:
	for unit_id in unit_ids:
		if not _sender_owns_unit(sender_id, int(unit_id)):
			return false
	return true


func _get_structure_scene_for_stats_path(stats_path: String) -> PackedScene:
	if _structure_scene_by_stats_path.has(stats_path):
		return _structure_scene_by_stats_path[stats_path]

	if structure_manager != null:
		return structure_manager.default_structure_scene

	return null


func _spawn_client_unit_from_snapshot(data: Dictionary) -> void:
	if unit_manager == null:
		return

	var stats_path: String = str(data.get("stats_path", ""))
	var stats: UnitStats = load(stats_path) as UnitStats
	if stats == null:
		return

	var unit_id: int = int(data.get("id", -1))
	if unit_id == -1:
		return

	var unit := UnitRuntime.new()
	unit.setup(
		unit_id,
		stats,
		int(data.get("team_id", 0)),
		Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	)

	unit_manager.units[unit_id] = unit
	unit_manager.unit_death_flash_played[unit_id] = false
	unit_manager.next_unit_id = max(unit_manager.next_unit_id, unit_id + 1)
	unit_manager._create_view(unit)


func _spawn_client_structure_from_snapshot(data: Dictionary) -> void:
	if structure_manager == null:
		return

	var stats_path: String = str(data.get("stats_path", ""))
	var stats: StructureStats = load(stats_path) as StructureStats
	if stats == null:
		return

	var structure_id: int = int(data.get("id", -1))
	if structure_id == -1:
		return

	var structure := StructureRuntime.new()
	structure.setup(
		structure_id,
		stats,
		int(data.get("team_id", 0)),
		Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	)

	structure_manager.structures[structure_id] = structure
	structure_manager.structure_death_flash_played[structure_id] = false
	structure_manager.structure_death_fx_played[structure_id] = false
	structure_manager.next_structure_id = max(structure_manager.next_structure_id, structure_id + 1)

	var scene_override: PackedScene = _get_structure_scene_for_stats_path(stats_path)
	structure_manager._create_view(structure, scene_override)


func _apply_units_snapshot(items: Array) -> void:
	if unit_manager == null:
		return

	var seen_ids: Dictionary = {}

	for item in items:
		var data: Dictionary = item
		var unit_id: int = int(data.get("id", -1))
		if unit_id == -1:
			continue

		seen_ids[unit_id] = true

		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			_spawn_client_unit_from_snapshot(data)
			unit = unit_manager.get_unit(unit_id)

		if unit == null:
			continue

		unit.position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		unit.current_health = int(data.get("current_health", unit.current_health))
		unit.is_alive = bool(data.get("is_alive", unit.is_alive))
		unit.state = int(data.get("state", unit.state))
		unit.facing_dir = Vector2(float(data.get("facing_x", 1.0)), float(data.get("facing_y", 0.0)))
		unit.death_timer_left = float(data.get("death_timer_left", unit.death_timer_left))

		unit.velocity = Vector2.ZERO
		unit.has_move_target = false
		unit.has_attack_move_destination = false

		_sync_unit_view(unit)

	for unit_id in unit_manager.units.keys():
		if not seen_ids.has(unit_id):
			unit_manager._remove_unit(int(unit_id))


func _apply_structures_snapshot(items: Array) -> void:
	if structure_manager == null:
		return

	var seen_ids: Dictionary = {}

	for item in items:
		var data: Dictionary = item
		var structure_id: int = int(data.get("id", -1))
		if structure_id == -1:
			continue

		seen_ids[structure_id] = true

		var structure: StructureRuntime = structure_manager.get_structure(structure_id)
		if structure == null:
			_spawn_client_structure_from_snapshot(data)
			structure = structure_manager.get_structure(structure_id)

		if structure == null:
			continue

		structure.position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		structure.current_health = int(data.get("current_health", structure.current_health))
		structure.is_alive = bool(data.get("is_alive", structure.is_alive))
		structure.state = int(data.get("state", structure.state))
		structure.rally_point = Vector2(float(data.get("rally_x", structure.rally_point.x)), float(data.get("rally_y", structure.rally_point.y)))
		structure.death_timer_left = float(data.get("death_timer_left", structure.death_timer_left))

		_sync_structure_view(structure)

	for structure_id in structure_manager.structures.keys():
		if not seen_ids.has(structure_id):
			structure_manager._remove_structure(int(structure_id))


func _sync_unit_view(unit: UnitRuntime) -> void:
	if unit_manager == null:
		return
	if not unit_manager.unit_views.has(unit.id):
		return

	var view: Node2D = unit_manager.unit_views[unit.id]
	if view == null or not is_instance_valid(view):
		return

	view.global_position = unit.position

	if view is CanvasItem:
		(view as CanvasItem).visible = true

	if view.has_method("apply_unit_runtime_state"):
		view.call(
			"apply_unit_runtime_state",
			unit.state,
			unit.current_health,
			unit.is_alive,
			unit.owner_team_id,
			unit.facing_dir
		)


func _sync_structure_view(structure: StructureRuntime) -> void:
	if structure_manager == null:
		return
	if not structure_manager.structure_views.has(structure.id):
		return

	var view: Node2D = structure_manager.structure_views[structure.id]
	if view == null or not is_instance_valid(view):
		return

	view.global_position = structure.position

	if view is CanvasItem:
		(view as CanvasItem).visible = true

	if view.has_method("apply_structure_runtime_state"):
		view.call(
			"apply_structure_runtime_state",
			structure.state,
			structure.current_health,
			structure.is_alive
		)


func _apply_economy_snapshot(data: Dictionary) -> void:
	if game_manager == null:
		return

	var credits_snapshot: Dictionary = data.get("credits_by_team", {})
	var income_snapshot: Dictionary = data.get("income_by_team", {})
	game_manager.apply_remote_economy_snapshot(credits_snapshot, income_snapshot)


func _apply_remote_match_end(winner_team_id: int) -> void:
	if _received_match_end:
		return

	_received_match_end = true

	if match_controller != null:
		match_controller.match_is_over = true

	var winner_name: String = "Draw"
	var winner_color: Color = Color.WHITE

	if winner_team_id != -1:
		winner_name = "Team %d" % (winner_team_id + 1)
		if match_controller != null and match_controller.runtime_team_to_name.has(winner_team_id):
			winner_name = str(match_controller.runtime_team_to_name[winner_team_id])

		winner_color = TeamPalette.get_team_color(winner_team_id)

	if match_controller != null and match_controller.match_end_controller != null:
		if winner_team_id == -1:
			match_controller.match_end_controller.show_draw()
		else:
			match_controller.match_end_controller.show_match_end(winner_name, winner_color)


func request_move_units(unit_ids: Array[int], target_position: Vector2) -> void:
	if not online_enabled or is_host_authority:
		if unit_manager != null:
			unit_manager.issue_move_order_many(unit_ids, target_position)
		return

	server_request_move.rpc_id(1, unit_ids, target_position)


func request_attack_move_units(unit_ids: Array[int], target_position: Vector2) -> void:
	if not online_enabled or is_host_authority:
		if unit_manager != null:
			unit_manager.issue_attack_move_order_many(unit_ids, target_position)
		return

	server_request_attack_move.rpc_id(1, unit_ids, target_position)


func request_attack_unit(unit_ids: Array[int], target_unit_id: int) -> void:
	if not online_enabled or is_host_authority:
		if unit_manager != null:
			unit_manager.issue_attack_unit_order_many(unit_ids, target_unit_id)
		return

	server_request_attack_unit.rpc_id(1, unit_ids, target_unit_id)


func request_attack_structure(unit_ids: Array[int], target_structure_id: int) -> void:
	if not online_enabled or is_host_authority:
		if unit_manager != null:
			unit_manager.issue_attack_structure_order_many(unit_ids, target_structure_id)
		return

	server_request_attack_structure.rpc_id(1, unit_ids, target_structure_id)


func request_set_rally(structure_id: int, rally_point: Vector2) -> void:
	if not online_enabled or is_host_authority:
		var structure: StructureRuntime = structure_manager.get_structure(structure_id)
		if structure != null:
			structure.rally_point = rally_point
		return

	server_request_set_rally.rpc_id(1, structure_id, rally_point)


func request_queue_unit(structure_id: int, unit_stats: UnitStats) -> void:
	if unit_stats == null:
		return

	if not online_enabled or is_host_authority:
		if structure_manager != null and game_manager != null:
			var structure: StructureRuntime = structure_manager.get_structure(structure_id)
			if structure != null and game_manager.spend_credits(structure.owner_team_id, unit_stats.cost):
				structure_manager.queue_unit_production(structure_id, unit_stats)
		return

	server_request_queue_unit.rpc_id(1, structure_id, unit_stats.resource_path)


func request_place_structure(builder_structure_id: int, structure_stats: StructureStats, world_pos: Vector2) -> void:
	if structure_stats == null:
		return

	if not online_enabled or is_host_authority:
		_server_apply_place_structure(local_peer_id, builder_structure_id, structure_stats.resource_path, world_pos)
		return

	server_request_place_structure.rpc_id(1, builder_structure_id, structure_stats.resource_path, world_pos)


@rpc("any_peer", "call_remote", "reliable")
func server_request_full_sync() -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return

	client_apply_snapshot.rpc_id(sender_id, _build_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func server_request_move(unit_ids: Array[int], target_position: Vector2) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _all_units_owned_by_sender(sender_id, unit_ids):
		return

	unit_manager.issue_move_order_many(unit_ids, target_position)


@rpc("any_peer", "call_remote", "reliable")
func server_request_attack_move(unit_ids: Array[int], target_position: Vector2) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _all_units_owned_by_sender(sender_id, unit_ids):
		return

	unit_manager.issue_attack_move_order_many(unit_ids, target_position)


@rpc("any_peer", "call_remote", "reliable")
func server_request_attack_unit(unit_ids: Array[int], target_unit_id: int) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _all_units_owned_by_sender(sender_id, unit_ids):
		return

	unit_manager.issue_attack_unit_order_many(unit_ids, target_unit_id)


@rpc("any_peer", "call_remote", "reliable")
func server_request_attack_structure(unit_ids: Array[int], target_structure_id: int) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _all_units_owned_by_sender(sender_id, unit_ids):
		return

	unit_manager.issue_attack_structure_order_many(unit_ids, target_structure_id)


@rpc("any_peer", "call_remote", "reliable")
func server_request_set_rally(structure_id: int, rally_point: Vector2) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _sender_owns_structure(sender_id, structure_id):
		return

	var structure: StructureRuntime = structure_manager.get_structure(structure_id)
	if structure == null:
		return

	structure.rally_point = rally_point


@rpc("any_peer", "call_remote", "reliable")
func server_request_queue_unit(structure_id: int, unit_stats_path: String) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _sender_owns_structure(sender_id, structure_id):
		return

	var structure: StructureRuntime = structure_manager.get_structure(structure_id)
	if structure == null:
		return
	if not structure.can_train_units():
		return

	var unit_stats: UnitStats = load(unit_stats_path) as UnitStats
	if unit_stats == null:
		return

	if game_manager != null:
		if not game_manager.spend_credits(structure.owner_team_id, unit_stats.cost):
			return

	structure_manager.queue_unit_production(structure_id, unit_stats)


@rpc("any_peer", "call_remote", "reliable")
func server_request_place_structure(builder_structure_id: int, structure_stats_path: String, world_pos: Vector2) -> void:
	if not is_host_authority:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_server_apply_place_structure(sender_id, builder_structure_id, structure_stats_path, world_pos)


func _server_apply_place_structure(sender_id: int, builder_structure_id: int, structure_stats_path: String, world_pos: Vector2) -> void:
	if not _sender_owns_structure(sender_id, builder_structure_id):
		return

	var builder: StructureRuntime = structure_manager.get_structure(builder_structure_id)
	if builder == null:
		return
	if not builder.can_place_structures():
		return

	var structure_stats: StructureStats = load(structure_stats_path) as StructureStats
	if structure_stats == null:
		return

	if not _can_place_structure_at(structure_stats, world_pos):
		return

	if game_manager != null:
		if not game_manager.spend_credits(builder.owner_team_id, structure_stats.cost):
			return

	var scene_override: PackedScene = _get_structure_scene_for_stats_path(structure_stats_path)
	structure_manager.spawn_structure(
		structure_stats,
		builder.owner_team_id,
		world_pos,
		scene_override
	)


func _can_place_structure_at(stats: StructureStats, world_pos: Vector2) -> bool:
	if stats == null or structure_manager == null:
		return false

	if match_controller != null and match_controller.camera_pan_controller != null:
		var world_rect: Rect2 = match_controller.camera_pan_controller.world_rect
		var half: Vector2 = stats.footprint_size * 0.5
		var placement_rect := Rect2(world_pos - half, stats.footprint_size)

		if not world_rect.encloses(placement_rect):
			return false

	for structure in structure_manager.structures.values():
		var s: StructureRuntime = structure
		if s == null:
			continue
		if not s.is_alive:
			continue

		var existing_half: Vector2 = s.stats.footprint_size * 0.5
		var existing_rect := Rect2(
			s.position - existing_half - Vector2(8.0, 8.0),
			s.stats.footprint_size + Vector2(16.0, 16.0)
		)

		var new_half: Vector2 = stats.footprint_size * 0.5
		var new_rect := Rect2(world_pos - new_half, stats.footprint_size)

		if new_rect.intersects(existing_rect):
			return false

	return true


@rpc("authority", "call_remote", "unreliable")
func client_apply_snapshot(snapshot: Dictionary) -> void:
	if is_host_authority:
		return

	_apply_units_snapshot(snapshot.get("units", []))
	_apply_structures_snapshot(snapshot.get("structures", []))
	_apply_economy_snapshot(snapshot.get("economy", {}))

	if bool(snapshot.get("match_over", false)):
		_apply_remote_match_end(int(snapshot.get("winner_team_id", -1)))


@rpc("authority", "call_remote", "reliable")
func client_match_end(winner_team_id: int) -> void:
	if is_host_authority:
		return

	_apply_remote_match_end(winner_team_id)
