class_name OptionsPanelController
extends PanelContainer

signal request_close
signal ui_scale_changed(value: float)

@export var title_label: Label
@export var ui_scale_label: Label
@export var ui_scale_slider: HSlider
@export var value_label: Label
@export var close_button: Button

@export var master_slider: HSlider
@export var music_slider: HSlider
@export var sfx_slider: HSlider

@export_group("Camera Mouse Options")
@export var mouse_wheel_zoom_check_box: CheckBox
@export var mouse_edge_pan_check_box: CheckBox

const SETTINGS_PATH := "user://settings.cfg"
const CAMERA_INPUT_SECTION := "camera_input"
const KEY_MOUSE_WHEEL_ZOOM := "mouse_wheel_zoom_enabled"
const KEY_MOUSE_EDGE_PAN := "mouse_edge_pan_enabled"

var hud_controller: HUDController = null

var mouse_wheel_zoom_enabled: bool = false
var mouse_edge_pan_enabled: bool = false

const KEY_CONTROLLER_CURSOR_SPEED := "controller_cursor_speed"
const KEY_CONTROLLER_CAMERA_PAN_SCALE := "controller_camera_pan_scale"

@export var controller_cursor_speed_slider: HSlider
@export var controller_pan_scale_slider: HSlider

var controller_cursor_speed: float = 360.0
var controller_camera_pan_scale: float = 0.45

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_create_camera_mouse_option_controls_if_missing()
	_load_camera_mouse_settings()

	_apply_mouse_filter_fail_safe(self)

	if ui_scale_slider != null:
		ui_scale_slider.min_value = 0.25
		ui_scale_slider.max_value = 1.50
		ui_scale_slider.step = 0.05
		ui_scale_slider.value_changed.connect(_on_ui_scale_changed)

	if master_slider != null:
		master_slider.min_value = 0.0
		master_slider.max_value = 1.0
		master_slider.step = 0.01
		master_slider.value = _get_bus_linear("Master")
		master_slider.value_changed.connect(_on_master_volume_changed)

	if music_slider != null:
		music_slider.min_value = 0.0
		music_slider.max_value = 1.0
		music_slider.step = 0.01
		music_slider.value = _get_bus_linear("Music")
		music_slider.value_changed.connect(_on_music_volume_changed)

	if sfx_slider != null:
		sfx_slider.min_value = 0.0
		sfx_slider.max_value = 1.0
		sfx_slider.step = 0.01
		sfx_slider.value = _get_bus_linear("SFX")
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	if mouse_wheel_zoom_check_box != null:
		mouse_wheel_zoom_check_box.button_pressed = mouse_wheel_zoom_enabled
		mouse_wheel_zoom_check_box.toggled.connect(_on_mouse_wheel_zoom_toggled)

	if mouse_edge_pan_check_box != null:
		mouse_edge_pan_check_box.button_pressed = mouse_edge_pan_enabled
		mouse_edge_pan_check_box.toggled.connect(_on_mouse_edge_pan_toggled)


	if controller_cursor_speed_slider != null:
		controller_cursor_speed_slider.min_value = 120.0
		controller_cursor_speed_slider.max_value = 900.0
		controller_cursor_speed_slider.step = 10.0
		controller_cursor_speed_slider.value = controller_cursor_speed
		controller_cursor_speed_slider.value_changed.connect(_on_controller_cursor_speed_changed)

	if controller_pan_scale_slider != null:
		controller_pan_scale_slider.min_value = 0.15
		controller_pan_scale_slider.max_value = 1.0
		controller_pan_scale_slider.step = 0.05
		controller_pan_scale_slider.value = controller_camera_pan_scale
		controller_pan_scale_slider.value_changed.connect(_on_controller_pan_scale_changed)


	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)

	_apply_camera_mouse_settings_to_active_controllers()
	_apply_layout()
	sync_from_hud()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func set_hud_controller(value: HUDController) -> void:
	hud_controller = value
	sync_from_hud()


func sync_from_hud() -> void:
	if ui_scale_label != null:
		ui_scale_label.text = "HUD Size"

	if title_label != null:
		title_label.text = "Options"

	if hud_controller != null and ui_scale_slider != null:
		ui_scale_slider.value = hud_controller.ui_scale

	if mouse_wheel_zoom_check_box != null:
		mouse_wheel_zoom_check_box.button_pressed = mouse_wheel_zoom_enabled

	if mouse_edge_pan_check_box != null:
		mouse_edge_pan_check_box.button_pressed = mouse_edge_pan_enabled

	_refresh_value_label()


func focus_default() -> void:
	if ui_scale_slider != null:
		ui_scale_slider.grab_focus()


func _on_ui_scale_changed(value: float) -> void:
	_refresh_value_label()

	if hud_controller != null:
		hud_controller.set_ui_scale(value)

	ui_scale_changed.emit(value)


func _on_close_pressed() -> void:
	request_close.emit()


func _refresh_value_label() -> void:
	if value_label != null and ui_scale_slider != null:
		value_label.text = "%.2f" % ui_scale_slider.value


func _apply_layout() -> void:
	var panel_size := Vector2(380.0, 300.0)

	custom_minimum_size = panel_size

	if get_parent() is Control:
		var parent_control: Control = get_parent()
		position = (parent_control.size - panel_size) * 0.5


