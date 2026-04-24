class_name ChunkedGeneratedTileMap
extends Node2D

const GROUND_LAYER := 0
const DETAIL_LAYER := 1
const MAX_TEAM_SPAWNS := 8

@export_group("Generation Set")
@export var generation_set: MapGenerationSet

@export_group("World Size")
@export var world_size_pixels: Vector2 = Vector2(10000.0, 10000.0)
@export var chunk_size_tiles: int = 32
@export var spawn_margin_pixels: float = 900.0
@export var spawn_clear_radius_pixels: float = 280.0

@export_group("Seed")
@export var generation_seed: int = 0
@export var use_session_based_seed: bool = true

@export_group("Culling")
@export var tracked_camera_group: StringName = &"map_cull_camera"
@export var cull_margin_pixels: float = 700.0
@export var keep_alive_padding_chunks: int = 1
@export var update_interval: float = 0.15

@export_group("Scene Nodes")
@export var chunks_root_path: NodePath = ^"Chunks"
@export var spawn_points_path: NodePath = ^"TeamSpawnPoints"

@export_group("Runtime")
@export var auto_generate_on_ready: bool = false

@export_group("Debug")
@export var debug_chunks: bool = false

var _chunks_root: Node2D = null
var _spawn_points: Node2D = null
var _loaded_chunks: Dictionary = {}
var _generated_spawn_positions: Dictionary = {}
var _seed_value: int = 12345
var _tile_size: Vector2i = Vector2i(16, 16)
var _timer: float = 0.0
var _has_setup: bool = false


func _ready() -> void:
	if auto_generate_on_ready:
		generate_map()


func _process(delta: float) -> void:
	if not _has_setup:
		return

	_timer -= delta

	if _timer > 0.0:
		return

	_timer = update_interval
	_update_visible_chunks()


func generate_map(force: bool = false) -> void:
	if _has_setup and not force:
		return

	_resolve_nodes()

	if generation_set == null:
		push_error("ChunkedGeneratedTileMap: generation_set is missing.")
		return

	if generation_set.tile_set == null:
		push_error("ChunkedGeneratedTileMap: generation_set.tile_set is missing.")
		return

	if not generation_set.has_ground_tiles():
		push_error("ChunkedGeneratedTileMap: generation_set needs at least one ground tile.")
		return

	_tile_size = generation_set.tile_set.tile_size

	if _tile_size.x <= 0 or _tile_size.y <= 0:
		_tile_size = Vector2i(16, 16)

	_seed_value = _get_seed_value()
	_generated_spawn_positions.clear()
	_create_spawn_markers()

	_has_setup = true
	_update_visible_chunks()

	if debug_chunks:
		print("ChunkedGeneratedTileMap ready | seed=", _seed_value, " world=", world_size_pixels, " tile_size=", _tile_size)


func get_team_spawn_position(team_id: int, fallback_index: int = -1) -> Vector2:
	if _generated_spawn_positions.has(team_id):
		return _generated_spawn_positions[team_id]

	if fallback_index >= 0 and _generated_spawn_positions.has(fallback_index):
		return _generated_spawn_positions[fallback_index]

	return Vector2.INF


func _resolve_nodes() -> void:
	_chunks_root = get_node_or_null(chunks_root_path) as Node2D

	if _chunks_root == null:
		_chunks_root = Node2D.new()
		_chunks_root.name = "Chunks"
		add_child(_chunks_root)
		chunks_root_path = _chunks_root.get_path()

	_spawn_points = get_node_or_null(spawn_points_path) as Node2D

	if _spawn_points == null:
		_spawn_points = Node2D.new()
		_spawn_points.name = "TeamSpawnPoints"
		add_child(_spawn_points)
		spawn_points_path = _spawn_points.get_path()


func _get_seed_value() -> int:
	if generation_seed != 0:
		return abs(generation_seed)

	if use_session_based_seed:
		var session_text := "%s|%s|%d|%d|%d" % [
			GameSession.selected_map_path,
			generation_set.display_name,
			GameSession.team_count,
			int(world_size_pixels.x),
			int(world_size_pixels.y)
		]

		return abs(hash(session_text))

	return 12345


