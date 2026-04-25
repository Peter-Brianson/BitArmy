class_name MatchInputBridge
extends Node

@export var camera_pan_controller: CameraPanController
@export var match_controller: MatchController
@export var selection_controller: SelectionController
@export var primary_player_index: int = 0
@export var pause_menu_group_name: String = "pause_menu"
@export var consume_router_transients: bool = true

@export_group("Virtual Cursor")
@export var keep_virtual_cursor_world_anchored_while_panning: bool = true

var _direct_pause_latch: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("match_input_bridge")


func _process(_delta: float) -> void:
	var player = InputHub.get_player(primary_player_index)

	if player == null:
		_apply_direct_pause_fallback()

		if consume_router_transients:
			InputHub.begin_frame()

		return

	_apply_camera_and_pointer_inputs(player)
	_apply_pause_input(player)
	_apply_qol_actions(player)
	_apply_direct_pause_fallback()

	if consume_router_transients:
		InputHub.begin_frame()


func _apply_camera_and_pointer_inputs(player) -> void:
	if camera_pan_controller == null:
		return

	if player.is_keyboard_mouse:
		_apply_camera_inputs(player)
		_apply_pointer_inputs(player)
		return

	var cursor_world_before_pan: Vector2 = camera_pan_controller.screen_to_world(player.pointer_screen)
	var should_anchor_cursor: bool = keep_virtual_cursor_world_anchored_while_panning
	should_anchor_cursor = should_anchor_cursor and player.camera_pan.length_squared() > 0.001
	should_anchor_cursor = should_anchor_cursor and player.pointer_delta.length_squared() <= 0.001

	_apply_camera_inputs(player)

	if should_anchor_cursor and camera_pan_controller.has_method("world_to_screen"):
		var corrected_screen_position: Vector2 = camera_pan_controller.world_to_screen(cursor_world_before_pan)
		player.pointer_screen = corrected_screen_position

	_apply_pointer_inputs(player)


func _apply_camera_inputs(player) -> void:
	if camera_pan_controller == null:
		return

	camera_pan_controller.external_camera_pan = player.camera_pan
	camera_pan_controller.external_zoom_delta = player.zoom_delta


func _apply_pointer_inputs(player) -> void:
	if camera_pan_controller == null:
		return

	if player.is_keyboard_mouse:
		camera_pan_controller.clear_virtual_pointer_override()

		if selection_controller != null:
			selection_controller.clear_external_pointer_world()

		return

	camera_pan_controller.set_virtual_pointer_screen(player.pointer_screen)

	var world_pos: Vector2 = camera_pan_controller.screen_to_world(player.pointer_screen)

	if selection_controller == null:
		return

	selection_controller.set_external_pointer_world(world_pos)

	if player.primary_just_pressed:
		selection_controller.primary_pointer_pressed(world_pos)

	if player.primary_just_released:
		selection_controller.primary_pointer_released(world_pos)

	if player.secondary_just_pressed:
		selection_controller.secondary_pointer_pressed(world_pos)


func _apply_pause_input(player) -> void:
	if not player.pause_just_pressed:
		return

	_toggle_pause_menu()


func _apply_direct_pause_fallback() -> void:
	var pressed_now: bool = Input.is_action_pressed("pause_game")

	if pressed_now and not _direct_pause_latch:
		_direct_pause_latch = true
		_toggle_pause_menu()
	elif not pressed_now:
		_direct_pause_latch = false


func _toggle_pause_menu() -> void:
	var pause_menu := get_tree().get_first_node_in_group(pause_menu_group_name)

	if pause_menu != null and pause_menu.has_method("toggle_pause_menu"):
		pause_menu.toggle_pause_menu()


func _apply_qol_actions(player) -> void:
	if not player.is_keyboard_mouse:
		return

	if Input.is_action_just_pressed("center_hq"):
		if match_controller != null:
			match_controller.center_camera_on_local_hq()

	if Input.is_action_just_pressed("select_all_units"):
		if selection_controller != null:
			selection_controller.select_all_player_units()
