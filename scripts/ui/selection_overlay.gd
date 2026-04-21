class_name SelectionOverlay
extends Node2D

@export var selection_controller: SelectionController


func _ready() -> void:
	z_as_relative = false
	z_index = 100


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if selection_controller == null:
		return

	if selection_controller.is_left_dragging and selection_controller.is_drag_selecting:
		var rect_world: Rect2 = _get_normalized_world_rect(
			selection_controller.drag_start_world,
			selection_controller.drag_current_world
		)

		var rect_local := Rect2(
			to_local(rect_world.position),
			rect_world.size
		)

		draw_rect(rect_local, Color(1, 1, 1, 0.10), true)
		draw_rect(rect_local, Color(1, 1, 1, 0.85), false, 1.0)


func _get_normalized_world_rect(a: Vector2, b: Vector2) -> Rect2:
	var top_left := Vector2(min(a.x, b.x), min(a.y, b.y))
	var bottom_right := Vector2(max(a.x, b.x), max(a.y, b.y))
	return Rect2(top_left, bottom_right - top_left)
