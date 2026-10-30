extends Control

## High-clarity vector icon set for the main menu and social-choice sheet.
## Drawn at the control's current logical size with antialiased paths, a fine
## highlight edge, and a restrained lower-right contact shadow.

@export_enum("settings", "play", "friends", "guide", "wifi", "quick", "code", "chevron") var icon_name: String = "play":
	set(value):
		icon_name = value
		queue_redraw()

@export var icon_color: Color = Color("56668A"):
	set(value):
		icon_color = value
		queue_redraw()

@export var accent_surface: bool = false:
	set(value):
		accent_surface = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side < 2.0:
		return
	var c := size * 0.5
	var s := side
	var color := icon_color
	var shadow := Color(0.14, 0.20, 0.34, 0.25 if not accent_surface else 0.18)
	var highlight := Color(1.0, 1.0, 1.0, 0.48 if not accent_surface else 0.38)

	match icon_name:
		"settings":
			_draw_gear(c, s, color, shadow, highlight)
		"play":
			_draw_play(c, s, color, shadow, highlight)
		"friends":
			_draw_friends(c, s, color, shadow, highlight)
		"guide":
			_draw_book(c, s, color, shadow, highlight)
		"wifi":
			_draw_wifi(c, s, color, shadow, highlight)
		"quick":
			_draw_quick(c, s, color, shadow, highlight)
		"code":
			_draw_code(c, s, color, shadow, highlight)
		"chevron":
			_draw_chevron(c, s, color, shadow, highlight)

