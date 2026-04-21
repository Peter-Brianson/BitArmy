class_name PauseMenuController
extends Control

@export var hud_controller: HUDController
@export var options_panel_scene: PackedScene

@export var dimmer: ColorRect
@export var panel: Control
@export var options_host: Control

@export var resume_button: Button
@export var options_button: Button
@export var reset_button: Button
@export var quit_button: Button

var options_panel_instance: OptionsPanelController = null

@export var skirmish_scene_path: String = "res://scenes/ui/SkirmishMenu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_apply_mouse_filter_fail_safe(self)

	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
	if options_button != null:
		options_button.pressed.connect(_on_options_pressed)
	if reset_button != null:
		reset_button.pressed.connect(_on_reset_pressed)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)

	_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if options_panel_instance != null and options_panel_instance.visible:
			_close_options()
		else:
			toggle_pause_menu()


func toggle_pause_menu() -> void:
	if visible:
		close_pause_menu()
	else:
		open_pause_menu()


func open_pause_menu() -> void:
	visible = true
	get_tree().paused = true

	if resume_button != null:
		resume_button.grab_focus()


func close_pause_menu() -> void:
	_close_options()
	visible = false
	get_tree().paused = false


func _on_resume_pressed() -> void:
	close_pause_menu()


func _on_options_pressed() -> void:
	_open_options()


func _on_reset_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(skirmish_scene_path)


func _open_options() -> void:
	if options_panel_scene == null:
		push_error("PauseMenuController: options_panel_scene is not assigned.")
		return

	if options_host == null:
		push_error("PauseMenuController: options_host is not assigned.")
		return

	if options_panel_instance == null:
		var instance: Node = options_panel_scene.instantiate()
		options_host.add_child(instance)
		options_panel_instance = instance as OptionsPanelController

		if options_panel_instance == null:
			push_error("PauseMenuController: instantiated options scene is not an OptionsPanelController.")
			return

		options_panel_instance.set_hud_controller(hud_controller)
		options_panel_instance.request_close.connect(_close_options)

	options_panel_instance.visible = true
	options_panel_instance.sync_from_hud()
	options_panel_instance.focus_default()


func _close_options() -> void:
	if options_panel_instance != null:
		options_panel_instance.visible = false

	if resume_button != null and visible:
		resume_button.grab_focus()


func _apply_layout() -> void:
	var viewport_size: Vector2 = size

	if dimmer != null:
		dimmer.anchor_left = 0.0
		dimmer.anchor_top = 0.0
		dimmer.anchor_right = 1.0
		dimmer.anchor_bottom = 1.0
		dimmer.offset_left = 0.0
		dimmer.offset_top = 0.0
		dimmer.offset_right = 0.0
		dimmer.offset_bottom = 0.0
		dimmer.color = Color(0, 0, 0, 0.45)

	if panel != null:
		var panel_size: Vector2 = Vector2(320.0, 260.0)
		panel.position = (viewport_size - panel_size) * 0.5
		panel.custom_minimum_size = panel_size

	if options_host != null:
		options_host.anchor_left = 0.0
		options_host.anchor_top = 0.0
		options_host.anchor_right = 1.0
		options_host.anchor_bottom = 1.0
		options_host.offset_left = 0.0
		options_host.offset_top = 0.0
		options_host.offset_right = 0.0
		options_host.offset_bottom = 0.0


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
