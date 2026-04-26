class_name MatchInputBridge
extends Node

@export var camera_pan_controller: CameraPanController
@export var match_controller: MatchController
@export var selection_controller: SelectionController
@export var hud_controller: HUDController
@export var structure_placement_controller: StructurePlacementController
@export var primary_player_index: int = 0
@export var pause_menu_group_name: String = "pause_menu"
@export var consume_router_transients: bool = true

@export_group("Virtual Cursor")
@export var keep_virtual_cursor_world_anchored_while_panning: bool = true

var _direct_pause_latch: bool = false
var _select_all_down_last: bool = false
var _center_hq_down_last: bool = false

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

	if camera_pan_controller == null:
		return

	var pointer := _build_pointer(player)

	_apply_camera(pointer)

	if hud_controller != null and hud_controller.has_method("handle_virtual_pointer"):
		if hud_controller.call("handle_virtual_pointer", pointer):
			pointer.handled_by_ui = true

	if not pointer.is_consumed() and structure_placement_controller != null:
		if structure_placement_controller.has_method("handle_virtual_pointer"):
			if structure_placement_controller.call("handle_virtual_pointer", pointer):
				pointer.handled_by_placement = true

	if not pointer.is_consumed() and selection_controller != null:
		if selection_controller.has_method("handle_virtual_pointer"):
			if selection_controller.call("handle_virtual_pointer", pointer):
				pointer.handled_by_selection = true

	if pointer.pause_just_pressed:
		_toggle_pause_menu()

	_apply_qol_actions(player)
	_apply_direct_pause_fallback()

	if consume_router_transients:
		InputHub.begin_frame()


func _build_pointer(player) -> VirtualPointerState:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_pos: Vector2 = player.pointer_screen

	if player.is_keyboard_mouse:
		camera_pan_controller.clear_virtual_pointer_override()
	else:
		camera_pan_controller.set_virtual_pointer_screen(screen_pos)

	var world_pos: Vector2 = camera_pan_controller.screen_to_world(screen_pos)

	var pointer := VirtualPointerState.new()
	pointer.setup_from_player(player, screen_pos, screen_pos, world_pos)

	return pointer


func _apply_camera(pointer: VirtualPointerState) -> void:
	camera_pan_controller.external_camera_pan = pointer.camera_pan
	camera_pan_controller.external_zoom_delta = pointer.zoom_delta


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
	var select_all_now: bool = _is_select_all_pressed_for_player(player)
	var center_hq_now: bool = _is_center_hq_pressed_for_player(player)

	if select_all_now and not _select_all_down_last:
		if selection_controller != null:
			selection_controller.select_all_player_units()

	if center_hq_now and not _center_hq_down_last:
		if match_controller != null:
			match_controller.center_camera_on_local_hq()

	_select_all_down_last = select_all_now
	_center_hq_down_last = center_hq_now


func _is_select_all_pressed_for_player(player) -> bool:
	if player == null:
		return false

	if player.is_keyboard_mouse:
		return Input.is_action_pressed("select_all_units")

	if player.is_touch:
		return false

	var device_id: int = int(player.device_id)
	return Input.is_joy_button_pressed(device_id, JOY_BUTTON_Y)


func _is_center_hq_pressed_for_player(player) -> bool:
	if player == null:
		return false

	if player.is_keyboard_mouse:
		return Input.is_action_pressed("center_hq")

	if player.is_touch:
		return false

	var device_id: int = int(player.device_id)
	return Input.get_joy_axis(device_id, JOY_AXIS_TRIGGER_LEFT) > 0.55
