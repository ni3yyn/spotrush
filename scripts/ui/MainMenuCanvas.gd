class_name MainMenuCanvas
extends Control

# Animated, interactive part of the menu art: the sculpted emblem dial, the nameplate
# the wordmark sits on, four collectible tokens and tap sparkles.
# The static surface/decor lives in NeuMenuBackdrop so it is not re-drawn every frame.

signal token_clicked(token_name: String)
signal emblem_clicked()

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")

var anim_time: float = 0.0
var tilt_offset: Vector2 = Vector2.ZERO
var target_tilt: Vector2 = Vector2.ZERO
var emblem_pulse_scale: float = 1.0
var particles: Array[Dictionary] = []
var particles_enabled: bool = true

var emblem_center: Vector2 = Vector2.ZERO
var token_eye_pos: Vector2 = Vector2.ZERO
var token_watch_pos: Vector2 = Vector2.ZERO

# 0 = resting, 1 = fully pressed in. Decays back so taps feel like physical keys.
var _press: Dictionary = {"emblem": 0.0, "eye": 0.0, "watch": 0.0}

var _plate: NeuStyle
var _well: NeuStyle
var _plaque: NeuStyle
var _sphere_eye: NeuStyle
var _sphere_watch: NeuStyle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_plate = NeuKit.raised(100.0, 11.0, 26.0)
	_plate.gradient = 0.7
	_well = NeuKit.inset(100.0, 7.0, 16.0)
	_plaque = NeuKit.raised(40.0, 8.0, 18.0)
	_plaque.gradient = 0.6
	_sphere_eye = NeuKit.accent(NeuKit.CANARY, 20.0, 5.0, 11.0)
	_sphere_watch = NeuKit.accent(NeuKit.MINT, 20.0, 5.0, 11.0)
	set_process(true)

