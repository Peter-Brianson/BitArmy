class_name InputRouter
extends Node

signal player_joined(player_index: int, device_id: int)
signal player_left(player_index: int, device_id: int)
signal player_team_changed(player_index: int, team_id: int)

const KEYBOARD_MOUSE_DEVICE_ID := -100
const MOBILE_TOUCH_DEVICE_ID := -200
const TOUCH_DEVICE_ID := MOBILE_TOUCH_DEVICE_ID
const MAX_LOCAL_PLAYERS := 8
const MAX_SPLIT_SCREEN_PLAYERS := 4


class PlayerState:
	var player_index: int = -1
	var device_id: int = -1
	var team_id: int = -1
	var is_keyboard_mouse: bool = false
	var is_touch: bool = false

	var pointer_screen: Vector2 = Vector2.ZERO
	var pointer_delta: Vector2 = Vector2.ZERO
	var cursor_velocity: Vector2 = Vector2.ZERO
	var camera_pan: Vector2 = Vector2.ZERO

	var primary_pressed: bool = false
	var primary_just_pressed: bool = false
	var primary_just_released: bool = false

	var secondary_pressed: bool = false
	var secondary_just_pressed: bool = false
	var secondary_just_released: bool = false

	var join_just_pressed: bool = false
	var cancel_just_pressed: bool = false
	var pause_just_pressed: bool = false

	var zoom_in_pressed: bool = false
	var zoom_out_pressed: bool = false
	var zoom_delta: float = 0.0

	var _primary_down_last: bool = false
	var _secondary_down_last: bool = false
	var _join_down_last: bool = false
	var _cancel_down_last: bool = false
	var _pause_down_last: bool = false

	func clear_transients() -> void:
		pointer_delta = Vector2.ZERO
		primary_just_pressed = false
		primary_just_released = false
		secondary_just_pressed = false
		secondary_just_released = false
		join_just_pressed = false
		cancel_just_pressed = false
		pause_just_pressed = false
		zoom_delta = 0.0


@export var stick_deadzone: float = 0.20
@export var controller_cursor_speed: float = 900.0
@export var allow_keyboard_mouse_player: bool = true

@export_group("Player Join / Leave")
@export var allow_global_player_leave: bool = false

@export_group("Mobile Touch")
@export var mobile_hold_seconds: float = 0.28
@export var mobile_tap_max_movement_pixels: float = 18.0
@export var mobile_drag_deadzone_pixels: float = 8.0
@export var mobile_one_finger_drag_pans_camera: bool = true
@export var mobile_invert_drag_pan: bool = true
@export var mobile_pinch_pixels_per_zoom_step: float = 90.0
@export var mobile_min_pinch_distance: float = 16.0

var _players: Array[PlayerState] = []
var _device_to_player: Dictionary = {}

var _mobile: bool = false
var _desktop_like: bool = true

var _mobile_active_touches: Dictionary = {}
var _mobile_primary_touch_index: int = -1
var _mobile_primary_touch_start_pos: Vector2 = Vector2.ZERO
var _mobile_primary_touch_current_pos: Vector2 = Vector2.ZERO
var _mobile_hold_timer: float = 0.0
var _mobile_hold_fired: bool = false
var _mobile_touch_moved_too_far: bool = false
var _mobile_pinching: bool = false
var _mobile_last_pinch_distance: float = 0.0
var _mobile_camera_pan_frame: Vector2 = Vector2.ZERO
var _mobile_zoom_delta_frame: float = 0.0

var _transient_clear_queued: bool = false
var _last_transient_clear_frame: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_mobile = OS.has_feature("mobile")
	_desktop_like = OS.has_feature("desktop") or OS.has_feature("editor")

	if _mobile:
		_register_device_if_needed(MOBILE_TOUCH_DEVICE_ID, false)
	else:
		_refresh_keyboard_mouse_player()
		_refresh_controller_list()


