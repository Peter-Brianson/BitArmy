class_name PauseMenuController
extends Control

@export var skirmish_scene_path: String = "res://scenes/ui/SkirmishMenu.tscn"
@export var versus_scene_path: String = "res://scenes/ui/P2PVersusMenu.tscn"
@export var options_panel_scene: PackedScene

@export var main_panel: Control
@export var options_host: Control

@export var resume_button: Button
@export var options_button: Button
@export var reset_button: Button
@export var back_button: Button

var options_panel_instance: OptionsPanelController = null


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

	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)

	_apply_layout()
	_refresh_button_states()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func toggle_pause_menu() -> void:
	if visible:
		close_pause_menu()
	else:
		open_pause_menu()


func open_pause_menu() -> void:
	visible = true
	_refresh_button_states()

	if _should_freeze_simulation():
		get_tree().paused = true

	if resume_button != null:
		resume_button.grab_focus()


func close_pause_menu() -> void:
	if options_panel_instance != null:
		options_panel_instance.visible = false

	visible = false

	if _should_freeze_simulation():
		get_tree().paused = false


func _on_resume_pressed() -> void:
	close_pause_menu()


func _on_options_pressed() -> void:
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
			push_error("PauseMenuController: options scene is not an OptionsPanelController.")
			return

		if options_panel_instance.has_signal("request_close"):
			options_panel_instance.request_close.connect(_close_options)

	if options_panel_instance != null:
		options_panel_instance.visible = true

		if options_panel_instance.has_method("sync_from_hud"):
			options_panel_instance.sync_from_hud()

		if options_panel_instance.has_method("focus_default"):
			options_panel_instance.focus_default()


func _close_options() -> void:
	if options_panel_instance != null:
		options_panel_instance.visible = false

	if resume_button != null:
		resume_button.grab_focus()


func _on_reset_pressed() -> void:
	# Do not allow local reset in online P2P.
	if GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP:
		return

	if get_tree().paused:
		get_tree().paused = false

	visible = false
	get_tree().reload_current_scene()


func _on_back_pressed() -> void:
	var target_scene_path: String = _get_return_scene_path()

	if get_tree().paused:
		get_tree().paused = false

	visible = false

	if GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP and multiplayer.multiplayer_peer != null:
		NetworkHub.disconnect_from_session()

	if target_scene_path != "":
		get_tree().change_scene_to_file(target_scene_path)


func _get_return_scene_path() -> String:
	# Preferred: menu scene stored before entering the match.
	if GameSession.has_meta("last_menu_scene_path"):
		var stored_path: String = str(GameSession.get_meta("last_menu_scene_path", ""))
		if stored_path != "":
			return stored_path

	# Fallback by mode.
	if GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP:
		return versus_scene_path

	return skirmish_scene_path


func _should_freeze_simulation() -> bool:
	return GameSession.match_mode != GameSession.MatchMode.ONLINE_PTP


func _refresh_button_states() -> void:
	if reset_button != null:
		reset_button.disabled = GameSession.match_mode == GameSession.MatchMode.ONLINE_PTP


func _apply_layout() -> void:
	if main_panel != null:
		var panel_size := Vector2(360.0, 320.0)
		main_panel.position = (size - panel_size) * 0.5
		main_panel.custom_minimum_size = panel_size

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
