class_name MainMenuBackground
extends Control

@export_group("Palette")
@export var sky_color: Color = Color8(28, 204, 209)
@export var ground_color: Color = Color8(127, 225, 139)
@export var grass_dark: Color = Color8(66, 105, 71)
@export var grass_mid: Color = Color8(93, 159, 101)

@export var ui_dark: Color = Color8(26, 97, 99)
@export var ink: Color = Color8(0, 0, 0)
@export var team_blue: Color = Color8(74, 144, 226)
@export var team_red: Color = Color8(233, 78, 78)
@export var white: Color = Color8(255, 255, 255)

@export_group("Style")
@export_range(1, 8, 1) var pixel_scale: int = 4
@export_range(0.1, 1.0, 0.05) var diorama_alpha: float = 0.75
@export var show_ground_strip: bool = true
@export var show_diorama: bool = true
@export var animate_flags: bool = true

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func _process(delta: float) -> void:
	if animate_flags:
		_time += delta
		queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size

	# Flat menu background.
	draw_rect(Rect2(Vector2.ZERO, s), sky_color, true)

	var ground_h: float = max(120.0, s.y * 0.17)
	var ground_y: float = s.y - ground_h

	if show_ground_strip:
		draw_rect(Rect2(0.0, ground_y, s.x, ground_h), ground_color, true)
		_draw_grass_noise(ground_y, ground_h)

	if show_diorama:
		_draw_blue_base(Vector2(s.x * 0.68, ground_y - 96.0))
		_draw_red_scouts(Vector2(s.x * 0.25, ground_y - 42.0))
		_draw_neutral_props(Vector2(s.x * 0.50, ground_y - 28.0))

func _draw_grass_noise(ground_y: float, ground_h: float) -> void:
	var s: Vector2 = size
	var u: float = float(pixel_scale)

	# Deterministic grass chunks. No random every frame.
	for i in range(0, 90):
		var x := float((i * 97) % int(max(1.0, s.x)))
		var y := ground_y + float((i * 37) % int(max(1.0, ground_h - 8.0)))
		var w := float(1 + ((i * 11) % 4)) * u
		var h := float(1 + ((i * 5) % 3)) * u

		var c := grass_dark
		if i % 3 == 0:
			c = grass_mid

		draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), c, true)


func _draw_blue_base(origin: Vector2) -> void:
	var a := diorama_alpha
	var u := float(pixel_scale)

	_draw_hq(origin + Vector2(0, 16) * u, team_blue, a)
	_draw_barracks(origin + Vector2(40, 28) * u, team_blue, a)
	_draw_small_house(origin + Vector2(-38, 35) * u, team_blue, a)
	_draw_tower(origin + Vector2(82, 18) * u, team_blue, a)
	_draw_flag(origin + Vector2(115, 24) * u, team_blue, a)

	for i in range(0, 10):
		var x := float((i % 5) * 12)
		var y := float((i / 5) * 12)
		_draw_unit(origin + Vector2(18 + x, 78 + y) * u, team_blue, a)


func _draw_red_scouts(origin: Vector2) -> void:
	var a := diorama_alpha * 0.85
	var u := float(pixel_scale)

	for i in range(0, 5):
		_draw_unit(origin + Vector2(i * 12, 0) * u, team_red, a)


func _draw_neutral_props(origin: Vector2) -> void:
	var a := diorama_alpha * 0.55
	var u := float(pixel_scale)

	# Simple rocks / map marks.
	_rect(origin + Vector2(-18, 8) * u, Vector2(8, 4) * u, ui_dark, a)
	_rect(origin + Vector2(-14, 4) * u, Vector2(4, 4) * u, ui_dark, a)

	_rect(origin + Vector2(25, 14) * u, Vector2(10, 4) * u, ui_dark, a)
	_rect(origin + Vector2(29, 10) * u, Vector2(4, 4) * u, ui_dark, a)


func _draw_hq(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(0, 12) * u, Vector2(22, 14) * u, color, alpha)
	_rect(pos + Vector2(5, 6) * u, Vector2(12, 6) * u, color, alpha)
	_rect(pos + Vector2(2, 24) * u, Vector2(4, 4) * u, ink, alpha)
	_rect(pos + Vector2(16, 24) * u, Vector2(4, 4) * u, ink, alpha)
	_rect(pos + Vector2(10, 2) * u, Vector2(2, 4) * u, ink, alpha)


func _draw_barracks(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(0, 10) * u, Vector2(28, 12) * u, color, alpha)
	_rect(pos + Vector2(4, 6) * u, Vector2(20, 4) * u, color, alpha)
	_rect(pos + Vector2(4, 18) * u, Vector2(4, 4) * u, ink, alpha)
	_rect(pos + Vector2(20, 18) * u, Vector2(4, 4) * u, ink, alpha)


func _draw_small_house(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(0, 10) * u, Vector2(16, 12) * u, color, alpha)
	_rect(pos + Vector2(4, 6) * u, Vector2(8, 4) * u, color, alpha)
	_rect(pos + Vector2(6, 18) * u, Vector2(4, 4) * u, ink, alpha)


func _draw_tower(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(4, 2) * u, Vector2(10, 26) * u, color, alpha)
	_rect(pos + Vector2(2, 0) * u, Vector2(14, 4) * u, color, alpha)
	_rect(pos + Vector2(7, 24) * u, Vector2(4, 4) * u, ink, alpha)


func _draw_flag(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(0, 0) * u, Vector2(2, 32) * u, ink, alpha)

	var flutter := 0
	if animate_flags and int(_time * 2.0) % 2 == 0:
		flutter = 1

	_rect(pos + Vector2(2, 2) * u, Vector2(12 + flutter * 2, 8) * u, color, alpha)
	_rect(pos + Vector2(10, 10) * u, Vector2(4, 4) * u, color, alpha)


func _draw_unit(pos: Vector2, color: Color, alpha: float) -> void:
	var u := float(pixel_scale)

	_rect(pos + Vector2(2, 0) * u, Vector2(4, 4) * u, color, alpha)
	_rect(pos + Vector2(1, 4) * u, Vector2(6, 7) * u, color, alpha)
	_rect(pos + Vector2(0, 11) * u, Vector2(2, 3) * u, ink, alpha)
	_rect(pos + Vector2(6, 11) * u, Vector2(2, 3) * u, ink, alpha)

	# Tiny weapon/readability pixel.
	_rect(pos + Vector2(7, 5) * u, Vector2(5, 2) * u, ink, alpha)


func _rect(pos: Vector2, rect_size: Vector2, color: Color, alpha: float = 1.0) -> void:
	var c := color
	c.a *= alpha

	var snapped_pos := Vector2(round(pos.x), round(pos.y))
	var snapped_size := Vector2(round(rect_size.x), round(rect_size.y))

	draw_rect(Rect2(snapped_pos, snapped_size), c, true)
