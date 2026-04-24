class_name ChunkedGeneratedTileMap
extends Node2D

const GROUND_LAYER := 0
const DETAIL_LAYER := 1
const MAX_TEAM_SPAWNS := 8

@export_group("Generation Set")
@export var generation_set: MapGenerationSet

@export_group("World Size")
@export var world_size_pixels: Vector2 = Vector2(10000.0, 10000.0)
@export var chunk_size_tiles: int = 64
@export var spawn_margin_pixels: float = 1400.0
@export var spawn_clear_radius_pixels: float = 280.0

@export_group("Seed")
@export var generation_seed: int = 0
@export var use_session_based_seed: bool = true

@export_group("Culling")
@export var tracked_camera_group: StringName = &"map_cull_camera"
@export var cull_margin_pixels: float = 350.0
@export var keep_alive_padding_chunks: int = 0
@export var update_interval: float = 0.25
@export var max_chunks_built_per_frame: int = 1
@export var max_chunks_built_on_refresh: int = 4

@export_group("Fog / Reveal")
@export var use_reveal_based_chunk_loading: bool = true
@export var fog_background_color: Color = Color(0.07, 0.08, 0.055, 1.0)
@export var reveal_radius_pixels: float = 900.0
@export var structure_reveal_radius_pixels: float = 1100.0
@export var base_reveal_radius_pixels: float = 1600.0
@export var base_pin_radius_chunks: int = 1
@export var fog_background_z_index: int = -100

@export_group("Scene Nodes")
@export var chunks_root_path: NodePath = ^"Chunks"
@export var spawn_points_path: NodePath = ^"TeamSpawnPoints"

@export_group("Runtime")
@export var auto_generate_on_ready: bool = true

@export_group("Debug")
@export var debug_chunks: bool = false

var _chunks_root: Node2D = null
var _spawn_points: Node2D = null
var _fog_background: Polygon2D = null

var _loaded_chunks: Dictionary = {}
var _pending_chunk_builds: Array[Vector2i] = []
var _pending_chunk_lookup: Dictionary = {}
var _pinned_chunks: Dictionary = {}
var _generated_spawn_positions: Dictionary = {}

var _dynamic_reveal_points: Array[Vector2] = []
var _structure_reveal_points: Array[Vector2] = []
var _base_reveal_points: Array[Vector2] = []

var _seed_value: int = 12345
var _tile_size: Vector2i = Vector2i(16, 16)
var _world_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000)
var _cached_spawn_positions: Array[Vector2] = []
var _patch_noise: FastNoiseLite = FastNoiseLite.new()

var _timer: float = 0.0
var _has_setup: bool = false
var _last_focus_chunk: Vector2i = Vector2i.ZERO
var _last_debug_chunk_count: int = -1


func _ready() -> void:
	if auto_generate_on_ready:
		generate_map()


func _process(delta: float) -> void:
	if not _has_setup:
		return

	_timer -= delta

	if _timer <= 0.0:
		_timer = update_interval
		_update_visible_chunks()

	_process_pending_chunk_builds(max_chunks_built_per_frame)


func generate_map(force: bool = false) -> void:
	if _has_setup and not force:
		return

	if force:
		_clear_all_chunks()
		_pinned_chunks.clear()
		_dynamic_reveal_points.clear()
		_structure_reveal_points.clear()
		_base_reveal_points.clear()

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

	if not generation_set.tile_set.has_source(generation_set.ground_source_id):
		push_error("ChunkedGeneratedTileMap: ground_source_id %d does not exist in the assigned TileSet." % generation_set.ground_source_id)
		return

	if generation_set.has_patch_tiles() and not generation_set.tile_set.has_source(generation_set.patch_source_id):
		push_error("ChunkedGeneratedTileMap: patch_source_id %d does not exist in the assigned TileSet." % generation_set.patch_source_id)
		return

	if generation_set.has_detail_tiles() and not generation_set.tile_set.has_source(generation_set.detail_source_id):
		push_error("ChunkedGeneratedTileMap: detail_source_id %d does not exist in the assigned TileSet." % generation_set.detail_source_id)
		return

	_tile_size = generation_set.tile_set.tile_size

	if _tile_size.x <= 0 or _tile_size.y <= 0:
		_tile_size = Vector2i(16, 16)

	_seed_value = _get_seed_value()
	_world_rect = _get_world_rect()
	_cached_spawn_positions = _calculate_spawn_positions()

	_patch_noise.seed = _seed_value
	_patch_noise.frequency = generation_set.patch_noise_frequency

	_generated_spawn_positions.clear()
	_create_or_update_fog_background()
	_create_spawn_markers()

	_has_setup = true
	_timer = 0.0

	if debug_chunks:
		print(
			"ChunkedGeneratedTileMap ready | seed=",
			_seed_value,
			" world=",
			world_size_pixels,
			" tile_size=",
			_tile_size
		)


