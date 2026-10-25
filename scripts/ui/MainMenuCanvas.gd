class_name MainMenuCanvas
extends Control

signal token_clicked(token_name: String)
signal emblem_clicked()

# Floating time accumulator
var anim_time: float = 0.0

# Mouse/touch tilt state
var tilt_offset: Vector2 = Vector2.ZERO
var target_tilt: Vector2 = Vector2.ZERO
var emblem_pulse_scale: float = 1.0

# Dynamic particle system
var particles: Array[Dictionary] = []
var particles_enabled: bool = true

# Theme Colors
const COLOR_BUTTER: Color = Color("FAF5E8")
const COLOR_BUTTER_DARK: Color = Color("EDE5D0")
const COLOR_COBALT: Color = Color("2B52E2")
const COLOR_COBALT_LIGHT: Color = Color("6185FF")
const COLOR_COBALT_DARK: Color = Color("122C99")
const COLOR_TANGERINE: Color = Color("FF6B35")
const COLOR_TANGERINE_LIGHT: Color = Color("FFB290")
const COLOR_TANGERINE_DARK: Color = Color("BA3B0C")
const COLOR_CORAL: Color = Color("FF5964")
const COLOR_CORAL_LIGHT: Color = Color("FFA2A8")
const COLOR_CORAL_DARK: Color = Color("B81B26")
const COLOR_LAVENDER: Color = Color("7C5CFC")
const COLOR_LAVENDER_LIGHT: Color = Color("9C80FF")
const COLOR_LAVENDER_DARK: Color = Color("5333D0")
const COLOR_CANARY: Color = Color("F4CB38")
const COLOR_CANARY_LIGHT: Color = Color("FDE67A")
const COLOR_CANARY_DARK: Color = Color("C49B0E")
const COLOR_DARK_NAVY: Color = Color("1E2432")
const COLOR_SHADOW_WARM: Color = Color(0.76, 0.72, 0.61, 0.45)
const COLOR_WHITE: Color = Color("FFFFFF")

# Interactive emblem bounds
var emblem_center: Vector2 = Vector2.ZERO
var token_eye_pos: Vector2 = Vector2.ZERO
var token_watch_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)

func _process(delta: float) -> void:
	anim_time += delta
	tilt_offset = tilt_offset.lerp(target_tilt, delta * 8.0)
	emblem_pulse_scale = move_toward(emblem_pulse_scale, 1.0, delta * 3.0)
	
	# Update particles
	if particles_enabled and not particles.is_empty():
		var surviving: Array[Dictionary] = []
		for p in particles:
			p["pos"] += p["vel"] * delta * 60.0
			p["alpha"] -= p["decay"] * delta * 60.0
			if p["alpha"] > 0.0:
				surviving.append(p)
		particles = surviving
		
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var center = size * 0.5
		var norm = (event.position - center) / maxf(1.0, minf(size.x, size.y))
		target_tilt = Vector2(norm.x * 12.0, norm.y * 12.0)
		
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos = event.position
		trigger_sparkles(pos)
		
		# Check token clicks
		if pos.distance_to(token_eye_pos) <= 24.0:
			accept_event()
			token_clicked.emit("Vision Pulse Token")
			return
		elif pos.distance_to(token_watch_pos) <= 24.0:
			accept_event()
			token_clicked.emit("Chrono Boost Token")
			return
			
		# Check central emblem click
		if pos.distance_to(emblem_center) <= 90.0:
			accept_event()
			emblem_pulse_scale = 0.92
			emblem_clicked.emit()
			return

func trigger_sparkles(pos: Vector2) -> void:
	if not particles_enabled:
		return
	var colors = [COLOR_COBALT, COLOR_TANGERINE, COLOR_CORAL, COLOR_LAVENDER, COLOR_CANARY]
	for i in range(16):
		var angle = randf_range(0.0, TAU)
		var spd = randf_range(2.0, 7.5)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle) * spd, sin(angle) * spd),
			"radius": randf_range(3.0, 6.5),
			"color": colors[randi() % colors.size()],
			"alpha": 1.0,
			"decay": randf_range(0.02, 0.045)
		})

