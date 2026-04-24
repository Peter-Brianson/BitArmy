class_name InputRouter
extends Node

signal player_joined(player_index: int, device_id: int)
signal player_left(player_index: int, device_id: int)
signal player_team_changed(player_index: int, team_id: int)

const KEYBOARD_MOUSE_DEVICE_ID := -100
const TOUCH_DEVICE_ID := -200
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

@export_group("Touch")
@export var touch_tap_max_distance: float = 22.0
@export var touch_long_press_seconds: float = 0.42
@export var touch_pan_pixels_for_full_speed: float = 42.0
@export var touch_pinch_pixels_per_zoom_step: float = 48.0

var _players: Array[PlayerState] = []
var _device_to_player: Dictionary = {}

var _mobile: bool = false

var _active_touches: Dictionary = {}
var _primary_touch_index: int = -1
var _touch_down_pos: Vector2 = Vector2.ZERO
var _touch_down_seconds: float = 0.0
var _touch_moved_too_far: bool = false
var _touch_long_press_fired: bool = false
var _last_touch_centroid: Vector2 = Vector2.ZERO
var _last_pinch_distance: float = 0.0
var _mobile_pan_decay: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_mobile = OS.has_feature("mobile")

	if _mobile:
		_register_device_if_needed(TOUCH_DEVICE_ID, false, true)
	else:
		_refresh_keyboard_mouse_player()

	_refresh_controller_list()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMagnifyGesture:
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

		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_apply_press_release(player, true, event.pressed)

			MOUSE_BUTTON_RIGHT:
				_apply_press_release(player, false, event.pressed)

			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					player.zoom_delta += 1.0

			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					player.zoom_delta -= 1.0

	elif event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_A:
				_apply_press_release(player, true, event.pressed)

				if event.pressed:
					player.join_just_pressed = true

			JOY_BUTTON_B:
				_apply_press_release(player, false, event.pressed)

				if event.pressed:
					player.cancel_just_pressed = true

			JOY_BUTTON_BACK:
				if event.pressed:
					player.cancel_just_pressed = true

			JOY_BUTTON_START:
				if event.pressed:
					player.pause_just_pressed = true

			JOY_BUTTON_LEFT_SHOULDER:
				player.zoom_out_pressed = event.pressed

			JOY_BUTTON_RIGHT_SHOULDER:
				player.zoom_in_pressed = event.pressed

	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.is_action_pressed("join_confirm"):
				player.join_just_pressed = true

			if event.is_action_pressed("cancel_back"):
				player.cancel_just_pressed = true

			if event.is_action_pressed("pause_game"):
				player.pause_just_pressed = true


func _process(delta: float) -> void:
	_refresh_controller_list()
	_poll_desktop_and_controller_axes(delta)
	_update_mobile_touch_player(delta)


func begin_frame() -> void:
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


func assign_team(player_index: int, team_id: int) -> void:
	var player: PlayerState = get_player(player_index)
	if player == null:
		return

	player.team_id = team_id
	player_team_changed.emit(player_index, team_id)


func join_connected_controllers(max_total_players: int = MAX_SPLIT_SCREEN_PLAYERS) -> void:
	var joypads: Array[int] = Input.get_connected_joypads()

	for device_id in joypads:
		if _players.size() >= max_total_players:
			return

		if _get_player_by_device(device_id) == null:
			_register_device_if_needed(device_id)


func _poll_desktop_and_controller_axes(delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	for player in _players:
		if player.is_touch:
			continue

		if player.is_keyboard_mouse:
			player.camera_pan = Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
			player.pointer_screen = viewport.get_mouse_position()

			if Input.is_action_just_pressed("pause_game"):
				player.pause_just_pressed = true

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

		player.zoom_delta = 0.0

		if player.zoom_in_pressed:
			player.zoom_delta += 1.0

		if player.zoom_out_pressed:
			player.zoom_delta -= 1.0


func _handle_mobile_event(event: InputEvent) -> void:
	_register_device_if_needed(TOUCH_DEVICE_ID, false, true)

	var player: PlayerState = _get_player_by_device(TOUCH_DEVICE_ID)
	if player == null:
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event, player)

	elif event is InputEventScreenDrag:
		_handle_screen_drag(event, player)

	elif event is InputEventMagnifyGesture:
		if event.factor > 1.0:
			player.zoom_delta += 1.0
		elif event.factor < 1.0:
			player.zoom_delta -= 1.0