func refresh_visible_chunks() -> void:
	if not _has_setup:
		return

	_update_visible_chunks()
	_process_pending_chunk_builds(max_chunks_built_on_refresh)


func get_team_spawn_position(team_id: int, fallback_index: int = -1) -> Vector2:
	if _generated_spawn_positions.has(team_id):
		return _generated_spawn_positions[team_id]

	if fallback_index >= 0 and _generated_spawn_positions.has(fallback_index):
		return _generated_spawn_positions[fallback_index]

	return Vector2.INF


func set_dynamic_reveal_points(points: Array[Vector2]) -> void:
	_dynamic_reveal_points = points


func set_structure_reveal_points(points: Array[Vector2]) -> void:
	_structure_reveal_points = points


func set_base_reveal_points(points: Array[Vector2], pin_base_chunks: bool = true) -> void:
	_base_reveal_points = points

	if pin_base_chunks:
		for position in _base_reveal_points:
			pin_chunks_around_position(position, base_pin_radius_chunks, true)


func pin_chunks_around_position(world_position: Vector2, radius_chunks: int = -1, build_now: bool = true) -> void:
	if not _has_setup:
		return

	var radius: int = base_pin_radius_chunks

	if radius_chunks >= 0:
		radius = radius_chunks

	var center_chunk: Vector2i = _world_to_chunk(world_position)

	for cy in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for cx in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			var chunk_coord := Vector2i(cx, cy)

			if not _chunk_overlaps_world(chunk_coord):
				continue

			_pinned_chunks[chunk_coord] = true

			if build_now and not _loaded_chunks.has(chunk_coord):
				_load_chunk(chunk_coord)


func pin_chunks_around_positions(world_positions: Array[Vector2], radius_chunks: int = -1, build_now: bool = true) -> void:
	for position in world_positions:
		pin_chunks_around_position(position, radius_chunks, build_now)


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


func _create_or_update_fog_background() -> void:
	if _fog_background == null or not is_instance_valid(_fog_background):
		_fog_background = Polygon2D.new()
		_fog_background.name = "FogBackground"
		add_child(_fog_background)

	_fog_background.z_index = fog_background_z_index
	_fog_background.color = fog_background_color

	var left: float = _world_rect.position.x
	var top: float = _world_rect.position.y
	var right: float = _world_rect.position.x + _world_rect.size.x
	var bottom: float = _world_rect.position.y + _world_rect.size.y

	_fog_background.polygon = PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom),
		Vector2(left, bottom)
	])


