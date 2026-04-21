class_name StructurePreview
extends Node2D

@onready var visual: CanvasItem = get_node_or_null("Visual")

var runtime_id: int = -1
var stats: StructureStats
var owner_team_id: int = -1
var team_color: Color = Color.WHITE
var current_health: int = 0
var is_alive: bool = true

var flash_color: Color = Color.WHITE
var flash_strength: float = 0.0
var flash_fade_speed: float = 8.0

func _ready() -> void:
	_apply_visual_shape()
	_apply_visuals()

func _physics_process(delta: float) -> void:
	if flash_strength > 0.0:
		flash_strength = max(flash_strength - flash_fade_speed * delta, 0.0)
		_apply_visuals()
		queue_redraw()

func apply_structure_runtime_setup(p_runtime_id: int, p_stats: StructureStats, p_team_id: int) -> void:
	runtime_id = p_runtime_id
	stats = p_stats
	owner_team_id = p_team_id
	team_color = TeamPalette.get_team_color(owner_team_id)
	current_health = stats.max_health
	is_alive = true

	_apply_visual_shape()
	_apply_visuals()
	queue_redraw()

func apply_structure_runtime_state(_state: int, p_health: int, p_is_alive: bool) -> void:
	current_health = p_health
	is_alive = p_is_alive

	_apply_visuals()
	queue_redraw()

func play_attack_flash() -> void:
	flash_color = Color("#FFF4A3")
	flash_strength = 0.75
	_apply_visuals()
	queue_redraw()

func play_hit_flash() -> void:
	flash_color = Color("#FFFFFF")
	flash_strength = 1.0
	_apply_visuals()
	queue_redraw()

func play_death_flash() -> void:
	flash_color = Color("#FF6B6B")
	flash_strength = 1.0
	_apply_visuals()
	queue_redraw()

func _apply_visual_shape() -> void:
	if stats == null:
		return
	if visual == null:
		return

	if visual is Sprite2D:
		var sprite: Sprite2D = visual
		sprite.centered = true
		sprite.scale = Vector2.ONE

	elif visual is ColorRect:
		var color_rect: ColorRect = visual as ColorRect
		color_rect.size = stats.footprint_size
		color_rect.position = -stats.footprint_size * 0.5

	elif visual is Polygon2D:
		var poly: Polygon2D = visual as Polygon2D
		var half: Vector2 = stats.footprint_size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y)
		])

func _apply_visuals() -> void:
	var final_color: Color = team_color.lerp(flash_color, flash_strength)

	if not is_alive:
		final_color = final_color.darkened(0.45)

	if visual != null and visual is CanvasItem:
		var canvas_item: CanvasItem = visual
		canvas_item.self_modulate = final_color

func _draw() -> void:
	if stats == null:
		return

	if visual != null:
		return

	var rect := Rect2(
		-stats.footprint_size * 0.5,
		stats.footprint_size
	)

	var final_color: Color = team_color.lerp(flash_color, flash_strength)

	if not is_alive:
		final_color = final_color.darkened(0.45)

	draw_rect(rect, final_color)
