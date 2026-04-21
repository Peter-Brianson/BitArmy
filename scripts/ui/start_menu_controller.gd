class_name StartMenuController
extends Control

@export var skirmish_scene_path: String = "res://scenes/ui/SkirmishMenu.tscn"
@export var options_panel_scene: PackedScene

@export var center_panel: Control
@export var options_host: Control

@export var skirmish_button: Button
@export var options_button: Button
@export var quit_button: Button

var options_panel_instance: OptionsPanelController = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mouse_filter_fail_safe(self)

	if skirmish_button != null:
		skirmish_button.pressed.connect(_on_skirmish_pressed)
	if options_button != null:
		options_button.pressed.connect(_on_options_pressed)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)

	_apply_layout()

	if skirmish_button != null:
		skirmish_button.grab_focus()
	
	AudioHub.play_menu_music()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _on_skirmish_pressed() -> void:
	GameSession.reset_skirmish_defaults()
	get_tree().change_scene_to_file(skirmish_scene_path)


func _on_options_pressed() -> void:
	if options_panel_scene == null:
		push_error("StartMenuController: options_panel_scene is not assigned.")
		return

	if options_panel_instance == null:
		var instance: Node = options_panel_scene.instantiate()
		options_host.add_child(instance)
		options_panel_instance = instance as OptionsPanelController

		if options_panel_instance == null:
			push_error("StartMenuController: options scene is not an OptionsPanelController.")
			return

		var hud := get_tree().get_first_node_in_group("hud_controller")
		if hud != null and hud is HUDController:
			options_panel_instance.set_hud_controller(hud)

		options_panel_instance.request_close.connect(_close_options)

	options_panel_instance.visible = true
	options_panel_instance.sync_from_hud()
	options_panel_instance.focus_default()


func _close_options() -> void:
	if options_panel_instance != null:
		options_panel_instance.visible = false

	if skirmish_button != null:
		skirmish_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _apply_layout() -> void:
	if center_panel != null:
		var panel_size := Vector2(360.0, 260.0)
		center_panel.position = (size - panel_size) * 0.5
		center_panel.custom_minimum_size = panel_size

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