func _handle_screen_touch(event: InputEventScreenTouch, player: PlayerState) -> void:
	player.pointer_screen = event.position

	if event.pressed:
		_active_touches[event.index] = event.position

		if _active_touches.size() == 1:
			_primary_touch_index = event.index
			_touch_down_pos = event.position
			_touch_down_seconds = 0.0
			_touch_moved_too_far = false
			_touch_long_press_fired = false

		elif _active_touches.size() == 2:
			_last_touch_centroid = _get_touch_centroid()
			_last_pinch_distance = _get_touch_distance()

	else:
		if _active_touches.has(event.index):
			_active_touches.erase(event.index)

		if event.index == _primary_touch_index:
			var tap_distance: float = _touch_down_pos.distance_to(event.position)

			if not _touch_long_press_fired and tap_distance <= touch_tap_max_distance:
				_apply_press_release(player, true, true)
				_apply_press_release(player, true, false)

			_primary_touch_index = -1
			_touch_down_seconds = 0.0
			_touch_moved_too_far = false
			_touch_long_press_fired = false

		if _active_touches.size() == 1:
			var remaining_indexes: Array = _active_touches.keys()
			_primary_touch_index = int(remaining_indexes[0])
			_touch_down_pos = _active_touches[_primary_touch_index]
			_touch_down_seconds = 0.0
			_touch_moved_too_far = false
			_touch_long_press_fired = false

		if _active_touches.size() < 2:
			_last_pinch_distance = 0.0


func _handle_screen_drag(event: InputEventScreenDrag, player: PlayerState) -> void:
	if not _active_touches.has(event.index):
		return

	_active_touches[event.index] = event.position
	player.pointer_screen = event.position

	if _active_touches.size() == 1 and event.index == _primary_touch_index:
		if _touch_down_pos.distance_to(event.position) > touch_tap_max_distance:
			_touch_moved_too_far = true

	elif _active_touches.size() >= 2:
		var centroid: Vector2 = _get_touch_centroid()

		if _last_touch_centroid != Vector2.ZERO:
			var drag_delta: Vector2 = centroid - _last_touch_centroid
			var pan_vector: Vector2 = -drag_delta / max(touch_pan_pixels_for_full_speed, 1.0)

			if pan_vector.length_squared() > 1.0:
				pan_vector = pan_vector.normalized()

			player.camera_pan = pan_vector
			_mobile_pan_decay = 0.08

		_last_touch_centroid = centroid

		var pinch_distance: float = _get_touch_distance()
		if _last_pinch_distance > 0.0:
			var pinch_delta: float = pinch_distance - _last_pinch_distance

			if abs(pinch_delta) >= touch_pinch_pixels_per_zoom_step:
				player.zoom_delta += sign(pinch_delta)
				_last_pinch_distance = pinch_distance
		else:
			_last_pinch_distance = pinch_distance


func _update_mobile_touch_player(delta: float) -> void:
	var player: PlayerState = _get_player_by_device(TOUCH_DEVICE_ID)
	if player == null:
		return

	if _mobile_pan_decay > 0.0:
		_mobile_pan_decay -= delta
	else:
		player.camera_pan = Vector2.ZERO

	if _primary_touch_index == -1:
		return

	if _active_touches.size() != 1:
		return

	if _touch_moved_too_far:
		return

	if _touch_long_press_fired:
		return

	_touch_down_seconds += delta

	if _touch_down_seconds >= touch_long_press_seconds:
		_touch_long_press_fired = true
		player.pointer_screen = _active_touches.get(_primary_touch_index, player.pointer_screen)
		_apply_press_release(player, false, true)
		_apply_press_release(player, false, false)


func _get_touch_centroid() -> Vector2:
	if _active_touches.is_empty():
		return Vector2.ZERO

	var total := Vector2.ZERO

	for pos in _active_touches.values():
		total += pos

	return total / float(_active_touches.size())


func _get_touch_distance() -> float:
	if _active_touches.size() < 2:
		return 0.0

	var positions: Array = _active_touches.values()
	var a: Vector2 = positions[0]
	var b: Vector2 = positions[1]

	return a.distance_to(b)


func _refresh_keyboard_mouse_player() -> void:
	if not allow_keyboard_mouse_player:
		return

	if _get_player_by_device(KEYBOARD_MOUSE_DEVICE_ID) != null:
		return

	_register_device_if_needed(KEYBOARD_MOUSE_DEVICE_ID, true, false)


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


func _register_device_if_needed(device_id: int, force_keyboard_mouse: bool = false, force_touch: bool = false) -> void:
	if _get_player_by_device(device_id) != null:
		return

	if _players.size() >= MAX_LOCAL_PLAYERS:
		return

	var p := PlayerState.new()
	p.player_index = _players.size()
	p.device_id = device_id
	p.is_keyboard_mouse = force_keyboard_mouse or device_id == KEYBOARD_MOUSE_DEVICE_ID
	p.is_touch = force_touch or device_id == TOUCH_DEVICE_ID

	var viewport := get_viewport()
	if viewport != null:
		p.pointer_screen = viewport.get_visible_rect().size * 0.5

	_players.append(p)
	_device_to_player[device_id] = p.player_index

	player_joined.emit(p.player_index, device_id)


func _unregister_device(device_id: int) -> void:
	if not _device_to_player.has(device_id):
		return

	if device_id == KEYBOARD_MOUSE_DEVICE_ID:
		return

	if device_id == TOUCH_DEVICE_ID:
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
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_BACK

	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action_pressed("leave_local_player")

	return false