func _input(event: InputEvent) -> void:
	if _mobile:
		_handle_mobile_event(event)
		return

	var device_id: int = event.device

	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		device_id = KEYBOARD_MOUSE_DEVICE_ID

	if _is_join_event(event):
		_register_device_if_needed(device_id)

	if _is_leave_event(event):
		_unregister_device(device_id)
		return

	var player: PlayerState = _get_player_by_device(device_id)

	if player == null:
		return

	if event is InputEventMouseMotion:
		player.pointer_screen = event.position
		player.pointer_delta += event.relative

	elif event is InputEventMouseButton:
		player.pointer_screen = event.position
		# Runtime mouse button edges are polled in _process().
		# This prevents one-frame clicks from being cleared before split-screen reads them.

	elif event is InputEventJoypadButton:
		# Runtime controller button edges are polled in _process().
		# _input() only helps register controllers through _is_join_event().
		pass

	elif event is InputEventKey:
		# Runtime keyboard edges are polled in _process().
		pass


func _process(delta: float) -> void:
	if _mobile:
		_poll_mobile_state(delta)
		return

	_refresh_controller_list()
	_poll_desktop_and_controller_axes(delta)


func begin_frame() -> void:
	if _transient_clear_queued:
		return

	_transient_clear_queued = true
	call_deferred("_clear_transients_deferred")


func _clear_transients_deferred() -> void:
	_transient_clear_queued = false

	var frame: int = Engine.get_process_frames()

	if _last_transient_clear_frame == frame:
		return

	_last_transient_clear_frame = frame

	for player in _players:
		player.clear_transients()


func is_mobile_platform() -> bool:
	return _mobile


func get_player_count() -> int:
	return _players.size()


func get_player(player_index: int) -> PlayerState:
	if player_index < 0 or player_index >= _players.size():
		return null

	return _players[player_index]


func get_players() -> Array[PlayerState]:
	return _players


func get_split_screen_players() -> Array[PlayerState]:
	var result: Array[PlayerState] = []

	for player in _players:
		if result.size() >= MAX_SPLIT_SCREEN_PLAYERS:
			break

		if player.team_id >= 0:
			result.append(player)

	return result


func get_player_label(player_index: int) -> String:
	var player: PlayerState = get_player(player_index)

	if player == null:
		return "Missing Player"

	if player.is_touch:
		return "Touch"

	if player.is_keyboard_mouse:
		return "Keyboard / Mouse"

	return "Controller %d" % player.device_id


func join_connected_controllers(max_total_players: int = MAX_SPLIT_SCREEN_PLAYERS) -> void:
	var joypads: Array[int] = Input.get_connected_joypads()

	for device_id in joypads:
		if _players.size() >= max_total_players:
			return

		if _get_player_by_device(device_id) == null:
			_register_device_if_needed(device_id)


func assign_team(player_index: int, team_id: int) -> void:
	var player := get_player(player_index)

	if player == null:
		return

	player.team_id = team_id
	player_team_changed.emit(player_index, team_id)


func _poll_desktop_and_controller_axes(delta: float) -> void:
	var viewport := get_viewport()

	if viewport == null:
		return

	for player in _players:
		if player.is_keyboard_mouse:
			player.camera_pan = Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
			player.pointer_screen = viewport.get_mouse_position()
			_poll_keyboard_mouse_buttons(player)
			continue

		var device_id: int = player.device_id

		player.camera_pan = Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)

		if player.camera_pan.length() < stick_deadzone:
			player.camera_pan = Vector2.ZERO

		player.cursor_velocity = Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)

		if player.cursor_velocity.length() < stick_deadzone:
			player.cursor_velocity = Vector2.ZERO

		player.pointer_delta = player.cursor_velocity * controller_cursor_speed * delta
		player.pointer_screen += player.pointer_delta

		var viewport_size: Vector2 = viewport.get_visible_rect().size

		player.pointer_screen.x = clamp(player.pointer_screen.x, 0.0, viewport_size.x)
		player.pointer_screen.y = clamp(player.pointer_screen.y, 0.0, viewport_size.y)

		_poll_controller_buttons(player)


