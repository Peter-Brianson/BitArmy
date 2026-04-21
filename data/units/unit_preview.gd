class_name UnitPreview
extends Node2D

@export var stats: UnitStats

var runtime_id: int = -1
var owner_team_id: int = -1
var team_color: Color = Color.WHITE
var current_health: int = 0
var is_alive: bool = true
var current_state: int = UnitRuntime.UnitState.IDLE
var facing_dir: Vector2 = Vector2.RIGHT

var flash_color: Color = Color.WHITE
var flash_strength: float = 0.0
var flash_fade_speed: float = 10.0

func _physics_process(delta: float) -> void:
	if flash_strength > 0.0:
		flash_strength = max(flash_strength - flash_fade_speed * delta, 0.0)
		queue_redraw()

func apply_unit_runtime_setup(p_runtime_id: int, p_stats: UnitStats, p_team_id: int) -> void:
	runtime_id = p_runtime_id
	stats = p_stats
	owner_team_id = p_team_id
	team_color = TeamPalette.get_team_color(owner_team_id)
	current_health = stats.max_health
	is_alive = true
	current_state = UnitRuntime.UnitState.IDLE
	facing_dir = Vector2.RIGHT
	queue_redraw()

func apply_unit_runtime_state(p_state: int, p_health: int, p_is_alive: bool, p_team_id: int, p_facing_dir: Vector2) -> void:
	current_state = p_state
	current_health = p_health
	is_alive = p_is_alive
	owner_team_id = p_team_id
	team_color = TeamPalette.get_team_color(owner_team_id)

	if p_facing_dir.length_squared() > 0.001:
		facing_dir = p_facing_dir.normalized()

	queue_redraw()

func play_attack_flash() -> void:
	flash_color = Color("#FFF4A3")
	flash_strength = 0.8
	queue_redraw()

func play_hit_flash() -> void:
	flash_color = Color("#FFFFFF")
	flash_strength = 1.0
	queue_redraw()

func play_death_flash() -> void:
	flash_color = Color("#FF6B6B")
	flash_strength = 1.0
	queue_redraw()

func _get_state_tinted_color() -> Color:
	var color: Color = team_color

	match current_state:
		UnitRuntime.UnitState.IDLE:
			pass
		UnitRuntime.UnitState.WALK:
			color = color.lightened(0.10)
		UnitRuntime.UnitState.ATTACK:
			color = color.lightened(0.22)
		UnitRuntime.UnitState.DEAD:
			color = color.darkened(0.45)

	if not is_alive:
		color = color.darkened(0.45)

	return color

func _draw() -> void:
	if stats == null:
		return

	var base_color: Color = _get_state_tinted_color()
	var final_color: Color = base_color.lerp(flash_color, flash_strength)

	var size := stats.body_size
	var rect := Rect2(
		Vector2(-size.x * 0.5, -size.y * 0.5),
		size
	)

	draw_rect(rect, final_color)

# Front marker
	var front_color: Color = Color.BLACK.lerp(Color.WHITE, flash_strength * 0.5)
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var marker_length: float = half_w
	if half_h > marker_length:
		marker_length = half_h

	var marker_start: Vector2 = facing_dir * 4.0
	var marker_end: Vector2 = facing_dir * marker_length

	draw_line(marker_start, marker_end, front_color, 2.0)
