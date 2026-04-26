class_name CameraPanController
extends Node2D

@export var camera: Camera2D

@export_group("World Bounds")
@export var world_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000)

@export_group("Pan")
@export var edge_margin: float = 24.0
@export var edge_scroll_speed: float = 650.0
@export var keyboard_scroll_speed: float = 650.0
@export var keyboard_pan_enabled: bool = true
@export var mouse_edge_pan_enabled: bool = false
@export var edge_pan_with_virtual_pointer: bool = false

@export_group("Zoom")
@export var zoom_step: float = 0.08
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var keyboard_zoom_enabled: bool = true
@export var mouse_wheel_zoom_enabled: bool = false

@export_group("Virtual Cursor")
@export var enable_virtual_cursor: bool = true
@export var virtual_cursor_visual: Control
@export var warp_os_mouse_for_virtual_pointer: bool = true
@export var virtual_cursor_hotspot: Vector2 = Vector2.ZERO
@export var auto_create_virtual_cursor_visual: bool = true
@export var generated_virtual_cursor_size: Vector2 = Vector2(8.0, 8.0)
@export var generated_virtual_cursor_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var generated_virtual_cursor_z_index: int = 4096
@export var virtual_pointer_is_primary: bool = true
@export var draw_virtual_cursor_visual: bool = false

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "camera_input"
const KEY_MOUSE_WHEEL_ZOOM := "mouse_wheel_zoom_enabled"
const KEY_MOUSE_EDGE_PAN := "mouse_edge_pan_enabled"

var external_camera_pan: Vector2 = Vector2.ZERO
var external_zoom_delta: float = 0.0

var _external_pointer_screen: Vector2 = Vector2.ZERO
var _has_external_pointer: bool = false

var suppress_mouse_camera_input: bool = false
var _queued_mouse_wheel_zoom: float = 0.0

var ui_mouse_block_rect: Rect2 = Rect2()
var use_ui_mouse_block_rect: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camera_pan_controller")

	_load_camera_input_settings()

	if camera == null:
		camera = get_node_or_null("Camera2D")

	if camera != null:
		camera.add_to_group("map_cull_camera")

	var viewport_size: Vector2 = get_viewport_rect().size
	_external_pointer_screen = viewport_size * 0.5

	if auto_create_virtual_cursor_visual:
		_ensure_virtual_cursor_visual()

	_update_virtual_cursor_visual()