func _poll_keyboard_mouse_buttons(player: PlayerState) -> void:
	var primary_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var secondary_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var join_now: bool = Input.is_action_pressed("join_confirm")
	var cancel_now: bool = Input.is_action_pressed("cancel_back")
	var pause_now: bool = Input.is_action_pressed("pause_game")

	_poll_hold_button_edges(player, primary_now, secondary_now)

	if join_now and not player._join_down_last:
		player.join_just_pressed = true

	if cancel_now and not player._cancel_down_last:
		player.cancel_just_pressed = true

	if pause_now and not player._pause_down_last:
		player.pause_just_pressed = true

	player._join_down_last = join_now
	player._cancel_down_last = cancel_now
	player._pause_down_last = pause_now

	player.zoom_delta = 0.0


func _poll_controller_buttons(player: PlayerState) -> void:
	var device_id: int = player.device_id

	var primary_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
	var secondary_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)
	var cancel_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_BACK)
	var pause_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)

	if primary_now and not player._primary_down_last:
		_emit_primary_click(player)
		player.join_just_pressed = true

	if secondary_now and not player._secondary_down_last:
		_emit_secondary_click(player)
		player.cancel_just_pressed = true

	if cancel_now and not player._cancel_down_last:
		player.cancel_just_pressed = true

	if pause_now and not player._pause_down_last:
		player.pause_just_pressed = true

	player._primary_down_last = primary_now
	player._secondary_down_last = secondary_now
	player._cancel_down_last = cancel_now
	player._pause_down_last = pause_now

	player.zoom_delta = 0.0

	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER):
		player.zoom_delta += 1.0

	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_LEFT_SHOULDER):
		player.zoom_delta -= 1.0


func _poll_hold_button_edges(player: PlayerState, primary_now: bool, secondary_now: bool) -> void:
	if primary_now and not player._primary_down_last:
		player.primary_just_pressed = true

	if not primary_now and player._primary_down_last:
		player.primary_just_released = true

	player.primary_pressed = primary_now
	player._primary_down_last = primary_now

	if secondary_now and not player._secondary_down_last:
		player.secondary_just_pressed = true

	if not secondary_now and player._secondary_down_last:
		player.secondary_just_released = true

	player.secondary_pressed = secondary_now
	player._secondary_down_last = secondary_now


func _handle_mobile_event(event: InputEvent) -> void:
	var player: PlayerState = _get_or_create_mobile_player()

	if player == null:
		return

	if event is InputEventScreenTouch:
		_handle_mobile_screen_touch(event, player)
		return

	if event is InputEventScreenDrag:
		_handle_mobile_screen_drag(event, player)
		return


func _handle_mobile_screen_touch(event: InputEventScreenTouch, player: PlayerState) -> void:
	if event.pressed:
		_mobile_active_touches[event.index] = event.position
		player.pointer_screen = event.position

		if _mobile_active_touches.size() == 1:
			_mobile_primary_touch_index = event.index
			_mobile_primary_touch_start_pos = event.position
			_mobile_primary_touch_current_pos = event.position
			_mobile_hold_timer = 0.0
			_mobile_hold_fired = false
			_mobile_touch_moved_too_far = false
			_mobile_pinching = false
			return

		if _mobile_active_touches.size() >= 2:
			_cancel_mobile_primary_touch(player)
			_start_or_update_mobile_pinch()
			return

	if not event.pressed:
		var was_primary: bool = event.index == _mobile_primary_touch_index

		if _mobile_active_touches.has(event.index):
			_mobile_active_touches.erase(event.index)

		if was_primary:
			if player.primary_pressed:
				_apply_press_release(player, true, false)
			elif not _mobile_hold_fired and not _mobile_touch_moved_too_far and not _mobile_pinching:
				_emit_mobile_tap_click(player, event.position)

			_reset_mobile_primary_touch()

		if _mobile_active_touches.size() < 2:
			_mobile_pinching = false
			_mobile_last_pinch_distance = 0.0

		if _mobile_active_touches.size() == 1:
			_promote_remaining_touch_to_primary(player)


