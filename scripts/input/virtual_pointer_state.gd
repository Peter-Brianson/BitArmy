class_name VirtualPointerState
extends RefCounted

var player_index: int = -1
var team_id: int = -1
var device_id: int = -1

var screen_pos: Vector2 = Vector2.ZERO
var local_view_pos: Vector2 = Vector2.ZERO
var world_pos: Vector2 = Vector2.ZERO
var delta_screen: Vector2 = Vector2.ZERO

var camera_pan: Vector2 = Vector2.ZERO
var zoom_delta: float = 0.0

var primary_pressed: bool = false
var primary_just_pressed: bool = false
var primary_just_released: bool = false

var secondary_pressed: bool = false
var secondary_just_pressed: bool = false
var secondary_just_released: bool = false

var cancel_just_pressed: bool = false
var pause_just_pressed: bool = false

var handled_by_ui: bool = false
var handled_by_placement: bool = false
var handled_by_selection: bool = false


func setup_from_player(
	player,
	local_pos: Vector2,
	global_screen_pos: Vector2,
	world_position: Vector2
) -> void:
	player_index = int(player.player_index)
	team_id = int(player.team_id)
	device_id = int(player.device_id)

	local_view_pos = local_pos
	screen_pos = global_screen_pos
	world_pos = world_position
	delta_screen = player.pointer_delta

	camera_pan = player.camera_pan
	zoom_delta = player.zoom_delta

	primary_pressed = player.primary_pressed
	primary_just_pressed = player.primary_just_pressed
	primary_just_released = player.primary_just_released

	secondary_pressed = player.secondary_pressed
	secondary_just_pressed = player.secondary_just_pressed
	secondary_just_released = player.secondary_just_released

	cancel_just_pressed = player.cancel_just_pressed
	pause_just_pressed = player.pause_just_pressed

	handled_by_ui = false
	handled_by_placement = false
	handled_by_selection = false


func setup_runtime_buttons(
	primary_now: bool,
	primary_last: bool,
	secondary_now: bool,
	secondary_last: bool,
	cancel_now: bool,
	cancel_last: bool,
	pause_now: bool,
	pause_last: bool,
	controller_click_mode: bool = false
) -> void:
	if controller_click_mode:
		var primary_click: bool = primary_now and not primary_last
		var secondary_click: bool = secondary_now and not secondary_last

		primary_pressed = false
		primary_just_pressed = primary_click
		primary_just_released = primary_click

		secondary_pressed = false
		secondary_just_pressed = secondary_click
		secondary_just_released = secondary_click
	else:
		primary_pressed = primary_now
		primary_just_pressed = primary_now and not primary_last
		primary_just_released = (not primary_now) and primary_last

		secondary_pressed = secondary_now
		secondary_just_pressed = secondary_now and not secondary_last
		secondary_just_released = (not secondary_now) and secondary_last

	cancel_just_pressed = cancel_now and not cancel_last
	pause_just_pressed = pause_now and not pause_last


func was_primary_clicked() -> bool:
	return primary_just_pressed or primary_just_released


func clear_handlers() -> void:
	handled_by_ui = false
	handled_by_placement = false
	handled_by_selection = false


func is_consumed() -> bool:
	return handled_by_ui or handled_by_placement or handled_by_selection