func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 0 or h <= 0:
		return
		
	# 1. Base Butter Background
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BUTTER)
	
	# Subtle outer phone border inset
	var inset = 6.0
	draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)), COLOR_BUTTER_DARK, false, 3.0)
	
	# 2. Background 3D Sculpted Geometrics
	_draw_background_geometrics(w, h)
	
	# 3. Central 3D Layered SpotRush Artifact Emblem
	_draw_central_emblem(w, h)
	
	# 4. Particles
	for p in particles:
		var c = p["color"]
		c.a = clampf(p["alpha"], 0.0, 1.0)
		draw_circle(p["pos"], p["radius"], c)

func _draw_background_geometrics(w: float, h: float) -> void:
	# A. Top-Left Large Cobalt Sphere (floating slowly)
	var f1 = sin(anim_time * 1.05) * 8.0
	var pos_a = Vector2(w * 0.04, h * 0.03 + f1)
	_draw_3d_sphere(pos_a, w * 0.28, COLOR_COBALT, COLOR_COBALT_LIGHT, COLOR_COBALT_DARK)
	
	# B. Top-Right Coral Red Torus Ring (reverse floating)
	var f2 = cos(anim_time * 0.95) * 9.0
	var pos_b = Vector2(w * 0.98, h * 0.05 + f2)
	_draw_3d_torus_ring(pos_b, w * 0.24, w * 0.065, COLOR_CORAL, COLOR_CORAL_LIGHT, COLOR_CORAL_DARK)
	
	# C. Middle-Left Lavender Squircle (floating, rotated 12 deg)
	var f3 = sin(anim_time * 0.85 + 1.2) * 7.0
	var pos_c = Vector2(w * 0.02, h * 0.42 + f3)
	_draw_3d_squircle(pos_c, w * 0.20, deg_to_rad(12.0), COLOR_LAVENDER, COLOR_LAVENDER_LIGHT, COLOR_LAVENDER_DARK)
	
	# D. Middle-Right Canary Yellow Squircle (floating, rotated -12 deg)
	var f4 = cos(anim_time * 0.9 + 2.1) * 8.0
	var pos_d = Vector2(w * 0.98, h * 0.52 + f4)
	_draw_3d_squircle(pos_d, w * 0.17, deg_to_rad(-12.0), COLOR_CANARY, COLOR_CANARY_LIGHT, COLOR_CANARY_DARK)
	
	# E. Bottom-Right Oversized Tangerine Sphere
	var f5 = sin(anim_time * 1.1 + 0.5) * 8.0
	var pos_e = Vector2(w * 0.95, h * 0.94 + f5)
	_draw_3d_sphere(pos_e, w * 0.32, COLOR_TANGERINE, COLOR_TANGERINE_LIGHT, COLOR_TANGERINE_DARK)