func _update_visible_chunks() -> void:
	var camera_rects: Array[Rect2] = _get_active_camera_rects()

	if camera_rects.is_empty():
		return

	var wanted_chunks: Dictionary = {}

	for rect in camera_rects:
		var expanded_rect := rect.grow(cull_margin_pixels)
		var min_chunk := _world_to_chunk(expanded_rect.position)
		var max_chunk := _world_to_chunk(expanded_rect.position + expanded_rect.size)

		min_chunk -= Vector2i(keep_alive_padding_chunks, keep_alive_padding_chunks)
		max_chunk += Vector2i(keep_alive_padding_chunks, keep_alive_padding_chunks)

		for cy in range(min_chunk.y, max_chunk.y + 1):
			for cx in range(min_chunk.x, max_chunk.x + 1):
				var chunk_coord := Vector2i(cx, cy)

				if not _chunk_overlaps_world(chunk_coord):
					continue

				wanted_chunks[chunk_coord] = true

				if not _loaded_chunks.has(chunk_coord):
					_load_chunk(chunk_coord)

	var chunks_to_remove: Array[Vector2i] = []

	for chunk_coord in _loaded_chunks.keys():
		if not wanted_chunks.has(chunk_coord):
			chunks_to_remove.append(chunk_coord)

	for chunk_coord in chunks_to_remove:
		_unload_chunk(chunk_coord)

	if debug_chunks:
		print("Map chunks loaded: ", _loaded_chunks.size())


func _get_active_camera_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []

	var cameras: Array[Node] = get_tree().get_nodes_in_group(tracked_camera_group)

	for node in cameras:
		if node is Camera2D:
			var camera := node as Camera2D

			if not camera.is_inside_tree():
				continue

			rects.append(_get_camera_world_rect(camera))

	if rects.is_empty():
		var viewport_camera := get_viewport().get_camera_2d()

		if viewport_camera != null:
			rects.append(_get_camera_world_rect(viewport_camera))

	return rects


func _get_camera_world_rect(camera: Camera2D) -> Rect2:
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	var zoom: Vector2 = camera.zoom

	if zoom.x <= 0.0:
		zoom.x = 1.0

	if zoom.y <= 0.0:
		zoom.y = 1.0

	var world_size := Vector2(
		viewport_size.x / zoom.x,
		viewport_size.y / zoom.y
	)

	return Rect2(camera.global_position - world_size * 0.5, world_size)


func _load_chunk(chunk_coord: Vector2i) -> void:
	if _chunks_root == null:
		return

	var tile_map := TileMap.new()
	tile_map.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	tile_map.tile_set = generation_set.tile_set

	while tile_map.get_layers_count() < 2:
		tile_map.add_layer(tile_map.get_layers_count())

	var chunk_origin_cell := chunk_coord * chunk_size_tiles
	var chunk_origin_world := _cell_to_world(chunk_origin_cell)

	tile_map.position = chunk_origin_world

	for local_y in range(chunk_size_tiles):
		for local_x in range(chunk_size_tiles):
			var local_cell := Vector2i(local_x, local_y)
			var world_cell := chunk_origin_cell + local_cell

			if not _cell_inside_world(world_cell):
				continue

			_set_cell_generated(tile_map, local_cell, world_cell)

	_chunks_root.add_child(tile_map)
	_loaded_chunks[chunk_coord] = tile_map


func _unload_chunk(chunk_coord: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_coord):
		return

	var node: Node = _loaded_chunks[chunk_coord]

	if node != null and is_instance_valid(node):
		node.queue_free()

	_loaded_chunks.erase(chunk_coord)


func _set_cell_generated(tile_map: TileMap, local_cell: Vector2i, world_cell: Vector2i) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _seed_value
	noise.frequency = generation_set.patch_noise_frequency

	var noise_value: float = noise.get_noise_2d(float(world_cell.x), float(world_cell.y))
	var is_spawn_clear: bool = _is_cell_in_spawn_clear_area(world_cell)

	if not is_spawn_clear and generation_set.has_patch_tiles() and noise_value >= generation_set.patch_noise_cutoff:
		tile_map.set_cell(
			GROUND_LAYER,
			local_cell,
			generation_set.patch_source_id,
			_pick_tile(generation_set.patch_tiles, world_cell, 11)
		)
	else:
		tile_map.set_cell(
			GROUND_LAYER,
			local_cell,
			generation_set.ground_source_id,
			_pick_tile(generation_set.ground_tiles, world_cell, 17)
		)

	if is_spawn_clear:
		tile_map.set_cell(DETAIL_LAYER, local_cell)
		return

	if generation_set.has_detail_tiles():
		var detail_roll: float = _cell_float(world_cell, 29)

		if detail_roll <= generation_set.detail_chance:
			tile_map.set_cell(
				DETAIL_LAYER,
				local_cell,
				generation_set.detail_source_id,
				_pick_tile(generation_set.detail_tiles, world_cell, 31)
			)


