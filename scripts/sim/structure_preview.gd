class_name StructurePreview
extends Node2D

@export var body_sprite: Sprite2D

var structure_id: int = -1
var stats: StructureStats
var owner_team_id: int = 0

var _current_state: int = StructureRuntime.StructureState.ACTIVE
var _flash_tint: Color = Color.WHITE
var _flash_timer: float = 0.0


func _ready() -> void:
	if body_sprite == null:
		body_sprite = get_node_or_null("BodySprite")

	if body_sprite != null:
		var shader := load("res://shaders/team_tint_bw.gdshader") as Shader
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			body_sprite.material = mat


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta

		if body_sprite != null:
			body_sprite.modulate = _flash_tint

		if _flash_timer <= 0.0 and body_sprite != null:
			body_sprite.modulate = Color.WHITE


func apply_structure_runtime_setup(p_structure_id: int, p_stats: StructureStats, p_owner_team_id: int) -> void:
	structure_id = p_structure_id
	stats = p_stats
	owner_team_id = p_owner_team_id

	_apply_team_color()
	_apply_visuals()


func apply_structure_runtime_state(state: int, _current_health: int, _is_alive: bool) -> void:
	_current_state = state
	_apply_visuals()


func play_attack_flash() -> void:
	_start_flash(Color(1.2, 1.2, 0.8, 1.0), 0.08)


func play_hit_flash() -> void:
	_start_flash(Color(1.2, 0.85, 0.85, 1.0), 0.10)


func play_death_flash() -> void:
	_start_flash(Color(0.7, 0.7, 0.7, 1.0), 0.25)


func _start_flash(tint: Color, duration: float) -> void:
	_flash_tint = tint
	_flash_timer = duration

	if body_sprite != null:
		body_sprite.modulate = tint


func _apply_team_color() -> void:
	if body_sprite == null:
		return

	var mat := body_sprite.material as ShaderMaterial
	if mat == null:
		return

	mat.set_shader_parameter("team_color", TeamPalette.get_team_color(owner_team_id))


func _apply_visuals() -> void:
	if stats == null:
		return

	var texture_to_use: Texture2D = _get_texture_for_state(_current_state)

	if body_sprite != null:
		if texture_to_use != null:
			body_sprite.visible = true
			body_sprite.texture = texture_to_use
			_apply_team_color()
		else:
			body_sprite.visible = false

	queue_redraw()


func _get_texture_for_state(state: int) -> Texture2D:
	if state == StructureRuntime.StructureState.DESTROYED:
		if stats.sprite_destroyed != null:
			return stats.sprite_destroyed
		return stats.sprite_normal

	return stats.sprite_normal


func _draw() -> void:
	if stats == null:
		return

	var texture_to_use: Texture2D = _get_texture_for_state(_current_state)
	if texture_to_use != null:
		return

	# Fallback default structure shape
	var team_color: Color = TeamPalette.get_team_color(owner_team_id)
	var size: Vector2 = stats.footprint_size
	var rect := Rect2(-size * 0.5, size)

	draw_rect(rect, Color.BLACK, true)

	var inner_margin: float = 3.0
	var inner_rect := Rect2(
		rect.position + Vector2(inner_margin, inner_margin),
		rect.size - Vector2(inner_margin * 2.0, inner_margin * 2.0)
	)

	if inner_rect.size.x > 0.0 and inner_rect.size.y > 0.0:
		draw_rect(inner_rect, team_color, true)

	if _current_state == StructureRuntime.StructureState.DESTROYED:
		draw_line(rect.position, rect.position + rect.size, Color(0.4, 0.4, 0.4), 3.0)
		draw_line(
			Vector2(rect.position.x + rect.size.x, rect.position.y),
			Vector2(rect.position.x, rect.position.y + rect.size.y),
			Color(0.4, 0.4, 0.4),
			3.0
		)
