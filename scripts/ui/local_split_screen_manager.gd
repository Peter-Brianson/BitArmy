class_name LocalSplitScreenManager
extends Control

@export_group("Main Single-Screen Nodes")
@export var main_camera_rig: CameraPanController
@export var original_match_input_bridge: MatchInputBridge
@export var main_selection_controller: SelectionController

@export_group("Match Managers")
@export var match_controller: MatchController
@export var team_manager: TeamManager
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var match_net_controller: MatchNetController

@export_group("Optional Render Nodes")
@export var unit_batch_renderer: Node

@export_group("Split Screen")
@export var max_views: int = 4
@export var split_only_in_skirmish: bool = true
@export var show_split_when_player_count_at_least: int = 2
@export var cursor_size: Vector2 = Vector2(8.0, 8.0)
@export var cursor_texture: Texture2D
@export var keep_cursor_world_anchored_while_panning: bool = true

var _views: Array[Dictionary] = []
var _local_pointers: Dictionary = {}
var _split_active: bool = false

var _saved_unit_camera_controller: CameraPanController
var _saved_structure_camera_controller: CameraPanController
var _saved_unit_batch_camera_controller: CameraPanController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if unit_manager != null:
		_saved_unit_camera_controller = unit_manager.camera_pan_controller

	if structure_manager != null:
		_saved_structure_camera_controller = structure_manager.camera_pan_controller

	if unit_batch_renderer != null:
		var saved_batch_camera = unit_batch_renderer.get("camera_pan_controller")

		if saved_batch_camera is CameraPanController:
			_saved_unit_batch_camera_controller = saved_batch_camera

	if InputHub != null:
		InputHub.player_joined.connect(_on_players_changed)
		InputHub.player_left.connect(_on_players_changed)
		InputHub.player_team_changed.connect(_on_player_team_changed)

	call_deferred("_rebuild_views")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _process(_delta: float) -> void:
	if not _split_active:
		return

	var players: Array = InputHub.get_split_screen_players()
	var count: int = min(players.size(), _views.size())

	for i in range(count):
		var player = players[i]
		var view: Dictionary = _views[i]

		var container: SubViewportContainer = view.get("container", null)
		var camera_rig: CameraPanController = view.get("camera_rig", null)
		var selection: SelectionController = view.get("selection", null)

		if container == null or camera_rig == null:
			continue

		var local_screen_pos: Vector2 = _get_local_pointer_screen(player, container)

		var cursor_world_before_pan: Vector2 = camera_rig.screen_to_world(local_screen_pos)
		var should_anchor_cursor: bool = keep_cursor_world_anchored_while_panning
		should_anchor_cursor = should_anchor_cursor and player.camera_pan.length_squared() > 0.001
		should_anchor_cursor = should_anchor_cursor and player.pointer_delta.length_squared() <= 0.001

		camera_rig.external_camera_pan = player.camera_pan
		camera_rig.external_zoom_delta = player.zoom_delta

		if should_anchor_cursor and camera_rig.has_method("world_to_screen"):
			local_screen_pos = camera_rig.world_to_screen(cursor_world_before_pan)
			local_screen_pos = _clamp_screen_pos(local_screen_pos, container.size)
			_local_pointers[int(player.player_index)] = local_screen_pos

		camera_rig.set_virtual_pointer_screen(local_screen_pos)

		var world_pos: Vector2 = camera_rig.screen_to_world(local_screen_pos)

		if selection != null:
			selection.set_external_pointer_world(world_pos)

			if player.primary_just_pressed:
				selection.primary_pointer_pressed(world_pos)

			if player.primary_just_released:
				selection.primary_pointer_released(world_pos)

			if player.secondary_just_pressed:
				selection.secondary_pointer_pressed(world_pos)
			elif player.cancel_just_pressed:
				selection.clear_selection()

		# Do not use player.join_just_pressed here.
		# Controller A is click/select in runtime. Using join_just_pressed here
		# makes A recenter the camera or create drag-like behavior.

		if player.pause_just_pressed:
			_toggle_pause_menu()

	InputHub.begin_frame()


func _rebuild_views() -> void:
	_clear_views()

	var players: Array = InputHub.get_split_screen_players()
	var view_count: int = min(players.size(), max_views)
	var should_split: bool = view_count >= show_split_when_player_count_at_least

	if split_only_in_skirmish and GameSession.match_mode != GameSession.MatchMode.SKIRMISH:
		should_split = false

	_set_split_active(should_split)

	if not should_split:
		return

	for i in range(view_count):
		_create_view(i, players[i])

	_apply_layout()
	call_deferred("_center_all_views")


