class_name SelectionUnderlay
extends Node2D

@export var selection_controller: SelectionController
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager


func _ready() -> void:
	z_as_relative = true
	z_index = 0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if selection_controller == null:
		return

	_draw_unit_selection()
	_draw_structure_selection()


func _draw_unit_selection() -> void:
	if unit_manager == null:
		return

	for unit_id: int in selection_controller.selected_unit_ids:
		var unit: UnitRuntime = unit_manager.get_unit(unit_id)
		if unit == null:
			continue
		if not unit.is_alive:
			continue

		var center: Vector2 = to_local(unit.position + Vector2(0.0, unit.stats.body_size.y * 0.30))
		var radius_x: float = max(unit.stats.radius + 6.0, 10.0)
		var radius_y: float = max(unit.stats.radius * 0.45, 4.0)

		_draw_oval_outline(center, radius_x + 1.5, radius_y + 1.0, Color(1, 1, 1, 0.25), 1.0)
		_draw_oval_outline(center, radius_x, radius_y, Color(1, 1, 1, 0.90), 2.0)


func _draw_structure_selection() -> void:
	if structure_manager == null:
		return

	var structure_id: int = selection_controller.selected_structure_id
	if structure_id == -1:
		return

	var structure: StructureRuntime = structure_manager.get_structure(structure_id)
	if structure == null:
		return
	if not structure.is_alive:
		return

	var rect := Rect2(
		to_local(structure.position - structure.stats.footprint_size * 0.5),
		structure.stats.footprint_size
	)

	draw_rect(rect.grow(2.0), Color(1, 1, 1, 0.25), false, 1.0)
	draw_rect(rect, Color(1, 1, 1, 0.95), false, 2.0)

	var local_center: Vector2 = to_local(structure.position)
	var local_rally: Vector2 = to_local(structure.rally_point)

	draw_line(local_center, local_rally, Color(1, 1, 1, 0.70), 2.0)

	# Rally point ring
	draw_arc(
		local_rally,
		10.0,
		0.0,
		TAU,
		24,
		Color(1, 1, 1, 0.95),
		2.0
	)

	draw_circle(local_rally, 2.5, Color(1, 1, 1, 0.95))

	# Rally direction tick
	var dir: Vector2 = structure.rally_point - structure.position
	if dir.length_squared() <= 0.001:
		dir = Vector2.DOWN
	else:
		dir = dir.normalized()

	_draw_rally_direction_tick(local_rally, dir)

func _draw_rally_direction_tick(center: Vector2, dir: Vector2) -> void:
	var tip: Vector2 = center + dir * 14.0
	var base: Vector2 = center + dir * 7.0
	var side: Vector2 = Vector2(-dir.y, dir.x)

	var left: Vector2 = base + side * 4.0
	var right: Vector2 = base - side * 4.0

	draw_line(base, tip, Color(1, 1, 1, 0.95), 2.0)
	draw_line(left, tip, Color(1, 1, 1, 0.95), 2.0)
	draw_line(right, tip, Color(1, 1, 1, 0.95), 2.0)

func _draw_oval_outline(center: Vector2, radius_x: float, radius_y: float, color: Color, width: float = 2.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 32

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU

		var x: float = cos(angle) * radius_x
		var y: float = sin(angle) * radius_y

		points.append(center + Vector2(x, y))

	draw_polyline(points, color, width)
