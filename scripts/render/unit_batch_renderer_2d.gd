class_name UnitBatchRenderer2D
extends Node2D

@export var team_manager: TeamManager
@export var camera_pan_controller: CameraPanController
@export var unit_manager: UnitSimulationManager
@export var unit_texture: Texture2D
@export var max_teams: int = 8
@export var cull_margin: float = 128.0

var _instances_by_team: Dictionary = {}   # team_id -> MultiMeshInstance2D
var _multimesh_by_team: Dictionary = {}   # team_id -> MultiMesh


func _ready() -> void:
	_build_team_batches()


func _process(_delta: float) -> void:
	_render_all_units()


func _build_team_batches() -> void:
	for child in get_children():
		child.queue_free()

	_instances_by_team.clear()
	_multimesh_by_team.clear()

	for team_id in range(max_teams):
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = 0

		var inst := MultiMeshInstance2D.new()
		inst.multimesh = mm
		inst.texture = unit_texture
		add_child(inst)

		_multimesh_by_team[team_id] = mm
		_instances_by_team[team_id] = inst

func _render_all_units() -> void:
	if unit_manager == null:
		return

	var visible_units_by_team: Dictionary = {}
	var cull_rect: Rect2 = _get_cull_rect()

	for team_id in _multimesh_by_team.keys():
		visible_units_by_team[team_id] = []

	for unit in unit_manager.units.values():
		var u: UnitRuntime = unit
		if not u.is_alive:
			continue
		if not cull_rect.has_point(u.position):
			continue

		visible_units_by_team[u.owner_team_id].append(u)

	for team_id in _multimesh_by_team.keys():
		var units_for_team: Array = visible_units_by_team[team_id]
		var mm: MultiMesh = _multimesh_by_team[team_id]

		mm.instance_count = units_for_team.size()

		for i in range(units_for_team.size()):
			var u: UnitRuntime = units_for_team[i]

			var x_axis := Vector2(u.stats.body_size.x, 0.0)
			var y_axis := Vector2(0.0, u.stats.body_size.y)

			# Optional left/right facing only:
			if u.facing_dir.x < 0.0:
				x_axis.x *= -1.0

			var _transform := Transform2D(x_axis, y_axis, u.position)
			mm.set_instance_transform_2d(i, _transform)
			mm.set_instance_color(i, _get_unit_render_color(u))

func _get_unit_render_color(unit: UnitRuntime) -> Color:
	var base: Color = TeamPalette.get_team_color(unit.owner_team_id)

	match unit.state:
		UnitRuntime.UnitState.ATTACK:
			return base.lerp(Color(1, 1, 0.6), 0.35)
		UnitRuntime.UnitState.DEAD:
			return base.darkened(0.45)
		_:
			return base

func _get_cull_rect() -> Rect2:
	if camera_pan_controller == null or camera_pan_controller.camera == null:
		return Rect2(-1000000, -1000000, 2000000, 2000000)

	var cam: Camera2D = camera_pan_controller.camera
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = cam.get_screen_center_position()
	var half_extents: Vector2 = viewport_size * 0.5 * cam.zoom
	var margin_vec := Vector2(cull_margin, cull_margin)

	return Rect2(
		center - half_extents - margin_vec,
		half_extents * 2.0 + margin_vec * 2.0
	)
