class_name LocalSplitScreenManager
extends Control

@export_group("Main Single-Screen Nodes")
@export var main_camera_rig: CameraPanController
@export var original_match_input_bridge: MatchInputBridge
@export var main_selection_controller: SelectionController
@export var main_selection_underlay: Node2D
@export var main_hud_controller: HUDController

@export_group("Match Managers")
@export var match_controller: MatchController
@export var team_manager: TeamManager
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager
@export var match_net_controller: MatchNetController
@export var game_manager: GameManager
@export var structure_placement_controller: StructurePlacementController

@export_group("Optional Render Nodes")
@export var unit_batch_renderer: Node

@export_group("Split Screen")
@export var max_views: int = 4
@export var split_only_in_skirmish: bool = true
@export var show_split_when_player_count_at_least: int = 2
@export var cursor_size: Vector2 = Vector2(8.0, 8.0)
@export var cursor_texture: Texture2D
@export var cursor_hotspot: Vector2 = Vector2(4.0, 4.0)
@export var keep_cursor_world_anchored_while_panning: bool = true
@export var debug_split_input: bool = false

@export_group("Controller Cursor")
@export var controller_cursor_speed: float = 360.0
@export var controller_cursor_deadzone: float = 0.18

@export_group("Per Player HUD")
@export var hud_scene: PackedScene
@export var show_per_player_hud: bool = true
@export var split_hud_scale: float = 0.72

var _views: Array[Dictionary] = []
var _local_pointers: Dictionary = {}
var _split_active: bool = false

var _saved_unit_camera_controller: CameraPanController
var _saved_structure_camera_controller: CameraPanController
var _saved_unit_batch_camera_controller: CameraPanController

var _primary_down_last: Dictionary = {}
var _secondary_down_last: Dictionary = {}
var _cancel_down_last: Dictionary = {}
var _pause_down_last: Dictionary = {}


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


func _process(delta: float) -> void:
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
		var hud: HUDController = view.get("hud", null)

		if container == null or camera_rig == null:
			continue

		var local_screen_pos: Vector2 = _get_local_pointer_screen(player, container, delta)

		var cursor_world_before_pan: Vector2 = camera_rig.screen_to_world(local_screen_pos)
		var should_anchor_cursor: bool = keep_cursor_world_anchored_while_panning
		should_anchor_cursor = should_anchor_cursor and player.camera_pan.length_squared() > 0.001
		should_anchor_cursor = should_anchor_cursor and _get_controller_cursor_vector(player).length_squared() <= 0.001

		camera_rig.external_camera_pan = player.camera_pan
		camera_rig.external_zoom_delta = player.zoom_delta

		if should_anchor_cursor and camera_rig.has_method("world_to_screen"):
			local_screen_pos = camera_rig.world_to_screen(cursor_world_before_pan)
			local_screen_pos = _clamp_screen_pos(local_screen_pos, container.size)
			_local_pointers[int(player.player_index)] = local_screen_pos

		camera_rig.set_virtual_pointer_screen(local_screen_pos)

		var world_pos: Vector2 = camera_rig.screen_to_world(local_screen_pos)
		var global_screen_pos: Vector2 = container.get_global_rect().position + local_screen_pos

		var pointer := VirtualPointerState.new()
		pointer.setup_from_player(player, local_screen_pos, global_screen_pos, world_pos)
		_apply_runtime_button_poll(pointer, player, container)

		if debug_split_input:
			if pointer.primary_just_pressed or pointer.primary_just_released or pointer.secondary_just_pressed or pointer.pause_just_pressed:
				print(
					"Virtual pointer P",
					pointer.player_index,
					" primary_press=",
					pointer.primary_just_pressed,
					" primary_release=",
					pointer.primary_just_released,
					" secondary=",
					pointer.secondary_just_pressed,
					" pause=",
					pointer.pause_just_pressed,
					" world=",
					pointer.world_pos
				)

		if hud != null and hud.has_method("handle_virtual_pointer"):
			if hud.call("handle_virtual_pointer", pointer):
				pointer.handled_by_ui = true

		if not pointer.is_consumed() and structure_placement_controller != null:
			if structure_placement_controller.has_method("handle_virtual_pointer"):
				if structure_placement_controller.call("handle_virtual_pointer", pointer):
					pointer.handled_by_placement = true

		if not pointer.is_consumed() and selection != null:
			if selection.has_method("handle_virtual_pointer"):
				if selection.call("handle_virtual_pointer", pointer):
					pointer.handled_by_selection = true

		if pointer.pause_just_pressed:
			_toggle_pause_menu()

	InputHub.begin_frame()


