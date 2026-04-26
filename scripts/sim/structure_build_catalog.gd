class_name StructureBuildCatalog
extends Node

const CATEGORY_LEGACY: String = "legacy"
const CATEGORY_TRAINERS: String = "trainers"
const CATEGORY_ECONOMY: String = "economy"
const CATEGORY_SUPPORT: String = "support"
const CATEGORY_DEFENSE: String = "defense"

@export_group("Scene Defaults")
@export var default_structure_scene: PackedScene

@export_group("Display Order")
@export var category_display_order: Array[String] = [
	CATEGORY_LEGACY,
	CATEGORY_TRAINERS,
	CATEGORY_ECONOMY,
	CATEGORY_SUPPORT,
	CATEGORY_DEFENSE,
]

@export_group("Legacy / Starter Structures")
@export var legacy_structure_stats: Array[StructureStats] = []
@export var legacy_structure_scenes: Array[PackedScene] = []

@export_group("Trainer Structures")
@export var trainer_structure_stats: Array[StructureStats] = []
@export var trainer_structure_scenes: Array[PackedScene] = []

@export_group("Economy Structures")
@export var economy_structure_stats: Array[StructureStats] = []
@export var economy_structure_scenes: Array[PackedScene] = []

@export_group("Support Structures")
@export var support_structure_stats: Array[StructureStats] = []
@export var support_structure_scenes: Array[PackedScene] = []

@export_group("Defense Structures")
@export var defense_structure_stats: Array[StructureStats] = []
@export var defense_structure_scenes: Array[PackedScene] = []


func normalize_category_name(category_name: String) -> String:
	var key: String = category_name.strip_edges().to_lower()

	match key:
		"legacy", "starter", "starters", "basic", "basics":
			return CATEGORY_LEGACY
		"trainer", "trainers", "training", "unit", "units":
			return CATEGORY_TRAINERS
		"economy", "econ", "resource", "resources", "income":
			return CATEGORY_ECONOMY
		"support", "tech", "utility", "buff", "buffs":
			return CATEGORY_SUPPORT
		"defense", "defence", "turret", "turrets", "wall", "walls":
			return CATEGORY_DEFENSE

	return key


func get_category_label(category_name: String) -> String:
	match normalize_category_name(category_name):
		CATEGORY_LEGACY:
			return "Legacy"
		CATEGORY_TRAINERS:
			return "Training"
		CATEGORY_ECONOMY:
			return "Economy"
		CATEGORY_SUPPORT:
			return "Support"
		CATEGORY_DEFENSE:
			return "Defense"

	return category_name.capitalize()


func get_non_empty_category_names() -> Array[String]:
	var results: Array[String] = []

	for category_name in category_display_order:
		var normalized: String = normalize_category_name(category_name)
		if results.has(normalized):
			continue

		if not get_entries_for_category_name(normalized).is_empty():
			results.append(normalized)

	return results


func get_all_entries() -> Array:
	var results: Array = []

	for category_name in get_non_empty_category_names():
		results.append_array(get_entries_for_category_name(category_name))

	return results


func get_entries_for_category_name(category_name: String) -> Array:
	var normalized: String = normalize_category_name(category_name)

	match normalized:
		CATEGORY_LEGACY:
			return _get_category_entries(
				CATEGORY_LEGACY,
				get_category_label(CATEGORY_LEGACY),
				legacy_structure_stats,
				legacy_structure_scenes
			)

		CATEGORY_TRAINERS:
			return _get_category_entries(
				CATEGORY_TRAINERS,
				get_category_label(CATEGORY_TRAINERS),
				trainer_structure_stats,
				trainer_structure_scenes
			)

		CATEGORY_ECONOMY:
			return _get_category_entries(
				CATEGORY_ECONOMY,
				get_category_label(CATEGORY_ECONOMY),
				economy_structure_stats,
				economy_structure_scenes
			)

		CATEGORY_SUPPORT:
			return _get_category_entries(
				CATEGORY_SUPPORT,
				get_category_label(CATEGORY_SUPPORT),
				support_structure_stats,
				support_structure_scenes
			)

		CATEGORY_DEFENSE:
			return _get_category_entries(
				CATEGORY_DEFENSE,
				get_category_label(CATEGORY_DEFENSE),
				defense_structure_stats,
				defense_structure_scenes
			)

	return []


func _get_category_entries(
	category_name: String,
	category_label: String,
	stats_array: Array,
	scene_array: Array
) -> Array:
	var results: Array = []

	for i in range(stats_array.size()):
		var stats: StructureStats = stats_array[i]

		if stats == null:
			continue

		var scene: PackedScene = default_structure_scene

		if i < scene_array.size() and scene_array[i] != null:
			scene = scene_array[i]

		if scene == null:
			continue

		results.append({
			"category": category_name,
			"category_label": category_label,
			"category_index": i,
			"stats": stats,
			"scene": scene,
		})

	return results