func _update_visible_chunks() -> void:
	var camera_rects: Array[Rect2] = _get_active_camera_rects()

	if camera_rects.is_empty():
		return

	var wanted_chunks: Dictionary = {}
	var focus_sum := Vector2.ZERO

	for rect in camera_rects:
		focus_sum += rect.position + rect.size * 0.5

	var focus_position: Vector2 = focus_sum / float(camera_rects.size())
	_last_focus_chunk = _world_to_chunk(focus_position)

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

				if not _should_chunk_be_visible(chunk_coord):
					continue

				wanted_chunks[chunk_coord] = true

				if not _loaded_chunks.has(chunk_coord):
					_enqueue_chunk_build(chunk_coord)

	_apply_pinned_chunks_to_wanted(wanted_chunks)

	var chunks_to_remove: Array[Vector2i] = []

	for chunk_coord in _loaded_chunks.keys():
		if not wanted_chunks.has(chunk_coord):
			chunks_to_remove.append(chunk_coord)

	for chunk_coord in chunks_to_remove:
		_unload_chunk(chunk_coord)

	for pending_coord in _pending_chunk_lookup.keys():
		if not wanted_chunks.has(pending_coord):
			_pending_chunk_lookup.erase(pending_coord)

	if not _pending_chunk_builds.is_empty():
		_pending_chunk_builds.sort_custom(Callable(self, "_sort_chunk_by_focus"))

	if debug_chunks and _last_debug_chunk_count != _loaded_chunks.size():
		_last_debug_chunk_count = _loaded_chunks.size()
		print("Map chunks loaded: ", _loaded_chunks.size(), " pending: ", _pending_chunk_builds.size())


func _apply_pinned_chunks_to_wanted(wanted_chunks: Dictionary) -> void:
	for chunk_coord in _pinned_chunks.keys():
		if not _chunk_overlaps_world(chunk_coord):
			continue

		wanted_chunks[chunk_coord] = true

		if not _loaded_chunks.has(chunk_coord):
			_load_chunk(chunk_coord)


func _should_chunk_be_visible(chunk_coord: Vector2i) -> bool:
	if _pinned_chunks.has(chunk_coord):
		return true

	if not use_reveal_based_chunk_loading:
		return true

	var chunk_center: Vector2 = _get_chunk_center_world(chunk_coord)

	if _is_point_near_any(chunk_center, _base_reveal_points, base_reveal_radius_pixels):
		return true

	if _is_point_near_any(chunk_center, _structure_reveal_points, structure_reveal_radius_pixels):
		return true

	if _is_point_near_any(chunk_center, _dynamic_reveal_points, reveal_radius_pixels):
		return true

	return false


func _is_point_near_any(point: Vector2, points: Array[Vector2], radius: float) -> bool:
	var radius_squared: float = radius * radius

	for reveal_point in points:
		if point.distance_squared_to(reveal_point) <= radius_squared:
			return true

	return false


func _get_chunk_center_world(chunk_coord: Vector2i) -> Vector2:
	var chunk_min_cell: Vector2i = chunk_coord * chunk_size_tiles
	var chunk_max_cell: Vector2i = chunk_min_cell + Vector2i(chunk_size_tiles, chunk_size_tiles)

	var min_world: Vector2 = _cell_to_world(chunk_min_cell)
	var max_world: Vector2 = _cell_to_world(chunk_max_cell)

	return (min_world + max_world) * 0.5


func _enqueue_chunk_build(chunk_coord: Vector2i) -> void:
	if _loaded_chunks.has(chunk_coord):
		return

	if _pending_chunk_lookup.has(chunk_coord):
		return

	_pending_chunk_lookup[chunk_coord] = true
	_pending_chunk_builds.append(chunk_coord)


func _process_pending_chunk_builds(max_count: int) -> void:
	if max_count <= 0:
		return

	var built_count: int = 0

	while built_count < max_count and not _pending_chunk_builds.is_empty():
		var chunk_coord: Vector2i = _pending_chunk_builds.pop_front()

		if not _pending_chunk_lookup.has(chunk_coord):
			continue

		_pending_chunk_lookup.erase(chunk_coord)

		if _loaded_chunks.has(chunk_coord):
			continue

		_load_chunk(chunk_coord)
		built_count += 1


func _sort_chunk_by_focus(a: Vector2i, b: Vector2i) -> bool:
	var adx: int = a.x - _last_focus_chunk.x
	var ady: int = a.y - _last_focus_chunk.y
	var bdx: int = b.x - _last_focus_chunk.x
	var bdy: int = b.y - _last_focus_chunk.y

	var a_distance: int = adx * adx + ady * ady
	var b_distance: int = bdx * bdx + bdy * bdy

	return a_distance < b_distance