func _draw_central_emblem(w: float, h: float) -> void:
	# Emblem is centered vertically around upper-middle (38% of screen height)
	emblem_center = Vector2(w * 0.5, h * 0.38) + tilt_offset
	var ec = emblem_center
	var base_r = minf(w, h) * 0.20 * emblem_pulse_scale
	
	# 1. Orbital Dotted/Dashed Ring (Slow continuous spin)
	var spin_angle = anim_time * 0.35
	var orbit_r = base_r * 1.42
	_draw_dashed_circle(ec, orbit_r, COLOR_LAVENDER, 2.5, 24, spin_angle)
	
	# 2. Concentric Outer Cobalt Blue Ring with Neumorphic Drop Shadow
	draw_circle(ec + Vector2(6, 10), base_r * 1.15, COLOR_SHADOW_WARM)
	draw_arc(ec, base_r * 1.12, 0, TAU, 48, COLOR_COBALT, 14.0, true)
	# Outer ring bevel specular
	draw_arc(ec - Vector2(2, 2), base_r * 1.12, -PI * 0.75, PI * 0.25, 32, Color(1, 1, 1, 0.45), 3.0, true)
	
	# 3. Recessed Inner Ring Groove (neu-pressed)
	var groove_r = base_r * 0.92
	draw_circle(ec, groove_r, Color("F3ECDC"))
	draw_arc(ec - Vector2(1, 1), groove_r, 0, TAU, 36, Color("B9AC8E", 0.6), 3.0, true)
	draw_arc(ec + Vector2(1, 1), groove_r, 0, TAU, 36, Color(1, 1, 1, 0.8), 3.0, true)
	
	# 4. Tilted Coral Ring Overlay Line (-35 deg tilt)
	var tilt_rad = deg_to_rad(-35.0)
	_draw_rotated_ellipse(ec, base_r * 1.35, base_r * 0.48, tilt_rad, COLOR_CORAL, 5.0)
	
	# 5. Central 3D Purple Diamond Squircle (rotated 45 deg) - corners pop out
	var sqr_size = base_r * 0.95
	_draw_3d_squircle(ec, sqr_size, deg_to_rad(45.0), COLOR_LAVENDER, COLOR_LAVENDER_LIGHT, COLOR_LAVENDER_DARK)
	
	# 6. Center High-Glint Tangerine Lightning Sphere (pulsing)
	var pulse_glow = 1.0 + (sin(anim_time * 3.0) * 0.06)
	var sphere_r = base_r * 0.44 * pulse_glow
	# Glow halo
	draw_circle(ec, sphere_r * 1.3, Color(1.0, 0.42, 0.21, 0.28))
	_draw_3d_sphere(ec, sphere_r, COLOR_TANGERINE, COLOR_TANGERINE_LIGHT, COLOR_TANGERINE_DARK)
	
	# Draw crisp white lightning bolt icon in center
	_draw_lightning_bolt(ec, sphere_r * 0.68, COLOR_WHITE)
	
	# 7. Orbiting Small Collectible Tokens
	# Top-Right: Vision Pulse Token (Coral squircle with eye symbol)
	var f_tok1 = sin(anim_time * 1.2) * 5.0
	token_eye_pos = ec + Vector2(base_r * 0.88, -base_r * 0.92 + f_tok1)
	_draw_collectible_token(token_eye_pos, 18.0, COLOR_CORAL, "eye")
	
	# Bottom-Left: Chrono Boost Token (Cobalt circle with stopwatch symbol)
	var f_tok2 = cos(anim_time * 1.1) * 5.0
	token_watch_pos = ec + Vector2(-base_r * 0.92, base_r * 0.85 + f_tok2)
	_draw_collectible_token(token_watch_pos, 18.0, COLOR_COBALT, "watch")

# --- PRIMITIVE 3D DRAWING HELPERS ---

func _draw_3d_sphere(center: Vector2, radius: float, base_col: Color, light_col: Color, dark_col: Color) -> void:
	# Drop shadow
	draw_circle(center + Vector2(radius * 0.18, radius * 0.26), radius * 0.96, COLOR_SHADOW_WARM)
	
	# Dark base
	draw_circle(center, radius, dark_col)
	
	# Midtone blend
	var mid_offset = center - Vector2(radius * 0.08, radius * 0.08)
	draw_circle(mid_offset, radius * 0.85, base_col)
	
	# Specular highlight
	var spec_offset = center - Vector2(radius * 0.32, radius * 0.32)
	draw_circle(spec_offset, radius * 0.46, light_col)
	draw_circle(spec_offset - Vector2(radius * 0.08, radius * 0.08), radius * 0.18, Color(1, 1, 1, 0.85))

func _draw_3d_torus_ring(center: Vector2, outer_r: float, thickness: float, base_col: Color, light_col: Color, dark_col: Color) -> void:
	# Drop shadow
	draw_arc(center + Vector2(6, 10), outer_r - (thickness * 0.5), 0, TAU, 40, COLOR_SHADOW_WARM, thickness, true)
	
	# Main ring
	draw_arc(center, outer_r - (thickness * 0.5), 0, TAU, 40, base_col, thickness, true)
	
	# Top specular highlight arc
	draw_arc(center - Vector2(2, 2), outer_r - (thickness * 0.3), -PI * 0.8, PI * 0.1, 24, light_col, thickness * 0.35, true)
	
	# Bottom inner shadow arc
	draw_arc(center + Vector2(2, 2), outer_r - (thickness * 0.7), PI * 0.2, PI * 0.9, 24, dark_col, thickness * 0.35, true)

