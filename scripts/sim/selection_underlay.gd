class_name SelectionUnderlay
extends Node2D

@export var selection_controller: SelectionController
@export var unit_manager: UnitSimulationManager
@export var structure_manager: StructureSimulationManager

@export_group("Fallback Drawing")
@export var fallback_unit_outer_color: Color = Color(1, 1, 1, 0.25)
@export var fallback_unit_inner_color: Color = Color(1, 1, 1, 0.90)
@export var fallback_structure_outer_color: Color = Color(1, 1, 1, 0.25)
@export var fallback_structure_inner_color: Color = Color(1, 1, 1, 0.95)
@export var fallback_rally_color: Color = Color(1, 1, 1, 0.95)

@export_group("Rally Marker")
@export var rally_line_width: float = 2.0
@export var rally_dash_length: float = 4.0
@export var rally_gap_length: float = 6.0

# This makes the line begin farther away from the structure center.
# It uses the structure footprint plus this padding.
@export var rally_line_start_padding: float = 18.0

# This prevents tiny structures from starting the rally line too close.
@export var rally_line_min_start_distance: float = 34.0

# This keeps the dotted line from drawing through the rally marker sprite/flag.
@export var rally_line_end_padding: float = 14.0

@export var rally_marker_radius: float = 11.0
@export var rally_marker_pole_height: float = 22.0
@export var rally_marker_flag_width: float = 12.0
@export var rally_marker_flag_height: float = 8.0
@export var rally_marker_shadow_offset: Vector2 = Vector2(1.0, 1.0)
@export var rally_marker_shadow_color: Color = Color(0, 0, 0, 0.35)

@export_group("Rally Marker Sprite")
@export var rally_marker_texture: Texture2D
@export var rally_marker_texture_scale: float = 1.0
@export var rally_marker_texture_offset: Vector2 = Vector2.ZERO
@export var rally_marker_texture_modulate: Color = Color.WHITE
@export var rally_marker_texture_draw_shadow: bool = true


func _ready() -> void:
	z_as_relative = true
	z_index = -1


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

		if _draw_unit_selection_texture(unit):
			continue

		var center: Vector2 = to_local(unit.position + Vector2(0.0, unit.stats.body_size.y * 0.30))
		var radius_x: float = max(unit.stats.radius + 6.0, 10.0)
		var radius_y: float = max(unit.stats.radius * 0.45, 4.0)

		_draw_oval_outline(center, radius_x + 1.5, radius_y + 1.0, fallback_unit_outer_color, 1.0)
		_draw_oval_outline(center, radius_x, radius_y, fallback_unit_inner_color, 2.0)


func _draw_unit_selection_texture(unit: UnitRuntime) -> bool:
	if unit == null or unit.stats == null:
		return false

	var texture: Texture2D = unit.stats.selection_ring_texture

	if texture == null:
		return false

	var base_center: Vector2 = unit.position + Vector2(0.0, unit.stats.body_size.y * 0.30)
	var center: Vector2 = to_local(base_center + unit.stats.selection_ring_offset)
	var size: Vector2 = texture.get_size() * max(unit.stats.selection_ring_scale, 0.01)
	var rect := Rect2(center - size * 0.5, size)

	draw_texture_rect(texture, rect, false, unit.stats.selection_ring_color)
	return true


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

	if not _draw_structure_selection_texture(structure):
		var rect := Rect2(
			to_local(structure.position - structure.stats.footprint_size * 0.5),
			structure.stats.footprint_size
		)

		draw_rect(rect.grow(2.0), fallback_structure_outer_color, false, 1.0)
		draw_rect(rect, fallback_structure_inner_color, false, 2.0)

	if structure.stats != null and not structure.stats.show_rally_marker:
		return

	_draw_rally_marker(structure)


func _draw_structure_selection_texture(structure: StructureRuntime) -> bool:
	if structure == null or structure.stats == null:
		return false

	var texture: Texture2D = structure.stats.selection_ring_texture

	if texture == null:
		return false

	var center: Vector2 = to_local(structure.position + structure.stats.selection_ring_offset)
	var size: Vector2 = texture.get_size() * max(structure.stats.selection_ring_scale, 0.01)
	var rect := Rect2(center - size * 0.5, size)

	draw_texture_rect(texture, rect, false, structure.stats.selection_ring_color)
	return true


