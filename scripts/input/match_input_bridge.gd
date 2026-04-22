class_name MatchInputBridge
extends Node

@export var camera_pan_controller: CameraPanController
@export var match_controller: MatchController
@export var selection_controller: SelectionController
@export var primary_player_index: int = 0
@export var pause_menu_group_name: String = "pause_menu"
@export var consume_router_transients: bool = true

var _direct_pause_latch: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var player = InputHub.get_player(primary_player_index)
	if player == null:
		# Still allow direct keyboard pause fallback even if router player lookup fails.
		_apply_direct_pause_fallback()

		if consume_router_transients:
			InputHub.begin_frame()
		return

	_apply_camera_inputs(player)
	_apply_pointer_inputs(player)
	_apply_pause_input(player)
	_apply_qol_actions(player)
	_apply_direct_pause_fallback()

	if consume_router_transients:
		InputHub.begin_frame()


func _apply_camera_inputs(player) -> void:
	if camera_pan_controller == null:
		return

	camera_pan_controller.external_camera_pan = player.camera_pan
	camera_pan_controller.external_zoom_delta = player.zoom_delta


func _apply_pointer_inputs(player) -> void:
	if camera_pan_controller == null:
		return

	if not player.is_keyboard_mouse:
		camera_pan_controller.set_virtual_pointer_screen(player.pointer_screen)

		if player.primary_just_pressed:
			camera_pan_controller.emit_virtual_mouse_button(MOUSE_BUTTON_LEFT, true)
		if player.primary_just_released:
			camera_pan_controller.emit_virtual_mouse_button(MOUSE_BUTTON_LEFT, false)

		if player.secondary_just_pressed:
			camera_pan_controller.emit_virtual_mouse_button(MOUSE_BUTTON_RIGHT, true)
		if player.secondary_just_released:
			camera_pan_controller.emit_virtual_mouse_button(MOUSE_BUTTON_RIGHT, false)
	else:
		camera_pan_controller.clear_virtual_pointer_override()


func _apply_pause_input(player) -> void:
	if not player.pause_just_pressed:
		return

	_toggle_pause_menu()


func _apply_direct_pause_fallback() -> void:
	# Keyboard fallback for cases where router transients are missed.
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