func _draw_3d_squircle(center: Vector2, sz: float, angle_rad: float, base_col: Color, light_col: Color, dark_col: Color) -> void:
	# Drop shadow
	_draw_rotated_rounded_rect(center + Vector2(6, 9), sz, sz, sz * 0.28, angle_rad, COLOR_SHADOW_WARM)
	
	# Dark base
	_draw_rotated_rounded_rect(center, sz, sz, sz * 0.28, angle_rad, dark_col)
	
	# Midtone
	_draw_rotated_rounded_rect(center - Vector2(sz * 0.06, sz * 0.06), sz * 0.90, sz * 0.90, sz * 0.25, angle_rad, base_col)
	
	# Specular highlight corner
	_draw_rotated_rounded_rect(center - Vector2(sz * 0.14, sz * 0.14), sz * 0.55, sz * 0.55, sz * 0.20, angle_rad, light_col)

func _draw_rotated_rounded_rect(center: Vector2, w: float, h: float, corner_r: float, angle_rad: float, col: Color) -> void:
	var pts: PackedVector2Array = []
	var half_w = (w * 0.5) - corner_r
	var half_h = (h * 0.5) - corner_r
	
	var corners = [
		Vector2(half_w, half_h),    # Bottom-right
		Vector2(-half_w, half_h),   # Bottom-left
		Vector2(-half_w, -half_h),  # Top-left
		Vector2(half_w, -half_h)    # Top-right
	]
	
	for i in range(4):
		var base_pt = corners[i]
		var start_ang = float(i) * (PI * 0.5)
		for s in range(5):
			var a = start_ang + (float(s) / 4.0 * PI * 0.5)
			var offset = Vector2(cos(a) * corner_r, sin(a) * corner_r)
			var pt = (base_pt + offset).rotated(angle_rad) + center
			pts.append(pt)
			
	draw_colored_polygon(pts, col)

func _draw_rotated_ellipse(center: Vector2, rx: float, ry: float, angle_rad: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = []
	var steps = 40
	for i in range(steps + 1):
		var th = (float(i) / float(steps)) * TAU
		var p = Vector2(cos(th) * rx, sin(th) * ry).rotated(angle_rad) + center
		pts.append(p)
	draw_polyline(pts, col, width, true)

func _draw_dashed_circle(center: Vector2, radius: float, col: Color, width: float, segments: int, rot_offset: float) -> void:
	var step = TAU / float(segments)
	for i in range(segments):
		if i % 2 == 0:
			var start_ang = rot_offset + (float(i) * step)
			var end_ang = start_ang + (step * 0.65)
			draw_arc(center, radius, start_ang, end_ang, 8, col, width, true)

func _draw_lightning_bolt(center: Vector2, sz: float, col: Color) -> void:
	var pts = PackedVector2Array([
		center + Vector2(sz * 0.12, -sz * 0.95),
		center + Vector2(-sz * 0.45, -sz * 0.05),
		center + Vector2(-sz * 0.05, -sz * 0.05),
		center + Vector2(-sz * 0.22, sz * 0.95),
		center + Vector2(sz * 0.48, sz * 0.02),
		center + Vector2(sz * 0.06, sz * 0.02)
	])
	draw_colored_polygon(pts, col)

func _draw_collectible_token(center: Vector2, radius: float, base_col: Color, icon_type: String) -> void:
	# Drop shadow
	draw_circle(center + Vector2(2, 4), radius, COLOR_SHADOW_WARM)
	# Token body
	draw_circle(center, radius, base_col)
	draw_arc(center, radius, 0, TAU, 24, Color(1, 1, 1, 0.4), 1.5, true)
	
	if icon_type == "eye":
		# Eye icon
		var eye_w = radius * 0.65
		var eye_h = radius * 0.35
		_draw_rotated_ellipse(center, eye_w, eye_h, 0.0, COLOR_WHITE, 1.8)
		draw_circle(center, radius * 0.22, COLOR_WHITE)
	elif icon_type == "watch":
		# Stopwatch icon
		draw_arc(center, radius * 0.52, 0, TAU, 20, COLOR_WHITE, 1.8, true)
		# Top button
		draw_line(center - Vector2(0, radius * 0.52), center - Vector2(0, radius * 0.75), COLOR_WHITE, 2.0)
		# Hands
		draw_line(center, center - Vector2(0, radius * 0.35), COLOR_WHITE, 1.6)
		draw_line(center, center + Vector2(radius * 0.25, 0), COLOR_WHITE, 1.6)
