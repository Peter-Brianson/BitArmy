class_name MapGenerationSet
extends Resource

@export var display_name: String = "Generated Set"
@export var tile_set: TileSet

@export_group("Ground Tiles")
@export var ground_source_id: int = 0
@export var ground_tiles: Array[Vector2i] = [Vector2i(0, 0)]

@export_group("Patch Tiles")
@export var patch_source_id: int = 0
@export var patch_tiles: Array[Vector2i] = []
@export_range(-1.0, 1.0, 0.01) var patch_noise_cutoff: float = 0.25
@export_range(0.001, 0.25, 0.001) var patch_noise_frequency: float = 0.035

@export_group("Detail Tiles")
@export var detail_source_id: int = 0
@export var detail_tiles: Array[Vector2i] = []
@export_range(0.0, 1.0, 0.01) var detail_chance: float = 0.05

func has_ground_tiles() -> bool:
	return not ground_tiles.is_empty()

func has_patch_tiles() -> bool:
	return not patch_tiles.is_empty()

func has_detail_tiles() -> bool:
	return not detail_tiles.is_empty()
