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

var hud_controller: HUDController = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

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

	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)

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
	var panel_size := Vector2(360.0, 180.0)
	custom_minimum_size = panel_size

	if get_parent() is Control:
		var parent_control: Control = get_parent()
		position = (parent_control.size - panel_size) * 0.5


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