func _create_camera_mouse_option_controls_if_missing() -> void:
	if mouse_wheel_zoom_check_box != null and mouse_edge_pan_check_box != null:
		return

	var vbox := get_node_or_null("VBoxContainer") as VBoxContainer

	if vbox == null:
		return

	var section_label := Label.new()
	section_label.name = "CameraMouseLabel"
	section_label.text = "Mouse Camera"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(section_label)
	_move_before_close_button(section_label)

	if mouse_wheel_zoom_check_box == null:
		mouse_wheel_zoom_check_box = CheckBox.new()
		mouse_wheel_zoom_check_box.name = "MouseWheelZoomCheckBox"
		mouse_wheel_zoom_check_box.text = "Mouse Wheel Zoom"
		mouse_wheel_zoom_check_box.tooltip_text = "Allow the mouse scroll wheel to zoom the battle camera."
		vbox.add_child(mouse_wheel_zoom_check_box)
		_move_before_close_button(mouse_wheel_zoom_check_box)

	if mouse_edge_pan_check_box == null:
		mouse_edge_pan_check_box = CheckBox.new()
		mouse_edge_pan_check_box.name = "MouseEdgePanCheckBox"
		mouse_edge_pan_check_box.text = "Mouse Edge Pan"
		mouse_edge_pan_check_box.tooltip_text = "Allow moving the mouse to the screen edge to pan the battle camera."
		vbox.add_child(mouse_edge_pan_check_box)
		_move_before_close_button(mouse_edge_pan_check_box)


func _move_before_close_button(node: Node) -> void:
	if close_button == null:
		return

	var parent := close_button.get_parent()

	if parent == null:
		return

	if node.get_parent() != parent:
		return

	parent.move_child(node, close_button.get_index())


func _load_camera_mouse_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(SETTINGS_PATH)

	if err != OK:
		mouse_wheel_zoom_enabled = false
		mouse_edge_pan_enabled = false
		return

	mouse_wheel_zoom_enabled = bool(config.get_value(
		CAMERA_INPUT_SECTION,
		KEY_MOUSE_WHEEL_ZOOM,
		false
	))

	mouse_edge_pan_enabled = bool(config.get_value(
		CAMERA_INPUT_SECTION,
		KEY_MOUSE_EDGE_PAN,
		false
	))
	controller_cursor_speed = float(config.get_value(
	CAMERA_INPUT_SECTION,
	KEY_CONTROLLER_CURSOR_SPEED,
	360.0
	))

	controller_camera_pan_scale = float(config.get_value(
		CAMERA_INPUT_SECTION,
		KEY_CONTROLLER_CAMERA_PAN_SCALE,
		0.45
	))


func _save_camera_mouse_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)

	config.set_value(
		CAMERA_INPUT_SECTION,
		KEY_MOUSE_WHEEL_ZOOM,
		mouse_wheel_zoom_enabled
	)

	config.set_value(
		CAMERA_INPUT_SECTION,
		KEY_MOUSE_EDGE_PAN,
		mouse_edge_pan_enabled
	)
	config.set_value(
	CAMERA_INPUT_SECTION,
	KEY_CONTROLLER_CURSOR_SPEED,
	controller_cursor_speed
	)

	config.set_value(
		CAMERA_INPUT_SECTION,
		KEY_CONTROLLER_CAMERA_PAN_SCALE,
		controller_camera_pan_scale
	)

	var err: Error = config.save(SETTINGS_PATH)

	if err != OK:
		push_warning("OptionsPanelController: failed to save camera mouse settings.")


func _on_controller_cursor_speed_changed(value: float) -> void:
	controller_cursor_speed = value
	_save_camera_mouse_settings()
	_apply_input_router_settings()


func _on_controller_pan_scale_changed(value: float) -> void:
	controller_camera_pan_scale = value
	_save_camera_mouse_settings()
	_apply_input_router_settings()


func _apply_input_router_settings() -> void:
	if InputHub == null:
		return

	InputHub.controller_cursor_speed = controller_cursor_speed

	if "controller_camera_pan_scale" in InputHub:
		InputHub.controller_camera_pan_scale = controller_camera_pan_scale

func _on_mouse_wheel_zoom_toggled(enabled: bool) -> void:
	mouse_wheel_zoom_enabled = enabled
	_save_camera_mouse_settings()
	_apply_camera_mouse_settings_to_active_controllers()


func _on_mouse_edge_pan_toggled(enabled: bool) -> void:
	mouse_edge_pan_enabled = enabled
	_save_camera_mouse_settings()
	_apply_camera_mouse_settings_to_active_controllers()


func _apply_camera_mouse_settings_to_active_controllers() -> void:
	var applied_count: int = 0

	for node in get_tree().get_nodes_in_group("camera_pan_controller"):
		if node is CameraPanController:
			var controller := node as CameraPanController
			controller.set_mouse_camera_options(
				mouse_wheel_zoom_enabled,
				mouse_edge_pan_enabled
			)
			applied_count += 1

	if applied_count > 0:
		return

	_apply_camera_mouse_settings_to_tree(get_tree().root)


func _apply_camera_mouse_settings_to_tree(node: Node) -> void:
	if node is CameraPanController:
		var controller := node as CameraPanController
		controller.set_mouse_camera_options(
			mouse_wheel_zoom_enabled,
			mouse_edge_pan_enabled
		)

	for child in node.get_children():
		_apply_camera_mouse_settings_to_tree(child)


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume_from_slider("Master", value)


func _on_music_volume_changed(value: float) -> void:
	_set_bus_volume_from_slider("Music", value)


func _on_sfx_volume_changed(value: float) -> void:
	_set_bus_volume_from_slider("SFX", value)


func _get_bus_linear(bus_name: String) -> float:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)

	if bus_idx == -1:
		return 1.0

	return db_to_linear(AudioServer.get_bus_volume_db(bus_idx))


func _set_bus_volume_from_slider(bus_name: String, value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)

	if bus_idx == -1:
		return

	# Avoid -INF edge weirdness while still allowing "almost silent".
	var safe_value: float = max(value, 0.0001)

	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(safe_value))