func _draw_rally_marker(structure: StructureRuntime) -> void:
	var local_center: Vector2 = to_local(structure.position)
	var local_rally: Vector2 = to_local(structure.rally_point)

	var delta: Vector2 = local_rally - local_center
	var distance: float = delta.length()

	if distance <= 0.001:
		_draw_rally_marker_at(local_rally)
		return

	var direction: Vector2 = delta / distance
	var line_start_distance: float = _get_rally_line_start_distance(structure)
	var line_start: Vector2 = local_center + direction * line_start_distance

	var line_color := Color(
		fallback_rally_color.r,
		fallback_rally_color.g,
		fallback_rally_color.b,
		fallback_rally_color.a * 0.75
	)

	var shadow_line_color := Color(
		rally_marker_shadow_color.r,
		rally_marker_shadow_color.g,
		rally_marker_shadow_color.b,
		rally_marker_shadow_color.a * 0.75
	)

	if line_start.distance_squared_to(local_rally) > 4.0:
		_draw_dashed_line(
			line_start + rally_marker_shadow_offset,
			local_rally + rally_marker_shadow_offset,
			shadow_line_color,
			rally_line_width,
			rally_dash_length,
			rally_gap_length,
			rally_line_end_padding
		)

		_draw_dashed_line(
			line_start,
			local_rally,
			line_color,
			rally_line_width,
			rally_dash_length,
			rally_gap_length,
			rally_line_end_padding
		)

	_draw_rally_marker_at(local_rally)


func _get_rally_line_start_distance(structure: StructureRuntime) -> float:
	if structure == null or structure.stats == null:
		return rally_line_min_start_distance

	var footprint_size: Vector2 = structure.stats.footprint_size
	var footprint_radius: float = max(footprint_size.x, footprint_size.y) * 0.5

	return max(footprint_radius + rally_line_start_padding, rally_line_min_start_distance)


func _draw_rally_marker_at(center: Vector2) -> void:
	if rally_marker_texture != null:
		_draw_rally_marker_texture(center)
		return

	_draw_rally_flag(center + rally_marker_shadow_offset, rally_marker_shadow_color)
	_draw_rally_flag(center, fallback_rally_color)


func _draw_rally_marker_texture(center: Vector2) -> void:
	var texture_size: Vector2 = rally_marker_texture.get_size() * max(rally_marker_texture_scale, 0.01)
	var draw_center: Vector2 = center + rally_marker_texture_offset
	var rect := Rect2(draw_center - texture_size * 0.5, texture_size)

	if rally_marker_texture_draw_shadow:
		var shadow_rect := Rect2(rect.position + rally_marker_shadow_offset, rect.size)
		draw_texture_rect(
			rally_marker_texture,
			shadow_rect,
			false,
			rally_marker_shadow_color
		)

	draw_texture_rect(
		rally_marker_texture,
		rect,
		false,
		rally_marker_texture_modulate
	)


func _draw_dashed_line(
	from_pos: Vector2,
	to_pos: Vector2,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float,
	end_padding: float
) -> void:
	var delta: Vector2 = to_pos - from_pos
	var total_length: float = delta.length()

	if total_length <= 0.001:
		return

	var direction: Vector2 = delta / total_length
	var drawable_length: float = max(total_length - end_padding, 0.0)

	if drawable_length <= 0.001:
		return

	var cursor: float = 0.0

	while cursor < drawable_length:
		var segment_start: Vector2 = from_pos + direction * cursor
		var segment_end: Vector2 = from_pos + direction * min(cursor + dash_length, drawable_length)

		draw_line(segment_start, segment_end, color, width)

		cursor += dash_length + gap_length


func _draw_rally_flag(center: Vector2, color: Color) -> void:
	var ring_width: float = rally_line_width
	var pole_base: Vector2 = center + Vector2(0.0, -1.0)
	var pole_top: Vector2 = center + Vector2(0.0, -rally_marker_pole_height)

	var flag_top: Vector2 = pole_top
	var flag_tip: Vector2 = pole_top + Vector2(rally_marker_flag_width, rally_marker_flag_height * 0.5)
	var flag_bottom: Vector2 = pole_top + Vector2(0.0, rally_marker_flag_height)

	var flag_points := PackedVector2Array([
		flag_top,
		flag_tip,
		flag_bottom
	])

	var flag_fill := Color(color.r, color.g, color.b, color.a * 0.35)

	draw_arc(center, rally_marker_radius, 0.0, TAU, 24, color, ring_width)
	draw_line(pole_base, pole_top, color, ring_width)
	draw_colored_polygon(flag_points, flag_fill)

	draw_line(flag_top, flag_tip, color, ring_width)
	draw_line(flag_tip, flag_bottom, color, ring_width)
	draw_line(flag_bottom, flag_top, color, ring_width)


func _draw_oval_outline(
	center: Vector2,
	radius_x: float,
	radius_y: float,
	color: Color,
	width: float = 2.0
) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 32

	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU
		var x: float = cos(angle) * radius_x
		var y: float = sin(angle) * radius_y

		points.append(center + Vector2(x, y))

	draw_polyline(points, color, width)
