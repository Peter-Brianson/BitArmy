class_name InputRouter
extends Node

signal player_joined(player_index: int, device_id: int)
signal player_left(player_index: int, device_id: int)
signal player_team_changed(player_index: int, team_id: int)

const KEYBOARD_MOUSE_DEVICE_ID := -100
const MAX_LOCAL_PLAYERS := 8

class PlayerState:
	var player_index: int = -1
	var device_id: int = -1
	var team_id: int = -1

	var is_keyboard_mouse: bool = false

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

var _players: Array[PlayerState] = []
var _device_to_player: Dictionary = {}
var _mobile: bool = false
var _desktop_like: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mobile = OS.has_feature("mobile")
	_desktop_like = OS.has_feature("desktop") or OS.has_feature("editor")
	_refresh_keyboard_mouse_player()
	_refresh_controller_list()


func _input(event: InputEvent) -> void:
	if _mobile:
		_handle_mobile_event(event)
		return

	var device_id: int = event.device

	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		device_id = KEYBOARD_MOUSE_DEVICE_ID

	# Join / leave handling.
	if _is_join_event(event):
		_register_device_if_needed(device_id)

	if _is_leave_event(event):
		_unregister_device(device_id)

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
	if not _mobile:
		_refresh_controller_list()
		_poll_desktop_and_controller_axes(delta)


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
	# Keep mobile direct-touch for now. The match-side bridge will interpret these.
	# No player join flow is needed here unless you later add hotseat/local mobile.
	pass


func _refresh_keyboard_mouse_player() -> void:
	if not allow_keyboard_mouse_player:
		return

	if _get_player_by_device(KEYBOARD_MOUSE_DEVICE_ID) != null:
		return

	_register_device_if_needed(KEYBOARD_MOUSE_DEVICE_ID, true)


func _refresh_controller_list() -> void:
	var joypads: Array[int] = Input.get_connected_joypads()

	for device_id in joypads:
		if _get_player_by_device(device_id) == null:
			# Do not auto-join controllers here. They still need a join press.
			pass

	var missing: Array[int] = []
	for player in _players:
		if player.is_keyboard_mouse:
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
	_device_to_player.erase(device_id)

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
		return event.pressed and event.button_index == JOY_BUTTON_B

	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action_pressed("cancel_back")

	return false
