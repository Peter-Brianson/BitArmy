class_name SpatialHash2D
extends RefCounted

var cell_size: float = 128.0

var unit_cells: Dictionary = {}
var structure_cells: Dictionary = {}


func clear() -> void:
	unit_cells.clear()
	structure_cells.clear()


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / cell_size)),
		int(floor(world_pos.y / cell_size))
	)


func add_unit(unit_id: int, world_pos: Vector2) -> void:
	var cell: Vector2i = world_to_cell(world_pos)

	if not unit_cells.has(cell):
		unit_cells[cell] = []

	unit_cells[cell].append(unit_id)


func add_structure(structure_id: int, world_pos: Vector2, footprint_size: Vector2) -> void:
	var half: Vector2 = footprint_size * 0.5
	var min_cell: Vector2i = world_to_cell(world_pos - half)
	var max_cell: Vector2i = world_to_cell(world_pos + half)

	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)

			if not structure_cells.has(cell):
				structure_cells[cell] = []

			structure_cells[cell].append(structure_id)


func query_unit_ids_in_radius(center: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var seen: Dictionary = {}

	var min_cell: Vector2i = world_to_cell(center - Vector2(radius, radius))
	var max_cell: Vector2i = world_to_cell(center + Vector2(radius, radius))

	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)

			if not unit_cells.has(cell):
				continue

			for unit_id: int in unit_cells[cell]:
				if seen.has(unit_id):
					continue
				seen[unit_id] = true
				results.append(unit_id)

	return results


func query_structure_ids_in_radius(center: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var seen: Dictionary = {}

	var min_cell: Vector2i = world_to_cell(center - Vector2(radius, radius))
	var max_cell: Vector2i = world_to_cell(center + Vector2(radius, radius))

	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)

			if not structure_cells.has(cell):
				continue

			for structure_id: int in structure_cells[cell]:
				if seen.has(structure_id):
					continue
				seen[structure_id] = true
				results.append(structure_id)

	return results
