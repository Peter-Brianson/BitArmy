class_name MatchEndController
extends Control

@export var skirmish_scene_path: String = "res://scenes/ui/SkirmishMenu.tscn"

@export var dimmer: ColorRect
@export var panel: Control
@export var result_label: Label
@export var restart_button: Button
@export var return_to_skirmish_button: Button

var is_showing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_apply_mouse_filter_fail_safe(self)

	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)

	if return_to_skirmish_button != null:
		return_to_skirmish_button.pressed.connect(_on_return_to_skirmish_pressed)

	_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()

func show_match_end(winner_name: String, winner_color: Color) -> void:
	is_showing = true
	visible = true

	if result_label != null:
		result_label.text = "%s Wins" % winner_name
		result_label.modulate = winner_color

	get_tree().paused = true
	AudioHub.play_victory_sfx()

	if restart_button != null:
		restart_button.grab_focus()


func show_draw() -> void:
	is_showing = true
	visible = true

	if result_label != null:
		result_label.text = "Draw"
		result_label.modulate = Color.WHITE

	get_tree().paused = true

	if restart_button != null:
		restart_button.grab_focus()


func reset_menu() -> void:
	is_showing = false
	visible = false

	if result_label != null:
		result_label.modulate = Color.WHITE

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_return_to_skirmish_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(skirmish_scene_path)


func _apply_layout() -> void:
	if dimmer != null:
		dimmer.anchor_left = 0.0
		dimmer.anchor_top = 0.0
		dimmer.anchor_right = 1.0
		dimmer.anchor_bottom = 1.0
		dimmer.offset_left = 0.0
		dimmer.offset_top = 0.0
		dimmer.offset_right = 0.0
		dimmer.offset_bottom = 0.0
		dimmer.color = Color(0, 0, 0, 0.5)

	if panel != null:
		var panel_size: Vector2 = Vector2(360.0, 180.0)
		panel.position = (size - panel_size) * 0.5
		panel.custom_minimum_size = panel_size


func _apply_mouse_filter_fail_safe(node: Node) -> void:
	for child in node.get_children():
		_apply_mouse_filter_fail_safe(child)

	if node is Control:
		var control: Control = node

		if control is BaseButton or control is Range:
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