func _apply_runtime_button_poll(
	pointer: VirtualPointerState,
	player,
	container: SubViewportContainer
) -> void:
	var player_index: int = int(player.player_index)

	if player.is_keyboard_mouse or player.is_touch:
		var mouse_inside_view: bool = container.get_global_rect().has_point(get_viewport().get_mouse_position())

		var primary_now: bool = mouse_inside_view and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var secondary_now: bool = mouse_inside_view and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var cancel_now: bool = Input.is_action_pressed("cancel_back")
		var pause_now: bool = Input.is_action_pressed("pause_game")

		var primary_last: bool = bool(_primary_down_last.get(player_index, false))
		var secondary_last: bool = bool(_secondary_down_last.get(player_index, false))
		var cancel_last: bool = bool(_cancel_down_last.get(player_index, false))
		var pause_last: bool = bool(_pause_down_last.get(player_index, false))

		pointer.setup_runtime_buttons(
			primary_now,
			primary_last,
			secondary_now,
			secondary_last,
			cancel_now,
			cancel_last,
			pause_now,
			pause_last,
			false
		)

		_primary_down_last[player_index] = primary_now
		_secondary_down_last[player_index] = secondary_now
		_cancel_down_last[player_index] = cancel_now
		_pause_down_last[player_index] = pause_now

		return

	var device_id: int = int(player.device_id)

	var primary_controller_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
	var secondary_controller_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)
	var cancel_controller_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_BACK)
	var pause_controller_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)

	var primary_controller_last: bool = bool(_primary_down_last.get(player_index, false))
	var secondary_controller_last: bool = bool(_secondary_down_last.get(player_index, false))
	var cancel_controller_last: bool = bool(_cancel_down_last.get(player_index, false))
	var pause_controller_last: bool = bool(_pause_down_last.get(player_index, false))

	# Controller A must be holdable so drag-select works.
	pointer.setup_runtime_buttons(
		primary_controller_now,
		primary_controller_last,
		secondary_controller_now,
		secondary_controller_last,
		cancel_controller_now,
		cancel_controller_last,
		pause_controller_now,
		pause_controller_last,
		false
	)

	_primary_down_last[player_index] = primary_controller_now
	_secondary_down_last[player_index] = secondary_controller_now
	_cancel_down_last[player_index] = cancel_controller_now
	_pause_down_last[player_index] = pause_controller_now


func _get_controller_cursor_vector(player) -> Vector2:
	if player.is_keyboard_mouse or player.is_touch:
		return Vector2.ZERO

	var device_id: int = int(player.device_id)
	var stick := Vector2(
		Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
	)

	var stick_length: float = stick.length()

	if stick_length < controller_cursor_deadzone:
		return Vector2.ZERO

	var adjusted_length: float = inverse_lerp(controller_cursor_deadzone, 1.0, min(stick_length, 1.0))
	return stick.normalized() * adjusted_length


func _get_local_pointer_screen(player, container: SubViewportContainer, delta: float) -> Vector2:
	var player_index: int = int(player.player_index)
	var container_size: Vector2 = container.size

	if player.is_keyboard_mouse or player.is_touch:
		var global_rect: Rect2 = container.get_global_rect()
		var local_pos: Vector2 = player.pointer_screen - global_rect.position

		local_pos = _clamp_screen_pos(local_pos, container_size)
		_local_pointers[player_index] = local_pos

		return local_pos

	var current: Vector2 = _local_pointers.get(player_index, container_size * 0.5)
	current += _get_controller_cursor_vector(player) * controller_cursor_speed * delta
	current = _clamp_screen_pos(current, container_size)

	_local_pointers[player_index] = current

	return current


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

	_set_all_match_input_bridges_enabled(not active)

	if main_camera_rig != null:
		main_camera_rig.set_process(not active)

	if main_selection_controller != null:
		main_selection_controller.set_process(not active)
		main_selection_controller.set_process_unhandled_input(not active)

	if main_selection_underlay != null:
		main_selection_underlay.visible = not active

	if main_hud_controller != null:
		main_hud_controller.visible = not active

	if unit_manager != null:
		unit_manager.camera_pan_controller = null if active else _saved_unit_camera_controller

	if structure_manager != null:
		structure_manager.camera_pan_controller = null if active else _saved_structure_camera_controller

	if unit_batch_renderer != null:
		unit_batch_renderer.set(
			"camera_pan_controller",
			null if active else _saved_unit_batch_camera_controller
		)