func _process(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_pointer: Vector2 = _get_active_screen_pointer(viewport_size)

	var mouse_edge_pan: Vector2 = Vector2.ZERO
	var can_edge_pan: bool = mouse_edge_pan_enabled
	can_edge_pan = can_edge_pan and not suppress_mouse_camera_input
	can_edge_pan = can_edge_pan and not is_mouse_over_blocked_ui()

	if _has_external_pointer and not edge_pan_with_virtual_pointer:
		can_edge_pan = false

	if can_edge_pan:
		mouse_edge_pan = _get_edge_pan_vector(screen_pointer, viewport_size)

	var pan_dir: Vector2 = external_camera_pan + _get_keyboard_pan_vector() + mouse_edge_pan

	if pan_dir.length_squared() > 1.0:
		pan_dir = pan_dir.normalized()

	var speed: float = max(edge_scroll_speed, keyboard_scroll_speed)

	position += pan_dir * speed * delta
	position = _get_clamped_camera_position(position, viewport_size)

	_apply_zoom()
	_update_virtual_cursor_visual()

	external_camera_pan = Vector2.ZERO
	external_zoom_delta = 0.0

func _ensure_virtual_cursor_visual() -> void:
	if virtual_cursor_visual != null:
		return

	var layer := CanvasLayer.new()
	layer.name = "VirtualCursorCanvasLayer"
	layer.layer = generated_virtual_cursor_z_index
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var cursor := ColorRect.new()
	cursor.name = "VirtualCursor"
	cursor.size = generated_virtual_cursor_size
	cursor.custom_minimum_size = generated_virtual_cursor_size
	cursor.color = generated_virtual_cursor_color
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.z_index = generated_virtual_cursor_z_index
	cursor.visible = false
	cursor.set_anchors_preset(Control.PRESET_TOP_LEFT)

	layer.add_child(cursor)

	virtual_cursor_visual = cursor

	if virtual_cursor_hotspot == Vector2.ZERO:
		virtual_cursor_hotspot = generated_virtual_cursor_size * 0.5

func set_mouse_camera_options(enable_wheel_zoom: bool, enable_edge_pan: bool) -> void:
	mouse_wheel_zoom_enabled = enable_wheel_zoom
	mouse_edge_pan_enabled = enable_edge_pan


func _load_camera_input_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(SETTINGS_PATH)

	if err != OK:
		mouse_wheel_zoom_enabled = false
		mouse_edge_pan_enabled = false
		return

	mouse_wheel_zoom_enabled = bool(config.get_value(
		SETTINGS_SECTION,
		KEY_MOUSE_WHEEL_ZOOM,
		false
	))

	mouse_edge_pan_enabled = bool(config.get_value(
		SETTINGS_SECTION,
		KEY_MOUSE_EDGE_PAN,
		false
	))


func set_ui_mouse_block_rect(rect: Rect2) -> void:
	ui_mouse_block_rect = rect
	use_ui_mouse_block_rect = true


func clear_ui_mouse_block_rect() -> void:
	use_ui_mouse_block_rect = false
	ui_mouse_block_rect = Rect2()


func is_mouse_over_blocked_ui() -> bool:
	if not use_ui_mouse_block_rect:
		return false

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	return ui_mouse_block_rect.has_point(mouse_pos)


func _unhandled_input(event: InputEvent) -> void:
	if suppress_mouse_camera_input or is_mouse_over_blocked_ui():
		return

	if not mouse_wheel_zoom_enabled:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_queued_mouse_wheel_zoom += 1.0
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_queued_mouse_wheel_zoom -= 1.0
			get_viewport().set_input_as_handled()


func set_virtual_pointer_screen(screen_pos: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	_external_pointer_screen = screen_pos
	_external_pointer_screen.x = clamp(_external_pointer_screen.x, 0.0, viewport_size.x)
	_external_pointer_screen.y = clamp(_external_pointer_screen.y, 0.0, viewport_size.y)

	_has_external_pointer = true

	if warp_os_mouse_for_virtual_pointer:
		Input.warp_mouse(_external_pointer_screen)

	_update_virtual_cursor_visual()


func clear_virtual_pointer_override() -> void:
	_has_external_pointer = false
	_update_virtual_cursor_visual()


func center_on_world(world_pos: Vector2) -> void:
	position = _get_clamped_camera_position(world_pos, get_viewport_rect().size)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	if camera == null:
		return global_position

	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_delta: Vector2 = screen_pos - viewport_size * 0.5
	var safe_zoom: Vector2 = camera.zoom

	if safe_zoom.x <= 0.0:
		safe_zoom.x = 1.0

	if safe_zoom.y <= 0.0:
		safe_zoom.y = 1.0

	return camera.global_position + Vector2(
		screen_delta.x / safe_zoom.x,
		screen_delta.y / safe_zoom.y
	)


func world_to_screen(world_pos: Vector2) -> Vector2:
	if camera == null:
		return Vector2.ZERO

	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_zoom: Vector2 = camera.zoom

	if safe_zoom.x <= 0.0:
		safe_zoom.x = 1.0

	if safe_zoom.y <= 0.0:
		safe_zoom.y = 1.0

	var world_delta: Vector2 = world_pos - camera.global_position

	return viewport_size * 0.5 + Vector2(
		world_delta.x * safe_zoom.x,
		world_delta.y * safe_zoom.y
	)


func _apply_zoom() -> void:
	if camera == null:
		return

	var block_mouse_zoom: bool = suppress_mouse_camera_input or is_mouse_over_blocked_ui()
	var zoom_delta: float = external_zoom_delta

	if mouse_wheel_zoom_enabled and not block_mouse_zoom:
		zoom_delta += _queued_mouse_wheel_zoom

	if keyboard_zoom_enabled:
		if Input.is_action_just_pressed("zoom_in"):
			zoom_delta += 1.0

		if Input.is_action_just_pressed("zoom_out"):
			zoom_delta -= 1.0

	_queued_mouse_wheel_zoom = 0.0

	if zoom_delta == 0.0:
		return

	var new_zoom := camera.zoom + Vector2.ONE * (-zoom_delta * zoom_step)

	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)

	camera.zoom = new_zoom
	position = _get_clamped_camera_position(position, get_viewport_rect().size)


func _get_active_screen_pointer(viewport_size: Vector2) -> Vector2:
	if enable_virtual_cursor and virtual_pointer_is_primary and _has_external_pointer:
		return _external_pointer_screen

	if enable_virtual_cursor and _has_external_pointer:
		return _external_pointer_screen

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	mouse_pos.x = clamp(mouse_pos.x, 0.0, viewport_size.x)
	mouse_pos.y = clamp(mouse_pos.y, 0.0, viewport_size.y)

	return mouse_pos


func _get_keyboard_pan_vector() -> Vector2:
	if not keyboard_pan_enabled:
		return Vector2.ZERO

	return Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")


func _get_edge_pan_vector(pointer: Vector2, viewport_size: Vector2) -> Vector2:
	var dir := Vector2.ZERO

	if pointer.x <= edge_margin:
		dir.x -= 1.0
	elif pointer.x >= viewport_size.x - edge_margin:
		dir.x += 1.0

	if pointer.y <= edge_margin:
		dir.y -= 1.0
	elif pointer.y >= viewport_size.y - edge_margin:
		dir.y += 1.0

	return dir

func _update_virtual_cursor_visual() -> void:
	if virtual_cursor_visual == null:
		return

	virtual_cursor_visual.visible = (
		draw_virtual_cursor_visual
		and enable_virtual_cursor
		and _has_external_pointer
	)

	virtual_cursor_visual.position = _external_pointer_screen - virtual_cursor_hotspot

func _get_clamped_camera_position(target_pos: Vector2, viewport_size: Vector2) -> Vector2:
	if camera == null:
		return target_pos

	var safe_zoom: Vector2 = camera.zoom

	if safe_zoom.x <= 0.0:
		safe_zoom.x = 1.0

	if safe_zoom.y <= 0.0:
		safe_zoom.y = 1.0

	var half_extents := Vector2(
		(viewport_size.x / safe_zoom.x) * 0.5,
		(viewport_size.y / safe_zoom.y) * 0.5
	)

	var min_pos := world_rect.position + half_extents
	var max_pos := world_rect.position + world_rect.size - half_extents

	if max_pos.x < min_pos.x:
		var center_x: float = world_rect.position.x + world_rect.size.x * 0.5
		min_pos.x = center_x
		max_pos.x = center_x

	if max_pos.y < min_pos.y:
		var center_y: float = world_rect.position.y + world_rect.size.y * 0.5
		min_pos.y = center_y
		max_pos.y = center_y

	return Vector2(
		clamp(target_pos.x, min_pos.x, max_pos.x),
		clamp(target_pos.y, min_pos.y, max_pos.y)
	)
