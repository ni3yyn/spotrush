extends RefCounted

# SpotRush neumorphic toolkit: palette, style factories, click-depth motion and the
# canvas helpers used by the menu art. One light source (top-left) everywhere.

const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Feel = preload("res://scripts/core/Feel.gd")

# --- palette ---------------------------------------------------------------------
# Change SURFACE / LIGHT / DARK to re-skin the whole game (e.g. warm cream: E9E2D2 / FFFFFF / C9BDA3).
const SURFACE: Color = Color("E4E9F2")
const LIGHT: Color = Color(1.0, 1.0, 1.0, 0.95)
const DARK: Color = Color(0.60, 0.66, 0.79, 0.62)
const INK: Color = Color("1E2432")
const SLATE: Color = Color("56668A")
const MUTED: Color = Color("8190AC")
const COBALT: Color = Color("2B52E2")
const CORAL: Color = Color("FF5964")
const CANARY: Color = Color("F4B82F")
const MINT: Color = Color("3FCB93")
const LAVENDER: Color = Color("7C5CFC")

# --- style factories -------------------------------------------------------------

static func raised(radius: float = 20.0, dist: float = 6.0, blur: float = 14.0, surface: Color = SURFACE) -> NeuStyle:
		var s := NeuStyle.new()
		s.surface = surface
		s.corner_radius = radius
		s.distance = dist
		s.blur = blur
		s.depth = 1.0
		s.depth_rest = 1.0
		s.depth_hover = 1.2
		s.depth_press = -0.9
		_margins(s, 12.0, 8.0)
		return s

static func inset(radius: float = 20.0, dist: float = 5.0, blur: float = 12.0, surface: Color = SURFACE) -> NeuStyle:
		var s := raised(radius, dist, blur, surface)
		s.depth = -0.85
		s.depth_rest = -0.85
		s.depth_hover = -0.7
		s.depth_press = -1.15
		s.gradient = 0.5
		return s

static func accent(color: Color, radius: float = 20.0, dist: float = 7.0, blur: float = 16.0) -> NeuStyle:
		var s := raised(radius, dist, blur, color)
		s.colored = true
		s.glow = Color(color.r, color.g, color.b, 0.42)
		s.gradient = 0.8
		s.rim = 0.7
		return s

static func disabled_look(radius: float = 20.0) -> NeuStyle:
		var s := raised(radius, 3.0, 7.0, SURFACE.darkened(0.04))
		s.depth = 0.35
		s.gradient = 0.2
		return s

static func _margins(s: StyleBox, h: float, v: float) -> void:
		s.content_margin_left = h
		s.content_margin_right = h
		s.content_margin_top = v
		s.content_margin_bottom = v

static func _focus_ring(radius: float) -> StyleBoxFlat:
		var f := StyleBoxFlat.new()
		f.draw_center = false
		f.set_border_width_all(2)
		f.border_color = Color(COBALT.r, COBALT.g, COBALT.b, 0.55)
		f.set_corner_radius_all(int(radius))
		f.expand_margin_left = 3.0
		f.expand_margin_right = 3.0
		f.expand_margin_top = 3.0
		f.expand_margin_bottom = 3.0
		return f

## Gives a button its neumorphic body and click-depth motion.
## kind: "raised" (default) | "primary" (cobalt) | "well" (inset readout) | "accent:<hex>"
static func style_button(btn: BaseButton, kind: String = "raised", radius: float = 20.0) -> NeuStyle:
		# Screens run the skin over nested scenes more than once; keep the first (animated) style.
		if btn.has_meta("neu_style"):
				return btn.get_meta("neu_style")
		var s: NeuStyle
		if kind == "primary":
				s = accent(COBALT, radius, 8.0, 18.0)
		elif kind.begins_with("accent:"):
				s = accent(Color(kind.substr(7)), radius, 8.0, 18.0)
		elif kind == "well":
				s = inset(radius, 5.0, 11.0)
		else:
				s = raised(radius, 6.0, 14.0)
		_margins(s, 10.0, 8.0)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
				btn.add_theme_stylebox_override(state, s)
		btn.add_theme_stylebox_override("disabled", disabled_look(radius))
		btn.add_theme_stylebox_override("focus", _focus_ring(radius))
		btn.set_meta("neu_style", s)
		attach_motion(btn, s)
		return s