func _handle_mobile_screen_drag(event: InputEventScreenDrag, player: PlayerState) -> void:
	_mobile_active_touches[event.index] = event.position

	if _mobile_active_touches.size() >= 2:
		_cancel_mobile_primary_touch(player)
		_update_mobile_pinch()
		return

	if event.index != _mobile_primary_touch_index:
		return

	player.pointer_screen = event.position
	player.pointer_delta += event.relative
	_mobile_primary_touch_current_pos = event.position

	var total_drag: float = _mobile_primary_touch_start_pos.distance_to(_mobile_primary_touch_current_pos)

	if total_drag > mobile_tap_max_movement_pixels:
		_mobile_touch_moved_too_far = true

	if _mobile_hold_fired:
		return

	if not mobile_one_finger_drag_pans_camera:
		return

	if event.relative.length() < mobile_drag_deadzone_pixels:
		return

	var drag_dir: Vector2 = event.relative.normalized()

	if mobile_invert_drag_pan:
		drag_dir *= -1.0

	_mobile_camera_pan_frame = drag_dir


func _poll_mobile_state(delta: float) -> void:
	var player: PlayerState = _get_or_create_mobile_player()

	if player == null:
		return

	player.camera_pan = _mobile_camera_pan_frame
	player.zoom_delta += _mobile_zoom_delta_frame

	_mobile_camera_pan_frame = Vector2.ZERO
	_mobile_zoom_delta_frame = 0.0

	if _mobile_primary_touch_index == -1:
		return

	if _mobile_pinching:
		return

	if _mobile_hold_fired:
		return

	if _mobile_touch_moved_too_far:
		return

	_mobile_hold_timer += delta

	if _mobile_hold_timer >= mobile_hold_seconds:
		_mobile_hold_fired = true
		player.pointer_screen = _mobile_primary_touch_current_pos
		_apply_press_release(player, true, true)


func _emit_mobile_tap_click(player: PlayerState, screen_position: Vector2) -> void:
	player.pointer_screen = screen_position
	_emit_primary_click(player)


func _cancel_mobile_primary_touch(player: PlayerState) -> void:
	if player.primary_pressed:
		_apply_press_release(player, true, false)

	_reset_mobile_primary_touch()


func _reset_mobile_primary_touch() -> void:
	_mobile_primary_touch_index = -1
	_mobile_primary_touch_start_pos = Vector2.ZERO
	_mobile_primary_touch_current_pos = Vector2.ZERO
	_mobile_hold_timer = 0.0
	_mobile_hold_fired = false
	_mobile_touch_moved_too_far = false


func _promote_remaining_touch_to_primary(_player: PlayerState) -> void:
	for touch_index in _mobile_active_touches.keys():
		_mobile_primary_touch_index = int(touch_index)
		_mobile_primary_touch_start_pos = _mobile_active_touches[touch_index]
		_mobile_primary_touch_current_pos = _mobile_active_touches[touch_index]
		_mobile_hold_timer = 0.0
		_mobile_hold_fired = false
		_mobile_touch_moved_too_far = false
		return


func _start_or_update_mobile_pinch() -> void:
	var positions: Array[Vector2] = _get_first_two_touch_positions()

	if positions.size() < 2:
		return

	_mobile_pinching = true
	_mobile_last_pinch_distance = positions[0].distance_to(positions[1])


func _update_mobile_pinch() -> void:
	var positions: Array[Vector2] = _get_first_two_touch_positions()

	if positions.size() < 2:
		return

	var current_distance: float = positions[0].distance_to(positions[1])

	if current_distance < mobile_min_pinch_distance:
		return

	if not _mobile_pinching or _mobile_last_pinch_distance <= 0.0:
		_mobile_pinching = true
		_mobile_last_pinch_distance = current_distance
		return

	var distance_delta: float = current_distance - _mobile_last_pinch_distance
	_mobile_last_pinch_distance = current_distance

	_mobile_zoom_delta_frame += distance_delta / max(mobile_pinch_pixels_per_zoom_step, 1.0)