func _set_split_active(active: bool) -> void:
	_split_active = active
	visible = active

	if original_match_input_bridge != null:
		original_match_input_bridge.set_process(not active)

	if main_camera_rig != null:
		main_camera_rig.set_process(not active)

	if main_selection_controller != null:
		main_selection_controller.set_process(not active)
		main_selection_controller.set_process_unhandled_input(not active)

	# In split-screen, one culling camera is not enough.
	# Setting these to null lets managers use their full/unculled fallback visibility.
	if unit_manager != null:
		unit_manager.camera_pan_controller = null if active else _saved_unit_camera_controller

	if structure_manager != null:
		structure_manager.camera_pan_controller = null if active else _saved_structure_camera_controller

	if unit_batch_renderer != null:
		unit_batch_renderer.set(
			"camera_pan_controller",
			null if active else _saved_unit_batch_camera_controller
		)


func _create_view(view_index: int, player) -> void:
	var session_member_id: int = int(player.team_id)
	var runtime_member_id: int = _get_runtime_member_for_session_member(session_member_id)

	var container := SubViewportContainer.new()
	container.name = "PlayerView%d" % (view_index + 1)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false

	# Each camera view looks at the same live battlefield, not a copy.
	viewport.world_2d = get_viewport().world_2d

	container.add_child(viewport)

	var view_root := Node2D.new()
	view_root.name = "ViewRoot"
	viewport.add_child(view_root)

	var camera_rig := CameraPanController.new()
	camera_rig.name = "CameraRig_P%d" % (view_index + 1)
	camera_rig.enable_virtual_cursor = true
	camera_rig.warp_os_mouse_for_virtual_pointer = false
	camera_rig.suppress_mouse_camera_input = true
	camera_rig.mouse_edge_pan_enabled = false
	camera_rig.mouse_wheel_zoom_enabled = false

	if main_camera_rig != null:
		camera_rig.world_rect = main_camera_rig.world_rect
		camera_rig.edge_margin = main_camera_rig.edge_margin
		camera_rig.edge_scroll_speed = main_camera_rig.edge_scroll_speed
		camera_rig.keyboard_scroll_speed = main_camera_rig.keyboard_scroll_speed
		camera_rig.zoom_step = main_camera_rig.zoom_step
		camera_rig.min_zoom = main_camera_rig.min_zoom
		camera_rig.max_zoom = main_camera_rig.max_zoom

	view_root.add_child(camera_rig)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.add_to_group("map_cull_camera")

	if main_camera_rig != null and main_camera_rig.camera != null:
		camera.zoom = main_camera_rig.camera.zoom
	else:
		camera.zoom = Vector2.ONE

	camera_rig.camera = camera
	camera_rig.add_child(camera)

	var cursor: Control = _create_virtual_cursor_control()

	# Keep the cursor as a screen-space overlay above this player's viewport.
	container.add_child(cursor)
	camera_rig.virtual_cursor_visual = cursor

	var selection := SelectionController.new()
	selection.name = "SelectionRoot_P%d" % (view_index + 1)
	selection.unit_manager = unit_manager
	selection.structure_manager = structure_manager
	selection.match_net_controller = match_net_controller
	selection.team_manager = team_manager
	selection.player_team_id = runtime_member_id

	# This prevents every split-screen SelectionRoot from also reading the real OS mouse.
	selection.set_process_unhandled_input(false)

	view_root.add_child(selection)

	_views.append({
		"player_index": int(player.player_index),
		"session_member_id": session_member_id,
		"runtime_member_id": runtime_member_id,
		"container": container,
		"viewport": viewport,
		"camera_rig": camera_rig,
		"selection": selection
	})


func _create_virtual_cursor_control() -> Control:
	var cursor: Control = null

	if cursor_texture != null:
		var texture_cursor := TextureRect.new()
		texture_cursor.texture = cursor_texture
		texture_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cursor = texture_cursor
	else:
		var fallback_cursor := ColorRect.new()
		fallback_cursor.color = Color(1.0, 1.0, 1.0, 0.95)
		cursor = fallback_cursor

	cursor.name = "VirtualCursor"
	cursor.size = cursor_size
	cursor.custom_minimum_size = cursor_size
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.z_index = 4096
	cursor.visible = false
	cursor.set_anchors_preset(Control.PRESET_TOP_LEFT)

	return cursor


func _clear_views() -> void:
	for view in _views:
		var container: SubViewportContainer = view.get("container", null)

		if container != null and is_instance_valid(container):
			container.queue_free()

	_views.clear()
	_local_pointers.clear()


func _apply_layout() -> void:
	if _views.is_empty():
		return

	var rects: Array[Rect2] = _get_split_rects(_views.size(), size)

	for i in range(_views.size()):
		var view: Dictionary = _views[i]
		var container: SubViewportContainer = view.get("container", null)
		var viewport: SubViewport = view.get("viewport", null)

		if container == null or viewport == null:
			continue

		var r: Rect2 = rects[i]

		container.position = r.position
		container.size = r.size

		viewport.size = Vector2i(
			max(1, int(r.size.x)),
			max(1, int(r.size.y))
		)

		var player_index: int = int(view.get("player_index", -1))

		if player_index == -1:
			continue

		if not _local_pointers.has(player_index):
			_local_pointers[player_index] = r.size * 0.5
		else:
			_local_pointers[player_index] = _clamp_screen_pos(
				_local_pointers[player_index],
				r.size
			)