func _draw_gear(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var phase := i % 4
		var radius := s * (0.37 if phase == 0 or phase == 3 else 0.48)
		var angle := TAU * float(i) / 40.0 - PI * 0.5
		points.append(c + Vector2(cos(angle), sin(angle)) * radius)
	_filled_shape(points, Vector2(1.5, 2.0), shadow)
	_filled_shape(points, Vector2(-0.8, -1.0), highlight)
	_filled_shape(points, Vector2.ZERO, color)
	draw_arc(c, s * 0.205, 0.0, TAU, 40, shadow, maxf(1.8, s * 0.065), true)
	var hole := Color("E4E9F2")
	if accent_surface:
		hole = color.darkened(0.22)
	draw_circle(c, s * 0.145, hole)
	draw_arc(c + Vector2(-0.4, -0.5), s * 0.145, 0.0, TAU, 40, highlight, maxf(1.0, s * 0.035), true)

func _draw_play(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var ring_radius := s * 0.39
	draw_arc(c + Vector2(1.0, 1.5), ring_radius, 0.0, TAU, 48, shadow, maxf(2.4, s * 0.075), true)
	draw_arc(c + Vector2(-0.5, -0.8), ring_radius, 0.0, TAU, 48, highlight, maxf(1.3, s * 0.045), true)
	draw_arc(c, ring_radius, 0.0, TAU, 48, color, maxf(2.3, s * 0.075), true)
	var tri := PackedVector2Array([
		c + Vector2(-s * 0.105, -s * 0.205),
		c + Vector2(s * 0.225, 0.0),
		c + Vector2(-s * 0.105, s * 0.205)
	])
	_filled_shape(tri, Vector2(1.1, 1.5), shadow)
	_filled_shape(tri, Vector2.ZERO, color)

func _draw_friends(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	# Three clearly separated heads over broad shoulder silhouettes. The centered
	# figure leads; the two smaller companions sit behind it, making the group read
	# as people rather than two abstract loops.
	var head_r: float = s * 0.095
	var side_r: float = s * 0.075
	var center_head := c + Vector2(0.0, -s * 0.18)
	var left_head := c + Vector2(-s * 0.235, -s * 0.055)
	var right_head := c + Vector2(s * 0.235, -s * 0.055)

	for head in [left_head, right_head]:
		draw_circle(head + Vector2(0.8, 1.1), side_r, shadow)
		draw_circle(head + Vector2(-0.45, -0.55), side_r, highlight)
		draw_circle(head, side_r, color)
	draw_circle(center_head + Vector2(0.9, 1.2), head_r, shadow)
	draw_circle(center_head + Vector2(-0.45, -0.65), head_r, highlight)
	draw_circle(center_head, head_r, color)

	var stroke: float = maxf(2.4, s * 0.075)
	# Rear shoulders are deliberately shorter and lower-contrast so the front
	# silhouette remains legible at small mobile icon sizes.
	_stroke_arc(c + Vector2(-s * 0.235, s * 0.22) + Vector2(0.8, 1.0), s * 0.155, PI * 0.10, PI * 0.90, shadow, stroke)
	_stroke_arc(c + Vector2(-s * 0.235, s * 0.22), s * 0.155, PI * 0.10, PI * 0.90, color, stroke)
	_stroke_arc(c + Vector2(s * 0.235, s * 0.22) + Vector2(0.8, 1.0), s * 0.155, PI * 0.10, PI * 0.90, shadow, stroke)
	_stroke_arc(c + Vector2(s * 0.235, s * 0.22), s * 0.155, PI * 0.10, PI * 0.90, color, stroke)
	# Front shoulders form one broad, unmistakable group base.
	_stroke_arc(c + Vector2(0.0, s * 0.18) + Vector2(0.9, 1.2), s * 0.235, PI * 0.08, PI * 0.92, shadow, stroke * 1.18)
	_stroke_arc(c + Vector2(0.0, s * 0.18) + Vector2(-0.55, -0.6), s * 0.235, PI * 0.10, PI * 0.42, highlight, maxf(1.0, stroke * 0.34))
	_stroke_arc(c + Vector2(0.0, s * 0.18), s * 0.235, PI * 0.08, PI * 0.92, color, stroke * 1.18)

func _draw_book(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var left := PackedVector2Array([
		c + Vector2(-s * 0.39, -s * 0.28), c + Vector2(-s * 0.20, -s * 0.34),
		c + Vector2(-s * 0.045, -s * 0.26), c + Vector2(-s * 0.045, s * 0.34),
		c + Vector2(-s * 0.22, s * 0.26), c + Vector2(-s * 0.39, s * 0.29)
	])
	var right := PackedVector2Array([
		c + Vector2(s * 0.39, -s * 0.28), c + Vector2(s * 0.20, -s * 0.34),
		c + Vector2(s * 0.045, -s * 0.26), c + Vector2(s * 0.045, s * 0.34),
		c + Vector2(s * 0.22, s * 0.26), c + Vector2(s * 0.39, s * 0.29)
	])
	_stroke_path(left, Vector2(1.2, 1.5), shadow, maxf(2.2, s * 0.075), true)
	_stroke_path(right, Vector2(1.2, 1.5), shadow, maxf(2.2, s * 0.075), true)
	_stroke_path(left, Vector2(-0.6, -0.8), highlight, maxf(1.0, s * 0.035), true)
	_stroke_path(right, Vector2(-0.6, -0.8), highlight, maxf(1.0, s * 0.035), true)
	_stroke_path(left, Vector2.ZERO, color, maxf(2.2, s * 0.075), true)
	_stroke_path(right, Vector2.ZERO, color, maxf(2.2, s * 0.075), true)
	draw_line(c + Vector2(0.0, -s * 0.24), c + Vector2(0.0, s * 0.34), shadow, maxf(1.5, s * 0.045), true)
	draw_line(c + Vector2(-s * 0.27, -s * 0.12), c + Vector2(-s * 0.11, -s * 0.07), color, maxf(1.1, s * 0.035), true)
	draw_line(c + Vector2(-s * 0.27, s * 0.02), c + Vector2(-s * 0.11, s * 0.07), color, maxf(1.1, s * 0.035), true)
	draw_line(c + Vector2(s * 0.11, -s * 0.07), c + Vector2(s * 0.27, -s * 0.12), color, maxf(1.1, s * 0.035), true)
	draw_line(c + Vector2(s * 0.11, s * 0.07), c + Vector2(s * 0.27, s * 0.02), color, maxf(1.1, s * 0.035), true)

func _draw_wifi(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var width := maxf(2.4, s * 0.085)
	for scale in [0.46, 0.31, 0.16]:
		var center := c + Vector2(0.0, s * 0.27)
		# The literal scale array is Variant-typed; cast before multiplication so
		# Godot can infer a stable float radius on strict GDScript builds.
		var radius: float = s * float(scale)
		_stroke_arc(center + Vector2(1.0, 1.2), radius, PI * 1.18, PI * 1.82, shadow, width)
		_stroke_arc(center, radius, PI * 1.18, PI * 1.82, color, width)
	draw_circle(c + Vector2(0.8, 1.2), s * 0.065, shadow)
	draw_circle(c, s * 0.065, highlight)
	draw_circle(c, s * 0.05, color)

func _draw_quick(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var radius := s * 0.34
	_stroke_arc(c + Vector2(1.0, 1.5), radius, 0.0, TAU, shadow, maxf(2.2, s * 0.075))
	_stroke_arc(c + Vector2(-0.5, -0.7), radius, 0.0, TAU, highlight, maxf(1.2, s * 0.04))
	_stroke_arc(c, radius, 0.0, TAU, color, maxf(2.2, s * 0.075))
	draw_line(c + Vector2(0.0, -s * 0.47), c + Vector2(0.0, -s * 0.34), color, maxf(2.0, s * 0.07), true)
	draw_line(c + Vector2(-s * 0.12, -s * 0.47), c + Vector2(s * 0.12, -s * 0.47), color, maxf(2.0, s * 0.07), true)
	var bolt := PackedVector2Array([
		c + Vector2(s * 0.08, -s * 0.20), c + Vector2(-s * 0.12, s * 0.04),
		c + Vector2(0.0, s * 0.04), c + Vector2(-s * 0.08, s * 0.22),
		c + Vector2(s * 0.16, -s * 0.04), c + Vector2(s * 0.045, -s * 0.04)
	])
	_filled_shape(bolt, Vector2(0.8, 1.0), shadow)
	_filled_shape(bolt, Vector2.ZERO, color)

func _draw_code(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var width := maxf(2.4, s * 0.09)
	var left := PackedVector2Array([c + Vector2(-s * 0.18, -s * 0.27), c + Vector2(-s * 0.36, 0.0), c + Vector2(-s * 0.18, s * 0.27)])
	var right := PackedVector2Array([c + Vector2(s * 0.18, -s * 0.27), c + Vector2(s * 0.36, 0.0), c + Vector2(s * 0.18, s * 0.27)])
	_stroke_path(left, Vector2(1.0, 1.3), shadow, width, false)
	_stroke_path(right, Vector2(1.0, 1.3), shadow, width, false)
	_stroke_path(left, Vector2.ZERO, color, width, false)
	_stroke_path(right, Vector2.ZERO, color, width, false)
	draw_line(c + Vector2(s * 0.08, -s * 0.31), c + Vector2(-s * 0.08, s * 0.31), highlight, maxf(1.2, s * 0.045), true)
	draw_line(c + Vector2(s * 0.08, -s * 0.31), c + Vector2(-s * 0.08, s * 0.31), color, maxf(1.8, s * 0.065), true)

func _draw_chevron(c: Vector2, s: float, color: Color, shadow: Color, highlight: Color) -> void:
	var path := PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.25), c + Vector2(s * 0.13, 0.0), c + Vector2(-s * 0.12, s * 0.25)])
	_stroke_path(path, Vector2(1.0, 1.2), shadow, maxf(2.2, s * 0.10), false)
	_stroke_path(path, Vector2(-0.6, -0.7), highlight, maxf(1.3, s * 0.055), false)
	_stroke_path(path, Vector2.ZERO, color, maxf(2.2, s * 0.10), false)

func _stroke_arc(center: Vector2, radius: float, start: float, finish: float, color: Color, width: float) -> void:
	draw_arc(center, radius, start, finish, 32, color, width, true)

func _stroke_path(points: PackedVector2Array, offset: Vector2, color: Color, width: float, closed: bool) -> void:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	if closed and shifted.size() > 2:
		shifted.append(shifted[0])
	draw_polyline(shifted, color, width, true)

func _filled_shape(points: PackedVector2Array, offset: Vector2, color: Color) -> void:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	draw_colored_polygon(shifted, color)