func _get_first_two_touch_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []

	for key in _mobile_active_touches.keys():
		result.append(_mobile_active_touches[key])

		if result.size() >= 2:
			break

	return result


func _get_or_create_mobile_player() -> PlayerState:
	var player: PlayerState = _get_player_by_device(MOBILE_TOUCH_DEVICE_ID)

	if player != null:
		return player

	_register_device_if_needed(MOBILE_TOUCH_DEVICE_ID, false)
	return _get_player_by_device(MOBILE_TOUCH_DEVICE_ID)


func _refresh_keyboard_mouse_player() -> void:
	if not allow_keyboard_mouse_player:
		return

	if _get_player_by_device(KEYBOARD_MOUSE_DEVICE_ID) != null:
		return

	_register_device_if_needed(KEYBOARD_MOUSE_DEVICE_ID, true)


func _refresh_controller_list() -> void:
	var joypads: Array[int] = Input.get_connected_joypads()
	var missing: Array[int] = []

	for player in _players:
		if player.is_keyboard_mouse or player.is_touch:
			continue

		if not joypads.has(player.device_id):
			missing.append(player.device_id)

	for device_id in missing:
		_unregister_device(device_id)


func _register_device_if_needed(device_id: int, force_keyboard_mouse: bool = false) -> void:
	if _get_player_by_device(device_id) != null:
		return

	if _players.size() >= MAX_LOCAL_PLAYERS:
		return

	var p := PlayerState.new()
	p.player_index = _players.size()
	p.device_id = device_id
	p.is_keyboard_mouse = force_keyboard_mouse or device_id == KEYBOARD_MOUSE_DEVICE_ID
	p.is_touch = device_id == MOBILE_TOUCH_DEVICE_ID or device_id == TOUCH_DEVICE_ID

	if p.is_touch:
		p.is_keyboard_mouse = false

	var viewport := get_viewport()

	if viewport != null:
		p.pointer_screen = viewport.get_visible_rect().size * 0.5

	_players.append(p)
	_device_to_player[device_id] = p.player_index

	player_joined.emit(p.player_index, device_id)


func _unregister_device(device_id: int) -> void:
	if not _device_to_player.has(device_id):
		return

	var remove_index: int = _device_to_player[device_id]
	var removed: PlayerState = _players[remove_index]

	_players.remove_at(remove_index)

	_device_to_player.clear()

	for i in range(_players.size()):
		_players[i].player_index = i
		_device_to_player[_players[i].device_id] = i

	player_left.emit(remove_index, removed.device_id)


func _get_player_by_device(device_id: int) -> PlayerState:
	if not _device_to_player.has(device_id):
		return null

	var index: int = _device_to_player[device_id]

	if index < 0 or index >= _players.size():
		return null

	return _players[index]


func _emit_primary_click(player: PlayerState) -> void:
	player.primary_pressed = false
	player.primary_just_pressed = true
	player.primary_just_released = true
	player.pointer_delta = Vector2.ZERO


func _emit_secondary_click(player: PlayerState) -> void:
	player.secondary_pressed = false
	player.secondary_just_pressed = true
	player.secondary_just_released = true
	player.pointer_delta = Vector2.ZERO


func _apply_press_release(player: PlayerState, is_primary: bool, pressed: bool) -> void:
	if is_primary:
		if pressed and not player.primary_pressed:
			player.primary_just_pressed = true

		if not pressed and player.primary_pressed:
			player.primary_just_released = true

		player.primary_pressed = pressed
	else:
		if pressed and not player.secondary_pressed:
			player.secondary_just_pressed = true

		if not pressed and player.secondary_pressed:
			player.secondary_just_released = true

		player.secondary_pressed = pressed


func _is_join_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_A

	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action_pressed("join_confirm")

	return false


func _is_leave_event(event: InputEvent) -> bool:
	if not allow_global_player_leave:
		return false

	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_B

	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action_pressed("cancel_back")

	return false