func _get_split_rects(count: int, total_size: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []

	if count <= 1:
		rects.append(Rect2(Vector2.ZERO, total_size))
		return rects

	if count == 2:
		if total_size.x >= total_size.y:
			var half_w: float = total_size.x * 0.5

			rects.append(Rect2(
				Vector2.ZERO,
				Vector2(half_w, total_size.y)
			))

			rects.append(Rect2(
				Vector2(half_w, 0.0),
				Vector2(half_w, total_size.y)
			))
		else:
			var half_h: float = total_size.y * 0.5

			rects.append(Rect2(
				Vector2.ZERO,
				Vector2(total_size.x, half_h)
			))

			rects.append(Rect2(
				Vector2(0.0, half_h),
				Vector2(total_size.x, half_h)
			))

		return rects

	var cell_size: Vector2 = total_size * 0.5

	rects.append(Rect2(Vector2.ZERO, cell_size))
	rects.append(Rect2(Vector2(cell_size.x, 0.0), cell_size))
	rects.append(Rect2(Vector2(0.0, cell_size.y), cell_size))

	if count >= 4:
		rects.append(Rect2(cell_size, cell_size))

	return rects


func _get_local_pointer_screen(player, container: SubViewportContainer) -> Vector2:
	var player_index: int = int(player.player_index)
	var container_size: Vector2 = container.size

	if player.is_keyboard_mouse or player.is_touch:
		var global_rect: Rect2 = container.get_global_rect()
		var local_pos: Vector2 = player.pointer_screen - global_rect.position

		local_pos = _clamp_screen_pos(local_pos, container_size)
		_local_pointers[player_index] = local_pos

		return local_pos

	var current: Vector2 = _local_pointers.get(player_index, container_size * 0.5)
	current += player.pointer_delta
	current = _clamp_screen_pos(current, container_size)

	_local_pointers[player_index] = current

	return current


func _clamp_screen_pos(pos: Vector2, viewport_size: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, 0.0, max(viewport_size.x, 1.0)),
		clamp(pos.y, 0.0, max(viewport_size.y, 1.0))
	)


func _center_all_views() -> void:
	for view in _views:
		var camera_rig: CameraPanController = view.get("camera_rig", null)
		var session_member_id: int = int(view.get("session_member_id", -1))

		_center_camera_on_player_member(camera_rig, session_member_id)


func _center_camera_on_player_member(camera_rig: CameraPanController, session_member_id: int) -> void:
	if camera_rig == null:
		return

	if structure_manager == null:
		return

	var runtime_member_id: int = _get_runtime_member_for_session_member(session_member_id)
	var hq_id: int = _get_hq_id_for_runtime_member(runtime_member_id)

	if hq_id == -1:
		return

	var hq: StructureRuntime = structure_manager.get_structure(hq_id)

	if hq == null:
		return

	if not hq.is_alive:
		return

	camera_rig.center_on_world(hq.position)


func _get_runtime_member_for_session_member(session_member_id: int) -> int:
	if match_controller == null:
		return session_member_id

	if match_controller.has_method("get_runtime_team_id_from_session_team_id"):
		var runtime_id: int = match_controller.get_runtime_team_id_from_session_team_id(session_member_id)

		if runtime_id != -1:
			return runtime_id

	var mapping_variant = match_controller.get("session_team_to_runtime_team")

	if mapping_variant is Dictionary:
		var mapping: Dictionary = mapping_variant

		if mapping.has(session_member_id):
			return int(mapping[session_member_id])

	return session_member_id


func _get_hq_id_for_runtime_member(runtime_member_id: int) -> int:
	if match_controller == null:
		return -1

	if match_controller.has_method("get_hq_id_for_runtime_team"):
		return int(match_controller.get_hq_id_for_runtime_team(runtime_member_id))

	var hq_map_variant = match_controller.get("runtime_team_to_hq_id")

	if hq_map_variant is Dictionary:
		var hq_map: Dictionary = hq_map_variant

		if hq_map.has(runtime_member_id):
			return int(hq_map[runtime_member_id])

	return -1


func _toggle_pause_menu() -> void:
	var pause_menu := get_tree().get_first_node_in_group("pause_menu")

	if pause_menu != null and pause_menu.has_method("toggle_pause_menu"):
		pause_menu.toggle_pause_menu()


func _on_players_changed(_player_index: int, _device_id: int) -> void:
	call_deferred("_rebuild_views")


func _on_player_team_changed(_player_index: int, _team_id: int) -> void:
	call_deferred("_rebuild_views")