## Gives a LineEdit a sunken "well" look, matching the inset trays/sockets used
## elsewhere, with the same cobalt focus ring as buttons instead of Godot's
## default flat box.
static func style_line_edit(edit: LineEdit, radius: float = 18.0) -> NeuStyle:
		var s := inset(radius, 4.0, 10.0)
		_margins(s, 16.0, 10.0)
		edit.add_theme_stylebox_override("normal", s)
		edit.add_theme_stylebox_override("read_only", disabled_look(radius))
		edit.add_theme_stylebox_override("focus", _focus_ring(radius))
		edit.add_theme_color_override("font_color", INK)
		edit.add_theme_color_override("font_placeholder_color", MUTED)
		edit.add_theme_color_override("caret_color", COBALT)
		edit.add_theme_color_override("selection_color", Color(COBALT.r, COBALT.g, COBALT.b, 0.28))
		return s

## Re-tint a button created with style_button() in place: accent colour, or plain surface.
static func set_accent(btn: BaseButton, color: Color) -> void:
		if not btn.has_meta("neu_style"):
				return
		var s: NeuStyle = btn.get_meta("neu_style")
		s.surface = color
		s.colored = true
		s.glow = Color(color.r, color.g, color.b, 0.42)
		s.gradient = 0.8
		s.emit_changed()

static func set_plain(btn: BaseButton) -> void:
		if not btn.has_meta("neu_style"):
				return
		var s: NeuStyle = btn.get_meta("neu_style")
		s.surface = SURFACE
		s.colored = false
		s.glow = Color(0.0, 0.0, 0.0, 0.0)
		s.gradient = 0.55
		s.emit_changed()

## Persistent "selected" look for toggle-like buttons (round count, tabs, etc.).
static func set_selected(btn: BaseButton, on: bool) -> void:
		if not btn.has_meta("neu_style"):
				return
		var s: NeuStyle = btn.get_meta("neu_style")
		s.depth_rest = -0.95 if on else 1.0
		s.depth_hover = -0.8 if on else 1.2
		s.depth_press = -1.2 if on else -0.9
		_settle(btn, s, 0.24, Tween.TRANS_CUBIC)

# --- click-depth motion ------------------------------------------------------------

static func attach_motion(btn: BaseButton, s: NeuStyle) -> void:
		if btn.has_meta("neu_motion"):
				return
		btn.set_meta("neu_motion", true)
		btn.set_meta("neu_held", false)
		btn.mouse_entered.connect(_on_enter.bind(btn, s))
		btn.mouse_exited.connect(_on_exit.bind(btn, s))
		btn.button_down.connect(_on_down.bind(btn, s))
		btn.button_up.connect(_on_up.bind(btn, s))
		btn.toggled.connect(func(_on: bool) -> void: _settle(btn, s, 0.24, Tween.TRANS_CUBIC))

static func _on_enter(btn: BaseButton, s: NeuStyle) -> void:
		if not btn.get_meta("neu_held", false) and not btn.disabled:
				_tween(btn, s, s.depth_hover if not _is_on(btn) else s.depth_press, 0.18, Tween.TRANS_CUBIC)

static func _on_exit(btn: BaseButton, s: NeuStyle) -> void:
		if not btn.get_meta("neu_held", false):
				_settle(btn, s, 0.24, Tween.TRANS_CUBIC)

static func _on_down(btn: BaseButton, s: NeuStyle) -> void:
		btn.set_meta("neu_held", true)
		_tween(btn, s, s.depth_press, 0.07, Tween.TRANS_QUAD)
		# Feel: a soft "thock" with slight pitch variation (so repeats never sound identical),
		# a light haptic tap, and a tiny squish of the whole key.
		Feel.sfx("press", randf_range(0.94, 1.06))
		Feel.haptic("light")
		_squish(btn, 0.974, 0.07, Tween.TRANS_QUAD)

