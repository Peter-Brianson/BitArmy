class_name UnitPreview
extends Node2D

@export var sprite: Sprite2D
@export var shadow_sprite: Sprite2D

var stats: UnitStats = null
var current_state: int = 0
var current_health: int = 1
var is_alive: bool = true
var owner_team_id: int = 0
var facing_dir: Vector2 = Vector2.RIGHT

var _walk_anim_timer: float = 0.0
var _walk_anim_frame: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	if sprite == null:
		sprite = _find_first_sprite_2d(self)

	if shadow_sprite == null:
		shadow_sprite = _find_sprite_by_name(self, "Shadow")

	_refresh_visual()


func _process(delta: float) -> void:
	if stats == null:
		return

	if current_state == UnitRuntime.UnitState.WALK and is_alive:
		var fps: float = max(stats.walk_anim_fps, 0.001)
		var frame_time: float = 1.0 / fps

		_walk_anim_timer += delta
		while _walk_anim_timer >= frame_time:
			_walk_anim_timer -= frame_time
			_walk_anim_frame = 1 - _walk_anim_frame

		_refresh_texture_only()
	else:
		if _walk_anim_timer != 0.0 or _walk_anim_frame != 0:
			_walk_anim_timer = 0.0
			_walk_anim_frame = 0
			_refresh_texture_only()

	_refresh_facing_only()


func setup(unit_stats: UnitStats, team_id: int) -> void:
	stats = unit_stats
	owner_team_id = team_id
	is_alive = true
	current_health = stats.max_health if stats != null else 1
	current_state = UnitRuntime.UnitState.IDLE
	facing_dir = Vector2.RIGHT
	_walk_anim_timer = 0.0
	_walk_anim_frame = 0
	_refresh_visual()


func apply_unit_runtime_state(
	state: int,
	health: int,
	alive: bool,
	team_id: int,
	new_facing_dir: Vector2
) -> void:
	current_state = state
	current_health = health
	is_alive = alive
	owner_team_id = team_id
	facing_dir = new_facing_dir

	if not is_alive or current_state != UnitRuntime.UnitState.WALK:
		_walk_anim_timer = 0.0
		_walk_anim_frame = 0

	_refresh_visual()


func set_stats(unit_stats: UnitStats) -> void:
	stats = unit_stats
	_walk_anim_timer = 0.0
	_walk_anim_frame = 0
	_refresh_visual()


func _refresh_visual() -> void:
	_refresh_texture_only()
	_refresh_color_only()
	_refresh_facing_only()
	_refresh_visibility_only()


func _refresh_texture_only() -> void:
	if sprite == null:
		return

	sprite.texture = _get_texture_for_state()


func _refresh_color_only() -> void:
	if sprite != null:
		sprite.modulate = _get_team_color(owner_team_id)

	if shadow_sprite != null:
		shadow_sprite.visible = is_alive


func _refresh_facing_only() -> void:
	if sprite == null:
		return

	if abs(facing_dir.x) > 0.001:
		sprite.flip_h = facing_dir.x < 0.0


func _refresh_visibility_only() -> void:
	visible = stats != null

	if shadow_sprite != null:
		shadow_sprite.visible = is_alive


func _get_texture_for_state() -> Texture2D:
	if stats == null:
		return null

	if not is_alive:
		if stats.sprite_dead != null:
			return stats.sprite_dead
		if stats.sprite_idle != null:
			return stats.sprite_idle
		return null

	match current_state:
		UnitRuntime.UnitState.WALK:
			return stats.get_walk_frame(_walk_anim_frame)

		UnitRuntime.UnitState.ATTACK:
			if stats.sprite_attack != null:
				return stats.sprite_attack
			return _get_idle_fallback()

		UnitRuntime.UnitState.IDLE:
			return _get_idle_fallback()

		_:
			return _get_idle_fallback()


func _get_idle_fallback() -> Texture2D:
	if stats == null:
		return null

	if stats.sprite_idle != null:
		return stats.sprite_idle

	if stats.sprite_walk != null:
		return stats.sprite_walk

	if stats.sprite_walk_a != null:
		return stats.sprite_walk_a

	if stats.sprite_walk_b != null:
		return stats.sprite_walk_b

	return null


func _get_team_color(team_id: int) -> Color:
	return TeamPalette.get_team_color(team_id)

func _find_first_sprite_2d(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D

	for child in node.get_children():
		var found: Sprite2D = _find_first_sprite_2d(child)
		if found != null:
			return found

	return null


func _find_sprite_by_name(node: Node, target_name: String) -> Sprite2D:
	if node is Sprite2D and node.name == target_name:
		return node as Sprite2D

	for child in node.get_children():
		var found: Sprite2D = _find_sprite_by_name(child, target_name)
		if found != null:
			return found

	return null