func _process(delta: float) -> void:
	anim_time += delta
	tilt_offset = tilt_offset.lerp(target_tilt, delta * 6.0)
	emblem_pulse_scale = move_toward(emblem_pulse_scale, 1.0, delta * 3.2)
	for key in _press.keys():
		_press[key] = move_toward(float(_press[key]), 0.0, delta * 3.4)
	if particles_enabled and not particles.is_empty():
		var surviving: Array[Dictionary] = []
		for particle in particles:
			particle["pos"] += particle["vel"] * delta * 60.0
			particle["alpha"] -= particle["decay"] * delta * 60.0
			if particle["alpha"] > 0.0:
				surviving.append(particle)
		particles = surviving
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var center: Vector2 = size * 0.5
		var normalized_offset: Vector2 = (motion_event.position - center) / maxf(1.0, minf(size.x, size.y))
		target_tilt = Vector2(normalized_offset.x * 5.0, normalized_offset.y * 5.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_background_tap(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_background_tap(event.position)

func _handle_background_tap(pos: Vector2) -> void:
	trigger_sparkles(pos)
	if pos.distance_to(token_eye_pos) <= 34.0:
		accept_event()
		_press["eye"] = 1.0
		token_clicked.emit("Focus Spark")
	elif pos.distance_to(token_watch_pos) <= 34.0:
		accept_event()
		_press["watch"] = 1.0
		token_clicked.emit("Momentum Spark")
	elif pos.distance_to(emblem_center) <= minf(size.x * 0.19, 88.0):
		accept_event()
		emblem_pulse_scale = 0.97
		_press["emblem"] = 1.0
		emblem_clicked.emit()

func trigger_sparkles(pos: Vector2) -> void:
	if not particles_enabled:
		return
	var colors: Array[Color] = [NeuKit.COBALT, NeuKit.CORAL, NeuKit.LAVENDER, NeuKit.CANARY, NeuKit.MINT]
	for i in range(12):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(1.7, 5.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"radius": randf_range(2.0, 4.5),
			"color": colors[randi() % colors.size()],
			"alpha": 0.9,
			"decay": randf_range(0.025, 0.045)
		})

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	_draw_emblem(w, h)
	for particle in particles:
		var color: Color = particle["color"]
		color.a = clampf(float(particle["alpha"]), 0.0, 1.0)
		draw_circle(particle["pos"], float(particle["radius"]), color)

func _draw_emblem(w: float, h: float) -> void:
	var center_y := h * 0.222
	var title_node := get_parent().get_node_or_null("SafeArea/VBoxMain/TitleContainer")
	if title_node is Control and (title_node as Control).size.y > 0.0:
		center_y = (title_node as Control).global_position.y + (title_node as Control).size.y * 0.52
	center_y = clampf(center_y, h * 0.18, h * 0.25)
	emblem_center = Vector2(w * 0.5, center_y) + tilt_offset
	var c := emblem_center
	var radius := minf(w * 0.23, h * 0.135) * emblem_pulse_scale
	var sink := float(_press["emblem"])

	# Dial: a raised plate with a sunken well cut into it. A restrained cobalt
	# atmosphere separates the hero emblem from the similarly coloured backdrop.
	for i in range(4, 0, -1):
		draw_circle(c, radius * (1.12 + float(i) * 0.035), Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.008 * float(5 - i)))
	_plate.depth = lerpf(1.0, 0.3, sink)
	NeuKit.disc(self, _plate, c, radius * 1.12)
	_well.depth = lerpf(-0.85, -1.1, sink)
	NeuKit.disc(self, _well, c, radius * 0.90)

	# Precision-machined orbit: inset ticks, two travelling glints and tiny metal
	# pins. It adds craft at close range without competing with the wordmark.
	var track_r := radius * 1.015
	var drift := sin(anim_time * 0.35) * 0.018
	for i in range(36):
		var ang := TAU * float(i) / 36.0 + drift
		var major := i % 3 == 0
		var tick := radius * (0.038 if major else 0.020)
		var direction := Vector2(cos(ang), sin(ang))
		var tick_color := Color(NeuKit.SLATE.r, NeuKit.SLATE.g, NeuKit.SLATE.b, 0.22 if major else 0.11)
		draw_line(c + direction * (track_r - tick), c + direction * track_r, tick_color, 1.6 if major else 1.0, true)
	var glint_angle := anim_time * 0.16
	draw_arc(c, track_r, glint_angle - 0.35, glint_angle + 0.12, 18, Color(1.0, 1.0, 1.0, 0.58), 2.2, true)
	draw_arc(c, track_r, glint_angle + PI - 0.18, glint_angle + PI + 0.24, 18, Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.24), 2.0, true)
	for ang in [-2.35, -0.79, 0.79, 2.35]:
		var pin := c + Vector2(cos(ang), sin(ang)) * radius * 1.055
		draw_circle(pin + Vector2(0.8, 1.2), 3.1, Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.22))
		draw_circle(pin, 2.5, Color(1.0, 1.0, 1.0, 0.68))

	# Nameplate the wordmark sits on: a raised capsule bridging the well.
	var plaque_width := w * 0.80
	var plaque_height := minf(h * 0.118, w * 0.30)
	_plaque.depth = lerpf(1.0, 0.45, sink)
	NeuKit.capsule(self, _plaque, c, plaque_width, plaque_height)
	var signature_y := c.y + plaque_height * 0.40
	draw_line(Vector2(c.x - plaque_width * 0.24, signature_y), Vector2(c.x + plaque_width * 0.24, signature_y), Color(1.0, 1.0, 1.0, 0.48), 1.4, true)
	draw_line(Vector2(c.x - 27.0, signature_y + 1.0), Vector2(c.x + 27.0, signature_y + 1.0), Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.20), 2.0, true)

	# Four collectible tokens, floating on the dial. Each is a real raised object.
	var float_y := sin(anim_time * 1.25) * 3.5
	var side := w * 0.104
	var cobalt_pos := Vector2(w * 0.342, c.y - radius * 0.90 + float_y)
	var cobalt_pts := NeuKit.round_poly(NeuKit.ngon(cobalt_pos, side * 0.74, 4, deg_to_rad(10.0)), side * 0.27)
	NeuKit.poly_token(self, cobalt_pts, NeuKit.COBALT, 1.0 + float_y * 0.05)

	token_eye_pos = Vector2(w * 0.668, c.y - radius * 0.86 - float_y)
	var p_eye := float(_press["eye"])
	_sphere_eye.depth = lerpf(1.0 + (-float_y) * 0.05, -0.8, p_eye)
	NeuKit.sphere_token(self, _sphere_eye, token_eye_pos, w * 0.049)

	var tri_pos := Vector2(w * 0.352, c.y + radius * 0.74 - float_y)
	var tri_side := w * 0.108
	var tri_pts := NeuKit.round_poly(NeuKit.ngon(tri_pos + Vector2(0.0, tri_side * 0.08), tri_side * 0.62, 3, -PI * 0.5), tri_side * 0.12)
	NeuKit.poly_token(self, tri_pts, NeuKit.CORAL, 1.0 - float_y * 0.05)

	token_watch_pos = Vector2(w * 0.662, c.y + radius * 0.75 + float_y)
	var p_watch := float(_press["watch"])
	_sphere_watch.depth = lerpf(1.0 + float_y * 0.05, -0.8, p_watch)
	NeuKit.sphere_token(self, _sphere_watch, token_watch_pos, w * 0.049)