func _pick_tile(tiles: Array[Vector2i], world_cell: Vector2i, salt: int) -> Vector2i:
	if tiles.is_empty():
		return Vector2i.ZERO

	var index: int = _cell_hash(world_cell, salt) % tiles.size()
	return tiles[index]


func _cell_float(world_cell: Vector2i, salt: int) -> float:
	var value: int = _cell_hash(world_cell, salt) % 10000
	return float(value) / 10000.0


func _cell_hash(world_cell: Vector2i, salt: int) -> int:
	var text := "%d|%d|%d|%d" % [_seed_value, world_cell.x, world_cell.y, salt]
	return abs(hash(text))


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(_tile_size.x)),
		floori(world_position.y / float(_tile_size.y))
	)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x * _tile_size.x),
		float(cell.y * _tile_size.y)
	)


func _world_to_chunk(world_position: Vector2) -> Vector2i:
	var cell := _world_to_cell(world_position)

	return Vector2i(
		floori(float(cell.x) / float(chunk_size_tiles)),
		floori(float(cell.y) / float(chunk_size_tiles))
	)


func _chunk_overlaps_world(chunk_coord: Vector2i) -> bool:
	var chunk_min_cell := chunk_coord * chunk_size_tiles
	var chunk_max_cell := chunk_min_cell + Vector2i(chunk_size_tiles, chunk_size_tiles)

	var chunk_min_world := _cell_to_world(chunk_min_cell)
	var chunk_max_world := _cell_to_world(chunk_max_cell)

	var chunk_rect := Rect2(chunk_min_world, chunk_max_world - chunk_min_world)
	var world_rect := _get_world_rect()

	return chunk_rect.intersects(world_rect)


func _cell_inside_world(cell: Vector2i) -> bool:
	var world_position := _cell_to_world(cell)
	return _get_world_rect().has_point(world_position)


func _get_world_rect() -> Rect2:
	return Rect2(
		-world_size_pixels * 0.5,
		world_size_pixels
	)


func _create_spawn_markers() -> void:
	if _spawn_points == null:
		return

	for child in _spawn_points.get_children():
		child.queue_free()

	var spawn_positions := _get_spawn_positions()

	for i in range(spawn_positions.size()):
		var marker := Marker2D.new()
		marker.name = "TeamSpawn%02d" % (i + 1)
		marker.global_position = spawn_positions[i]
		_spawn_points.add_child(marker)

		_generated_spawn_positions[i] = spawn_positions[i]


func _get_spawn_positions() -> Array[Vector2]:
	var world_rect := _get_world_rect()

	var left := world_rect.position.x + spawn_margin_pixels
	var right := world_rect.position.x + world_rect.size.x - spawn_margin_pixels
	var top := world_rect.position.y + spawn_margin_pixels
	var bottom := world_rect.position.y + world_rect.size.y - spawn_margin_pixels
	var center := world_rect.position + world_rect.size * 0.5

	return [
		Vector2(left, center.y),       # Team 1
		Vector2(right, center.y),      # Team 2
		Vector2(center.x, top),        # Team 3
		Vector2(center.x, bottom),     # Team 4
		Vector2(left, bottom),         # Team 5
		Vector2(right, bottom),        # Team 6
		Vector2(right, top),           # Team 7
		Vector2(left, top)             # Team 8
	]


func _is_cell_in_spawn_clear_area(world_cell: Vector2i) -> bool:
	var cell_world_position := _cell_to_world(world_cell)
	var spawn_positions := _get_spawn_positions()

	for spawn_position in spawn_positions:
		if cell_world_position.distance_to(spawn_position) <= spawn_clear_radius_pixels:
			return true

	return false
