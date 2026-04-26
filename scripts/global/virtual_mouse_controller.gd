class_name VirtualMouseController
extends CanvasLayer

@export var primary_player_index: int = 0

@export_group("Cursor Art")
@export var cursor_texture: Texture2D
@export var cursor_size: Vector2 = Vector2(8.0, 8.0)
@export var cursor_hotspot: Vector2 = Vector2(4.0, 4.0)
@export var cursor_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var cursor_layer: int = 4096
@export var use_nearest_filter: bool = true

@export_group("Visibility")
@export var show_for_keyboard_mouse: bool = true
@export var show_for_controller: bool = true
@export var hide_when_split_screen_active: bool = true

@export_group("OS Mouse")
@export var hide_os_mouse_when_virtual_cursor_active: bool = true
@export var debug_show_os_mouse: bool = false
@export var restore_mouse_visible_on_exit: bool = true

@export_group("Controller Menu Mouse")
@export var warp_os_mouse_for_controller_menus: bool = true
@export var emit_controller_mouse_events_on_menus: bool = true
@export var emit_mouse_events_in_match: bool = false

var _cursor: Control
var _last_screen_pos: Vector2 = Vector2.ZERO
var _last_motion_pushed_pos: Vector2 = Vector2.INF
var _last_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = cursor_layer
	_last_mouse_mode = Input.mouse_mode
	_build_cursor()

	var viewport := get_viewport()

	if viewport != null:
		_last_screen_pos = viewport.get_visible_rect().size * 0.5


func _exit_tree() -> void:
	if restore_mouse_visible_on_exit:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	if _cursor == null:
		_update_os_mouse_visibility(false)
		return

	var player = _get_primary_player()
	var screen_pos: Vector2 = _get_screen_pos_for_player(player)

	_last_screen_pos = screen_pos
	_cursor.position = screen_pos - cursor_hotspot

	var split_active: bool = _is_split_screen_active()
	var should_show_global_cursor: bool = _should_show_for_player(player, split_active)

	_cursor.visible = should_show_global_cursor

	# The virtual cursor is still active during split-screen, but split-screen draws
	# its own per-view cursors. So the global cursor hides, while the OS mouse
	# can still be hidden.
	var virtual_cursor_active: bool = should_show_global_cursor or split_active
	_update_os_mouse_visibility(virtual_cursor_active)

	if not should_show_global_cursor:
		return

	if player == null:
		return

	if player.is_keyboard_mouse:
		return

	if split_active:
		return

	var match_active: bool = _is_match_input_active()

	if match_active and not emit_mouse_events_in_match:
		return

	if warp_os_mouse_for_controller_menus:
		Input.warp_mouse(screen_pos)

	if emit_controller_mouse_events_on_menus:
		_push_controller_mouse_events(player, screen_pos)


func get_screen_position() -> Vector2:
	return _last_screen_pos


func set_cursor_texture(texture: Texture2D) -> void:
	cursor_texture = texture
	_build_cursor()


func refresh_cursor_art() -> void:
	_build_cursor()


func _build_cursor() -> void:
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null

	if cursor_texture != null:
		var texture_cursor := TextureRect.new()
		texture_cursor.texture = cursor_texture
		texture_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_cursor = texture_cursor
	else:
		var fallback_cursor := ColorRect.new()
		fallback_cursor.color = cursor_color
		_cursor = fallback_cursor

	_cursor.name = "VirtualMouseCursor"
	_cursor.size = cursor_size
	_cursor.custom_minimum_size = cursor_size
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.z_index = cursor_layer
	_cursor.visible = false
	_cursor.set_anchors_preset(Control.PRESET_TOP_LEFT)

	if use_nearest_filter:
		_cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	add_child(_cursor)


func _get_primary_player():
	if InputHub == null:
		return null

	return InputHub.get_player(primary_player_index)


func _get_screen_pos_for_player(player) -> Vector2:
	var viewport := get_viewport()

	if viewport == null:
		return _last_screen_pos

	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var screen_pos: Vector2 = _last_screen_pos

	if player == null:
		screen_pos = viewport.get_mouse_position()
	elif player.is_keyboard_mouse:
		screen_pos = viewport.get_mouse_position()
	else:
		screen_pos = player.pointer_screen

	screen_pos.x = clamp(screen_pos.x, 0.0, viewport_size.x)
	screen_pos.y = clamp(screen_pos.y, 0.0, viewport_size.y)

	return screen_pos


func _should_show_for_player(player, split_active: bool) -> bool:
	if hide_when_split_screen_active and split_active:
		return false

	if player == null:
		return show_for_keyboard_mouse

	if player.is_keyboard_mouse:
		return show_for_keyboard_mouse

	if player.is_touch:
		return false

	return show_for_controller


func _update_os_mouse_visibility(virtual_cursor_active: bool) -> void:
	if debug_show_os_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if not hide_os_mouse_when_virtual_cursor_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if virtual_cursor_active:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _is_match_input_active() -> bool:
	return get_tree().get_first_node_in_group("match_input_bridge") != null


func _is_split_screen_active() -> bool:
	for node in get_tree().get_nodes_in_group("local_split_screen_manager"):
		if node == null:
			continue

		if node.has_method("is_split_screen_active"):
			if bool(node.call("is_split_screen_active")):
				return true

		var active_variant = node.get("_split_active")

		if active_variant is bool and bool(active_variant):
			return true

	return false


func _push_controller_mouse_events(player, screen_pos: Vector2) -> void:
	var viewport := get_viewport()

	if viewport == null:
		return

	if _last_motion_pushed_pos == Vector2.INF:
		_last_motion_pushed_pos = screen_pos

	var relative: Vector2 = screen_pos - _last_motion_pushed_pos

	if relative.length_squared() > 0.001:
		var motion := InputEventMouseMotion.new()
		motion.position = screen_pos
		motion.global_position = screen_pos
		motion.relative = relative
		viewport.push_input(motion, true)
		_last_motion_pushed_pos = screen_pos

	if player.primary_just_pressed:
		_push_mouse_button(MOUSE_BUTTON_LEFT, true, screen_pos)

	if player.primary_just_released:
		_push_mouse_button(MOUSE_BUTTON_LEFT, false, screen_pos)

	if player.secondary_just_pressed:
		_push_mouse_button(MOUSE_BUTTON_RIGHT, true, screen_pos)

	if player.secondary_just_released:
		_push_mouse_button(MOUSE_BUTTON_RIGHT, false, screen_pos)


func _push_mouse_button(button_index: MouseButton, pressed: bool, screen_pos: Vector2) -> void:
	var viewport := get_viewport()

	if viewport == null:
		return

	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = screen_pos
	event.global_position = screen_pos

	viewport.push_input(event, true)
