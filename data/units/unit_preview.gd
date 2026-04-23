class_name UnitPreview
extends Node2D

@export var body_sprite: Sprite2D

var unit_id: int = -1
var stats: UnitStats
var owner_team_id: int = 0
var _current_state: int = UnitRuntime.UnitState.IDLE
var _facing_dir: Vector2 = Vector2.RIGHT

var _flash_tint: Color = Color.WHITE
var _flash_timer: float = 0.0

var _walk_anim_timer: float = 0.0
var _walk_anim_frame: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	if body_sprite == null:
		body_sprite = get_node_or_null("BodySprite")

	if body_sprite == null:
		push_warning("UnitPreview: BodySprite node not found.")


func _process(delta: float) -> void:
	if stats == null:
		return

	_update_walk_animation(delta)
	_update_flash(delta)


func apply_unit_runtime_setup(p_unit_id: int, p_stats: UnitStats, p_owner_team_id: int) -> void:
	unit_id = p_unit_id
	stats = p_stats
	owner_team_id = p_owner_team_id
	_current_state = UnitRuntime.UnitState.IDLE
	_facing_dir = Vector2.RIGHT
	_flash_timer = 0.0
	_walk_anim_timer = 0.0
	_walk_anim_frame = 0
	_apply_visuals()


func apply_unit_runtime_state(state: int, _current_health: int, _is_alive: bool, p_owner_team_id: int, facing_dir: Vector2) -> void:
	var previous_state: int = _current_state

	_current_state = state
	owner_team_id = p_owner_team_id
	_facing_dir = facing_dir

	if previous_state != UnitRuntime.UnitState.WALK and _current_state == UnitRuntime.UnitState.WALK:
		_walk_anim_timer = 0.0
		_walk_anim_frame = 0

	if _current_state != UnitRuntime.UnitState.WALK:
		_walk_anim_timer = 0.0
		_walk_anim_frame = 0

	_apply_visuals()


func play_attack_flash() -> void:
	_start_flash(Color(1.2, 1.2, 0.8, 1.0), 0.08)


func play_hit_flash() -> void:
	_start_flash(Color(1.3, 0.8, 0.8, 1.0), 0.10)


func play_death_flash() -> void:
	_start_flash(Color(0.7, 0.7, 0.7, 1.0), 0.20)


func _start_flash(tint: Color, duration: float) -> void:
	_flash_tint = tint
	_flash_timer = duration

	if body_sprite != null:
		body_sprite.modulate = tint


func _update_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return

	_flash_timer -= delta

	if _flash_timer <= 0.0:
		_flash_timer = 0.0
		_apply_current_modulate()


func _update_walk_animation(delta: float) -> void:
	if _current_state != UnitRuntime.UnitState.WALK:
		return
	if stats == null:
		return
	if body_sprite == null:
		return

	var uses_two_frame_walk: bool = stats.sprite_walk_a != null or stats.sprite_walk_b != null
	if not uses_two_frame_walk:
		return

	var fps: float = max(stats.walk_anim_fps, 0.001)
	var frame_time: float = 1.0 / fps

	_walk_anim_timer += delta
	while _walk_anim_timer >= frame_time:
		_walk_anim_timer -= frame_time
		_walk_anim_frame = 1 - _walk_anim_frame
		_apply_visuals()


func _apply_team_color() -> void:
	if body_sprite == null:
		return

	body_sprite.modulate = TeamPalette.get_team_color(owner_team_id)


func _apply_current_modulate() -> void:
	if body_sprite == null:
		return

	if _flash_timer > 0.0:
		body_sprite.modulate = _flash_tint
	else:
		_apply_team_color()


func _apply_visuals() -> void:
	if stats == null:
		return

	var texture_to_use: Texture2D = _get_texture_for_state(_current_state)

	if body_sprite != null:
		if texture_to_use != null:
			body_sprite.visible = true
			body_sprite.texture = texture_to_use
			body_sprite.centered = true
			body_sprite.flip_h = _facing_dir.x < 0.0
			_apply_current_modulate()
		else:
			body_sprite.visible = false

	queue_redraw()


func _get_texture_for_state(state: int) -> Texture2D:
	if stats == null:
		return null

	match state:
		UnitRuntime.UnitState.WALK:
			if stats.sprite_walk_a != null or stats.sprite_walk_b != null:
				return stats.get_walk_frame(_walk_anim_frame)
			if stats.sprite_walk != null:
				return stats.sprite_walk
			return stats.sprite_idle

		UnitRuntime.UnitState.ATTACK:
			if stats.sprite_attack != null:
				return stats.sprite_attack
			return stats.sprite_idle

		UnitRuntime.UnitState.DEAD:
			if stats.sprite_dead != null:
				return stats.sprite_dead
			return stats.sprite_idle

		_:
			return stats.sprite_idle


func _draw() -> void:
	if stats == null:
		return

	var texture_to_use: Texture2D = _get_texture_for_state(_current_state)
	if texture_to_use != null:
		return

	var team_color: Color = TeamPalette.get_team_color(owner_team_id)
	var size: Vector2 = stats.body_size
	var rect := Rect2(-size * 0.5, size)

	draw_rect(rect, Color.BLACK, true)

	var inner_margin: float = 2.0
	var inner_rect := Rect2(
		rect.position + Vector2(inner_margin, inner_margin),
		rect.size - Vector2(inner_margin * 2.0, inner_margin * 2.0)
	)

	if inner_rect.size.x > 0.0 and inner_rect.size.y > 0.0:
		draw_rect(inner_rect, team_color, true)

	if _current_state == UnitRuntime.UnitState.ATTACK:
		draw_circle(Vector2(size.x * 0.5 + 2.0, -2.0), 2.0, Color.WHITE)

	if _current_state == UnitRuntime.UnitState.DEAD:
		draw_line(rect.position, rect.position + rect.size, Color(0.4, 0.4, 0.4), 2.0)
		draw_line(
			Vector2(rect.position.x + rect.size.x, rect.position.y),
			Vector2(rect.position.x, rect.position.y + rect.size.y),
			Color(0.4, 0.4, 0.4),
			2.0
		)