static func _on_up(btn: BaseButton, s: NeuStyle) -> void:
		btn.set_meta("neu_held", false)
		# Springy release: the surface pops back out slightly past its resting height.
		_settle(btn, s, 0.34, Tween.TRANS_BACK)
		Feel.sfx("release", randf_range(0.97, 1.05))
		_squish(btn, 1.0, 0.34, Tween.TRANS_BACK)

static func _squish(btn: BaseButton, target: float, dur: float, trans: Tween.TransitionType) -> void:
		if Feel.reduced() or not is_instance_valid(btn) or not btn.is_inside_tree():
				return
		btn.pivot_offset = btn.size * 0.5
		if btn.has_meta("neu_sq"):
				var old: Tween = btn.get_meta("neu_sq")
				if old != null and old.is_valid():
						old.kill()
		var tw := btn.create_tween().set_trans(trans).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(target, target), dur)
		btn.set_meta("neu_sq", tw)

static func _is_on(btn: BaseButton) -> bool:
		return btn.toggle_mode and btn.button_pressed

static func _settle(btn: BaseButton, s: NeuStyle, dur: float, trans: Tween.TransitionType) -> void:
		var target := s.depth_rest
		if _is_on(btn):
				target = s.depth_press
		elif btn.is_hovered() and not btn.disabled:
				target = s.depth_hover
		_tween(btn, s, target, dur, trans)

static func _tween(btn: BaseButton, s: NeuStyle, target: float, dur: float, trans: Tween.TransitionType) -> void:
		if not is_instance_valid(btn) or not btn.is_inside_tree():
				s.depth = target
				return
		if btn.has_meta("neu_tw"):
				var old: Tween = btn.get_meta("neu_tw")
				if old != null and old.is_valid():
						old.kill()
		var tw := btn.create_tween().set_trans(trans).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "depth", target, dur)
		btn.set_meta("neu_tw", tw)

# --- text -------------------------------------------------------------------------

## Bold weight derived from the control's own theme font (works with any project font).
## Pins the variable font's REAL "wght" axis (Baloo 2 ships 400-800) so text reads
## genuinely heavy instead of relying on fake-bold alone, then adds a small outline
## embolden on top. If a font has no wght axis the tag is ignored and the embolden
## still thickens the face, so this stays safe with any project font.
static func bold_font(ctl: Control, amount: float = 0.5) -> Font:
		var base: Font = ctl.get_theme_default_font()
		if base == null:
				base = ThemeDB.fallback_font
		return weighted_font(base, 700.0, minf(amount, 0.26))

## A FontVariation pinned to a real OpenType weight axis value plus optional
## outline embolden. UI text sits on wght 700; the display wordmark takes 800.
static func weighted_font(base: Font, weight: float = 700.0, embolden: float = 0.0) -> Font:
		var fv := FontVariation.new()
		fv.base_font = base
		if base.fallbacks != null:
				fv.fallbacks = base.fallbacks
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		if embolden > 0.0:
				fv.variation_embolden = embolden
		return fv

## Letterpress text: a 1px white lip under dark text reads as etched into the surface.
static func etch(node: Control, on_dark: bool = false) -> void:
		var col := Color(0.0, 0.0, 0.0, 0.28) if on_dark else Color(1.0, 1.0, 1.0, 0.95)
		var oy := 1 if not on_dark else 2
		node.add_theme_color_override("font_shadow_color", col)
		node.add_theme_constant_override("shadow_offset_x", 0 if on_dark else 1)
		node.add_theme_constant_override("shadow_offset_y", oy)

# --- canvas shape helpers (Control._draw) --------------------------------------------

static func disc(ci: CanvasItem, style: NeuStyle, center: Vector2, radius: float) -> void:
		style.corner_radius = radius
		ci.draw_style_box(style, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0))

static func capsule(ci: CanvasItem, style: NeuStyle, center: Vector2, width: float, height: float) -> void:
		style.corner_radius = height * 0.5
		ci.draw_style_box(style, Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height)))