func _set_all_match_input_bridges_enabled(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("match_input_bridge"):
		if node is MatchInputBridge:
			node.set_process(enabled)

	_set_match_input_bridges_enabled_recursive(get_tree().root, enabled)

	if original_match_input_bridge != null:
		original_match_input_bridge.set_process(enabled)


func _set_match_input_bridges_enabled_recursive(node: Node, enabled: bool) -> void:
	if node is MatchInputBridge:
		node.set_process(enabled)

	for child in node.get_children():
		_set_match_input_bridges_enabled_recursive(child, enabled)


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
	viewport.world_2d = get_viewport().world_2d

	container.add_child(viewport)

	var view_root := Node2D.new()
	view_root.name = "ViewRoot"
	viewport.add_child(view_root)

	var selection_underlay: Node2D = _create_selection_underlay_for_view(view_index)
	view_root.add_child(selection_underlay)

	var camera_rig := CameraPanController.new()
	camera_rig.name = "CameraRig_P%d" % (view_index + 1)
	camera_rig.enable_virtual_cursor = true
	camera_rig.warp_os_mouse_for_virtual_pointer = false
	camera_rig.suppress_mouse_camera_input = true
	camera_rig.mouse_edge_pan_enabled = false
	camera_rig.mouse_wheel_zoom_enabled = false
	camera_rig.virtual_cursor_hotspot = cursor_hotspot

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
	container.add_child(cursor)
	camera_rig.virtual_cursor_visual = cursor

	var selection := SelectionController.new()
	selection.name = "SelectionRoot_P%d" % (view_index + 1)
	selection.unit_manager = unit_manager
	selection.structure_manager = structure_manager
	selection.match_net_controller = match_net_controller
	selection.team_manager = team_manager
	selection.player_team_id = runtime_member_id
	selection.set_process_unhandled_input(false)
	selection.z_as_relative = false
	selection.z_index = 2000

	view_root.add_child(selection)

	_wire_selection_underlay(selection_underlay, selection)

	var player_hud: HUDController = _create_player_hud(container, selection, camera_rig)

	_views.append({
		"player_index": int(player.player_index),
		"session_member_id": session_member_id,
		"runtime_member_id": runtime_member_id,
		"container": container,
		"viewport": viewport,
		"camera_rig": camera_rig,
		"selection": selection,
		"selection_underlay": selection_underlay,
		"hud": player_hud
	})


func _create_selection_underlay_for_view(view_index: int) -> Node2D:
	var underlay: Node2D = null

	if main_selection_underlay != null:
		underlay = main_selection_underlay.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node2D

	if underlay == null:
		underlay = Node2D.new()

	underlay.name = "SelectionUnderlay_P%d" % (view_index + 1)
	underlay.z_as_relative = false
	underlay.z_index = -1000
	underlay.visible = true
	underlay.set_process(true)

	return underlay


func _wire_selection_underlay(underlay: Node2D, selection: SelectionController) -> void:
	if underlay == null:
		return

	underlay.set("selection_controller", selection)
	underlay.set("unit_manager", unit_manager)
	underlay.set("structure_manager", structure_manager)


func _create_player_hud(
	container: SubViewportContainer,
	selection: SelectionController,
	camera_rig: CameraPanController
) -> HUDController:
	if not show_per_player_hud:
		return null

	var hud: HUDController = null

	if hud_scene != null:
		hud = hud_scene.instantiate() as HUDController
	elif main_hud_controller != null:
		hud = main_hud_controller.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as HUDController

	if hud == null:
		return null

	hud.name = "PlayerHUD"
	hud.selection_controller = selection
	hud.unit_manager = unit_manager
	hud.structure_manager = structure_manager
	hud.game_manager = game_manager
	hud.match_controller = match_controller
	hud.match_net_controller = match_net_controller
	hud.camera_pan_controller = camera_rig
	hud.structure_placement_controller = structure_placement_controller
	hud.ui_scale = split_hud_scale

	_copy_main_hud_build_options(hud)

	container.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.visible = true

	return hud


func _copy_main_hud_build_options(hud: HUDController) -> void:
	if hud == null or main_hud_controller == null:
		return

	var stats_variant: Variant = main_hud_controller.get("buildable_structure_stats")
	var scenes_variant: Variant = main_hud_controller.get("buildable_structure_scenes")

	if stats_variant is Array:
		hud.set("buildable_structure_stats", (stats_variant as Array).duplicate())

	if scenes_variant is Array:
		hud.set("buildable_structure_scenes", (scenes_variant as Array).duplicate())


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
	_primary_down_last.clear()
	_secondary_down_last.clear()
	_cancel_down_last.clear()
	_pause_down_last.clear()


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
			rects.append(Rect2(Vector2.ZERO, Vector2(half_w, total_size.y)))
			rects.append(Rect2(Vector2(half_w, 0.0), Vector2(half_w, total_size.y)))
		else:
			var half_h: float = total_size.y * 0.5
			rects.append(Rect2(Vector2.ZERO, Vector2(total_size.x, half_h)))
			rects.append(Rect2(Vector2(0.0, half_h), Vector2(total_size.x, half_h)))

		return rects

	var cell_size: Vector2 = total_size * 0.5

	rects.append(Rect2(Vector2.ZERO, cell_size))
	rects.append(Rect2(Vector2(cell_size.x, 0.0), cell_size))
	rects.append(Rect2(Vector2(0.0, cell_size.y), cell_size))

	if count >= 4:
		rects.append(Rect2(cell_size, cell_size))

	return rects


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