func _get_active_camera_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var cameras: Array[Node] = get_tree().get_nodes_in_group(tracked_camera_group)

	for node in cameras:
		if node is Camera2D:
			var camera := node as Camera2D

			if not camera.is_inside_tree():
				continue

			if not camera.enabled:
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

	var visible_world_size := Vector2(
		viewport_size.x / zoom.x,
		viewport_size.y / zoom.y
	)

	return Rect2(camera.global_position - visible_world_size * 0.5, visible_world_size)


func _load_chunk(chunk_coord: Vector2i) -> void:
	if _chunks_root == null:
		return

	var tile_map := TileMap.new()
	tile_map.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	tile_map.tile_set = generation_set.tile_set
	tile_map.z_index = 0

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
	if _pinned_chunks.has(chunk_coord):
		return

	if not _loaded_chunks.has(chunk_coord):
		return

	var node: Node = _loaded_chunks[chunk_coord]

	if node != null and is_instance_valid(node):
		node.queue_free()

	_loaded_chunks.erase(chunk_coord)


func _set_cell_generated(tile_map: TileMap, local_cell: Vector2i, world_cell: Vector2i) -> void:
	var is_spawn_clear: bool = _is_cell_in_spawn_clear_area(world_cell)

	if not is_spawn_clear and generation_set.has_patch_tiles():
		var noise_value: float = _patch_noise.get_noise_2d(float(world_cell.x), float(world_cell.y))

		if noise_value >= generation_set.patch_noise_cutoff:
			tile_map.set_cell(
				GROUND_LAYER,
				local_cell,
				generation_set.patch_source_id,
				_pick_tile(generation_set.patch_tiles, world_cell, 11)
			)
		else:
			_set_ground_cell(tile_map, local_cell, world_cell)
	else:
		_set_ground_cell(tile_map, local_cell, world_cell)

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


func _set_ground_cell(tile_map: TileMap, local_cell: Vector2i, world_cell: Vector2i) -> void:
	tile_map.set_cell(
		GROUND_LAYER,
		local_cell,
		generation_set.ground_source_id,
		_pick_tile(generation_set.ground_tiles, world_cell, 17)
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
	var h: int = _seed_value
	h = h ^ (world_cell.x * 73856093)
	h = h ^ (world_cell.y * 19349663)
	h = h ^ (salt * 83492791)

	if h < 0:
		h = -h

	return h


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

	return chunk_rect.intersects(_world_rect)


func _cell_inside_world(cell: Vector2i) -> bool:
	var world_position := _cell_to_world(cell)
	return _world_rect.has_point(world_position)


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

	for i in range(_cached_spawn_positions.size()):
		var marker := Marker2D.new()
		marker.name = "TeamSpawn%02d" % (i + 1)
		marker.global_position = _cached_spawn_positions[i]
		_spawn_points.add_child(marker)

		_generated_spawn_positions[i] = _cached_spawn_positions[i]


func _calculate_spawn_positions() -> Array[Vector2]:
	var safe_margin: float = max(spawn_margin_pixels, 1400.0)

	var left := _world_rect.position.x + safe_margin
	var right := _world_rect.position.x + _world_rect.size.x - safe_margin
	var top := _world_rect.position.y + safe_margin
	var bottom := _world_rect.position.y + _world_rect.size.y - safe_margin
	var center := _world_rect.position + _world_rect.size * 0.5

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
	var radius_squared: float = spawn_clear_radius_pixels * spawn_clear_radius_pixels

	for spawn_position in _cached_spawn_positions:
		if cell_world_position.distance_squared_to(spawn_position) <= radius_squared:
			return true

	return false


func _clear_all_chunks() -> void:
	for chunk_coord in _loaded_chunks.keys():
		var node: Node = _loaded_chunks[chunk_coord]

		if node != null and is_instance_valid(node):
			node.queue_free()

	_loaded_chunks.clear()
	_pending_chunk_builds.clear()
	_pending_chunk_lookup.clear()