static func ngon(center: Vector2, radius: float, sides: int, rotation: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in sides:
				var a := rotation + TAU * float(i) / float(sides)
				pts.append(center + Vector2(cos(a), sin(a)) * radius)
		return pts

static func round_poly(pts: PackedVector2Array, r: float) -> PackedVector2Array:
		var shrunk := Geometry2D.offset_polygon(pts, -r, Geometry2D.JOIN_MITER)
		if shrunk.is_empty():
				return pts
		var grown := Geometry2D.offset_polygon(shrunk[0], r, Geometry2D.JOIN_ROUND)
		return grown[0] if not grown.is_empty() else pts

## A neumorphic polygon token: the same one-light material NeuStyle gives rounded
## surfaces, built for arbitrary shapes (diamonds, triangles, menu gems).
## lift: 1 = floating on the surface, 0 = lying flat, negative = pressed into it.
static func poly_token(ci: CanvasItem, pts: PackedVector2Array, base: Color, lift: float = 1.0, scale: float = 1.0, steps: int = 7, shadow_strength: float = 1.0) -> void:
		if pts.size() < 3:
				return
		var k := clampf(lift, 0.0, 1.15)
		# 0 = floating, 1 = fully sunken (cast shadows gone, inner shading takes over).
		var press := clampf(1.0 - lift / 0.35, 0.0, 1.0)
		var center := Vector2.ZERO
		for p in pts:
				center += p
		center /= float(pts.size())
		var reach := 6.0
		for p in pts:
				reach = maxf(reach, (p - center).length())

		# Cast shadows: soft dual falloff (dark down-right, light up-left, coloured
		# contact glow) that thins out as the token sinks toward the surface.
		if press < 1.0:
				var d := 7.5 * lift * scale
				var spread := 17.0 * lift * scale
				var lift_a := clampf(k, 0.0, 1.0) * (1.0 - press)
				if spread > 0.5 and lift_a > 0.01:
						var layers := [
										[Vector2(d, d), DARK],
										[Vector2(-d, -d), LIGHT],
										[Vector2(0.0, d * 1.3), Color(base.r, base.g, base.b, 0.38)]
						]
						# All three shadow colours use the same expanded geometry. Build it
						# once per radius, then reuse it instead of offsetting the polygon
						# three times for every shadow step.
						var shadow_polys: Array = []
						for s in steps:
							var e := -spread * 0.5 + spread * float(s + 1) / float(steps)
							shadow_polys.append(Geometry2D.offset_polygon(pts, e, Geometry2D.JOIN_ROUND))
						for layer in layers:
							var off: Vector2 = layer[0]
							var col: Color = layer[1]
							col = Color(col.r, col.g, col.b, col.a * shadow_strength)
							var al := NeuStyle.alpha_steps(col.a * lift_a, steps)
							for s in steps:
								for poly in shadow_polys[s]:
									if poly.size() >= 3:
										ci.draw_colored_polygon(Transform2D(0.0, off) * poly, Color(col.r, col.g, col.b, al[s]))

		if press > 0.0:
				# Sunken: the cast shadows collapse into a tight contact shadow.
				var grow := 1.5 + 2.0 * press
				for poly in Geometry2D.offset_polygon(pts, grow, Geometry2D.JOIN_ROUND):
						if poly.size() >= 3:
								ci.draw_colored_polygon(Transform2D(0.0, Vector2(0.0, grow * 0.6)) * poly, Color(DARK.r, DARK.g, DARK.b, 0.32 * press))

		# Body: dark sidewall first (it peeks out along the bottom-right edge), with
		# an antialiased silhouette stroke so the shape never looks jagged.
		var wall := base.darkened(0.27)
		ci.draw_colored_polygon(pts, wall)
		var outline := pts.duplicate()
		outline.append(pts[0])
		ci.draw_polyline(outline, wall, 1.7, true)

		# Face: smooth per-vertex sheen - brighter toward the top-left light, darker
		# across the far side, mirroring the gradient NeuStyle paints on boxes.
		var face := Geometry2D.offset_polygon(pts, -1.6, Geometry2D.JOIN_ROUND)
		if not face.is_empty() and face[0].size() >= 3:
				var fpts: PackedVector2Array = face[0]
				var span := maxf(reach * 2.4, 1.0)
				var cols := PackedColorArray()
				for p in fpts:
						var t := clampf(0.5 + ((p.x - center.x) + (p.y - center.y)) / span, 0.0, 1.0)
						cols.append(base.lightened(0.24 * (1.0 - t) * k + 0.03).lerp(base.darkened(0.22 * t + 0.03), t))
				ci.draw_polygon(fpts, cols)

		# Edges: a lit rim on the slopes facing the light and a dark wall on the far
		# side; sunken tokens flip to an engraved pit (dark near wall, lit far wall).
		var ring := pts if press <= 0.0 else _inset_ring(pts, 2.2)
		var m := ring.size()
		for i in m:
				var a: Vector2 = ring[i]
				var b: Vector2 = ring[(i + 1) % m]
				var edge := b - a
				if edge.length() < 0.5:
						continue
				var mid := (a + b) * 0.5
				var nrm := Vector2(edge.y, -edge.x).normalized()
				if nrm.dot(mid - center) < 0.0:
						nrm = -nrm
				var face_k := nrm.dot(Vector2(-0.70710678, -0.70710678))
				if press <= 0.0:
						if face_k > 0.08:
								ci.draw_line(a, b, Color(1.0, 1.0, 1.0, 0.70 * k * face_k * shadow_strength), 2.6, true)
						elif face_k < -0.08:
								ci.draw_line(a, b, Color(wall.r, wall.g, wall.b, 0.55 * k * -face_k), 2.6, true)
				else:
						if face_k > 0.08:
								ci.draw_line(a, b, Color(DARK.r, DARK.g, DARK.b, 0.34 * press * face_k), 2.6, true)
						elif face_k < -0.08:
								ci.draw_line(a, b, Color(1.0, 1.0, 1.0, 0.38 * press * -face_k), 1.8, true)

		# Small specular near the lit shoulder - the finishing touch while raised.
		if k > 0.4 and press < 0.4:
				ci.draw_circle(center + Vector2(-reach * 0.30, -reach * 0.34), maxf(1.6, reach * 0.115), Color(1.0, 1.0, 1.0, 0.34 * k))

static func _inset_ring(pts: PackedVector2Array, amount: float) -> PackedVector2Array:
		var inner := Geometry2D.offset_polygon(pts, -amount, Geometry2D.JOIN_ROUND)
		if inner.is_empty():
				return pts
		return inner[0]

## Spherical token: raised colour disc with a convex sheen and a small specular.
static func sphere_token(ci: CanvasItem, style: NeuStyle, center: Vector2, radius: float, specular_alpha: float = 0.62) -> void:
		disc(ci, style, center, radius)
		ci.draw_circle(center + Vector2(-radius * 0.33, -radius * 0.37), radius * 0.19, Color(1.0, 1.0, 1.0, specular_alpha * clampf(style.depth, 0.0, 1.0)))

# --- spot-mark ----------------------------------------------------------------------

# Cache of sculpted pieces the mark is built from, keyed by kind + rounded px radius
# (the entrance bloom rescales the mark every frame, so caching keeps that cheap).
static var _mark_cache: Dictionary = {}

static func _mark_style(kind: String, radius: float) -> NeuStyle:
		var key := "%s-%d" % [kind, int(radius)]
		if _mark_cache.has(key):
				return _mark_cache[key]
		if _mark_cache.size() > 96:
				_mark_cache.clear()
		var s: NeuStyle
		match kind:
				"well":
						s = inset(radius, 8.0, 19.0)
						s.depth = -0.9
				"dimple":
						s = inset(radius, 5.5, 12.0)
						s.depth = -1.05
						s.surface = SURFACE.darkened(0.05)
				"bead":
						s = raised(radius, 3.4, 7.0)
						s.depth = 1.2
				_:
						s = raised(radius)
		_mark_cache[key] = s
		return s

## The SpotRush mark as a pressed neumorphic sculpture: a soft ambient lift, a
## shallow well, an engraved groove ring, a deep centre dimple and three small
## raised beads rolling around the groove. Monochrome by design - the mark gets
## its depth entirely from the one top-left light source.
##
## This is the SINGLE source of truth for the mark: BootScreen draws it while
## loading, NeuWipe draws it on the sealed curtain, and the two must be
## pixel-identical for the boot -> menu handoff to be seamless. Draw it on a
## dedicated layer and fade that layer's modulate.a (stylebox pieces cannot be
## faded per-colour).
static func draw_spot_mark(ci: CanvasItem, center: Vector2, ring_r: float, time: float, orbit: bool) -> void:
		if ring_r < 2.0:
				return
		# Soft white presence halo under the sculpture (same radial glow the
		# backdrop uses, so it never band against the pad lighting).
		var halo_size := ring_r * 5.2
		ci.draw_texture_rect(glow_texture(Color(1.0, 1.0, 1.0, 0.30)), Rect2(center - Vector2(halo_size, halo_size) * 0.5, Vector2(halo_size, halo_size)), false)
		# Shallow well pressed into the surface.
		disc(ci, _mark_style("well", ring_r * 1.62), center, ring_r * 1.62)
		# Engraved groove: dark cut with the lit lower lip just below it.
		ci.draw_arc(center, ring_r, 0.0, TAU, 96, Color(DARK.r, DARK.g, DARK.b, 0.42), 3.2, true)
		ci.draw_arc(center + Vector2(0.0, 2.0), ring_r + 0.5, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.5), 1.5, true)
		# Deep centre dimple.
		disc(ci, _mark_style("dimple", ring_r * 0.46), center, ring_r * 0.46)
		# Three raised beads rolling around the groove - the only raised accents,
		# kept surface-toned so the mark stays quiet and sculptural.
		if orbit:
				for i in 3:
						var ang := time * 2.6 + float(i) * TAU / 3.0
						var p := center + Vector2(cos(ang), sin(ang)) * ring_r
						disc(ci, _mark_style("bead", 7.0), p, 7.0)
						ci.draw_circle(p + Vector2(-2.0, -2.2), 1.9, Color(1.0, 1.0, 1.0, 0.85))

# --- backdrop -------------------------------------------------------------------------

static var _glow_cache: Dictionary = {}

## Public access to the shared radial-glow textures (curtain shader samples the
## same two glows the backdrop paints, so the pad lighting matches everywhere).
static func glow_texture(color: Color) -> GradientTexture2D:
		return _glow(color)

static func _glow(color: Color) -> GradientTexture2D:
		var key := color.to_html(true)
		if _glow_cache.has(key):
				return _glow_cache[key]
		var g := Gradient.new()
		g.set_color(0, color)
		g.set_color(1, Color(color.r, color.g, color.b, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_glow_cache[key] = t
		return t

## Flat surface with a soft light falloff (lit from top-left) and optional sculpted decor.
static func draw_backdrop(ci: Control, decor: bool = true) -> void:
		var w := ci.size.x
		var h := ci.size.y
		if w <= 0.0 or h <= 0.0:
				return
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), SURFACE)
		var big := maxf(w, h) * 1.5
		ci.draw_texture_rect(_glow(Color(1.0, 1.0, 1.0, 0.65)), Rect2(Vector2(-big * 0.5, -big * 0.42), Vector2(big, big)), false)
		ci.draw_texture_rect(_glow(Color(DARK.r, DARK.g, DARK.b, 0.24)), Rect2(Vector2(w - big * 0.45, h - big * 0.45), Vector2(big, big)), false)
		if not decor:
				return
		# Sculpted corners: a raised dial bottom-left, an inset well bottom-right, small satellites.
		var r1 := w * 0.34
		var dial := raised(r1, 14.0, 30.0)
		disc(ci, dial, Vector2(-w * 0.03, h * 1.02), r1)
		var well1 := inset(r1, 8.0, 18.0)
		disc(ci, well1, Vector2(-w * 0.03, h * 1.02), r1 * 0.58)
		var r2 := w * 0.30
		var well2 := inset(r2, 10.0, 22.0)
		disc(ci, well2, Vector2(w * 1.04, h * 1.0), r2)
		var knob := raised(r2 * 0.5, 9.0, 20.0)
		disc(ci, knob, Vector2(w * 1.04, h * 1.0), r2 * 0.5)
		var r3 := w * 0.115
		var sat := raised(r3, 9.0, 20.0)
		disc(ci, sat, Vector2(w * 1.02, h * 0.30), r3)
		var r4 := w * 0.13
		var well3 := inset(r4, 7.0, 16.0)
		disc(ci, well3, Vector2(-w * 0.045, h * 0.43), r4)
