extends StyleBox

# Soft-UI ("neumorphic") surface material.
#
# One surface colour, lit from the top-left:
#   depth > 0  -> RAISED : light shadow up-left, dark shadow down-right, convex sheen
#   depth < 0  -> INSET  : dark inner shadow up-left, light inner shadow down-right
#   depth = 0  -> flat
#
# `depth` is continuous, so a button can animate smoothly from raised to pressed-in
# (see NeuKit.attach_motion). Shadows are built from stacked translucent rounded rects
# whose alphas are solved so the *composited* result follows a smooth falloff; this is
# what gives the soft blur that StyleBoxFlat's single shadow cannot do in two directions.

@export var surface: Color = Color("E4E9F2")
@export var light: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var dark: Color = Color(0.60, 0.66, 0.79, 0.62)
## Optional coloured under-glow for accent surfaces (alpha 0 = off).
@export var glow: Color = Color(0.0, 0.0, 0.0, 0.0)
## True for accent-coloured surfaces: inset shadows are derived from the surface itself.
@export var colored: bool = false
@export var corner_radius: float = 22.0
## Shadow offset in px at |depth| = 1.
@export var distance: float = 7.0
## Shadow softness in px at |depth| = 1.
@export var blur: float = 16.0
## Strength of the convex / concave sheen across the face (0..1).
@export_range(0.0, 1.0) var gradient: float = 0.55
## Optional performance cap for repeated small surfaces (0 = automatic quality).
## Challenge tokens use this to keep dense boards inexpensive to redraw.
@export_range(0, 10, 1) var shadow_steps_override: int = 0
## Strength of the 1px lit rim on the top-left edge of raised surfaces.
@export_range(0.0, 1.0) var rim: float = 0.7
@export var depth: float = 1.0:
	set(value):
		if is_equal_approx(depth, value):
			return
		depth = value
		emit_changed()

# Motion targets used by NeuKit.attach_motion().
var depth_rest: float = 1.0
var depth_hover: float = 1.2
var depth_press: float = -0.9

var _f: StyleBoxFlat
# Geometry cache: identical shapes (e.g. ten token sockets) share one computed mesh.
var _mesh_cache: Dictionary = {}
static var _alpha_steps_cache: Dictionary = {}

func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(distance * 1.6 + blur * 1.2)

func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var r := minf(corner_radius, minf(rect.size.x, rect.size.y) * 0.5)
	var a := absf(depth)
	var fade := clampf(a / 0.25, 0.0, 1.0)
	var n := clampi(int(round(blur * a / 1.8)), 3, 10)
	if shadow_steps_override > 0:
		n = clampi(shadow_steps_override, 3, 10)

	if depth > 0.02:
		var off := distance * a
		var spread := blur * a
		_shadow(ci, rect, r, Vector2(off, off), spread, n, _fade(dark, fade))
		_shadow(ci, rect, r, Vector2(-off, -off), spread, n, _fade(light, fade))
		if glow.a > 0.001:
			_shadow(ci, rect, r, Vector2(0.0, off * 1.3), spread * 1.1, n, _fade(glow, minf(a, 1.0) * fade))

	_fill(ci, rect, r, surface)

	if gradient > 0.0 and a > 0.02:
		_sheen(ci, rect, r, a * fade, depth > 0.0)

	if depth > 0.02:
		_rim(ci, rect, r, fade)
	elif depth < -0.02:
		var ioff := distance * a * 0.75
		var ispread := blur * a * 0.8
		var d_col := dark
		var l_col := light
		if colored:
			d_col = Color(surface.darkened(0.55), 0.85)
			l_col = Color(surface.lightened(0.45), 0.6)
		_inner(ci, rect, r, Vector2(ioff, ioff), ispread, n, _fade(d_col, fade))
		_inner(ci, rect, r, Vector2(-ioff, -ioff), ispread, n, _fade(l_col, fade))

# --- internals -----------------------------------------------------------------

static func _fade(c: Color, k: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * k)

## Per-layer alphas such that N stacked translucent layers composite to a smoothstep
## falloff ending at `total`. Layer k covers everything layers k+1.. cover, so the
## visible alpha in band k is 1 - prod(1 - a_j) for j >= k; we solve for a_k directly.
static func alpha_steps(total: float, n: int) -> PackedFloat32Array:
	var safe_n := maxi(1, n)
	var key := "%d:%.4f" % [safe_n, total]
	if _alpha_steps_cache.has(key):
		return _alpha_steps_cache[key]
	var out := PackedFloat32Array()
	for k in safe_n:
		var c0 := total * (1.0 - smoothstep(0.0, 1.0, float(k) / float(safe_n)))
		var c1 := total * (1.0 - smoothstep(0.0, 1.0, float(k + 1) / float(safe_n)))
		out.append(clampf(1.0 - (1.0 - c0) / maxf(0.0001, 1.0 - c1), 0.0, 1.0))
	if _alpha_steps_cache.size() >= 128:
		_alpha_steps_cache.clear()
	_alpha_steps_cache[key] = out
	return out

func _flat() -> StyleBoxFlat:
	if _f == null:
		_f = StyleBoxFlat.new()
		_f.anti_aliasing = true
	_f.draw_center = true
	_f.border_width_left = 0
	_f.border_width_top = 0
	_f.border_width_right = 0
	_f.border_width_bottom = 0
	return _f

func _fill(ci: RID, rect: Rect2, radius: float, color: Color) -> void:
	var f := _flat()
	f.bg_color = color
	f.set_corner_radius_all(int(round(clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5))))
	f.draw(ci, rect)

func _shadow(ci: RID, rect: Rect2, r: float, offset: Vector2, spread: float, n: int, color: Color) -> void:
	if color.a <= 0.002 or spread < 0.5:
		return
	var al := alpha_steps(color.a, n)
	for k in n:
		var e := -spread * 0.5 + spread * float(k + 1) / float(n)
		var rr := rect.grow(e)
		if rr.size.x < 1.0 or rr.size.y < 1.0:
			continue
		rr.position += offset
		_fill(ci, rr, r + e, Color(color.r, color.g, color.b, al[k]))

## Inner shadow as ONE gradient mesh instead of stacked border rings: the shape outline is
## pushed inward by a per-vertex thickness (thicker on the edges facing the light) while
## vertex alpha fades smoothly to zero. Two draw calls per inset keeps the canvas light and
## avoids the huge ring-draw counts that corrupted batching on some drivers.
func _inner(ci: RID, rect: Rect2, r: float, offset: Vector2, spread: float, _n: int, color: Color) -> void:
	if color.a <= 0.002 or spread < 0.5:
		return
	var key := "i%.1f,%.1f,%.1f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f" % [rect.size.x, rect.size.y, r, offset.x, offset.y, spread, color.r, color.g, color.b, color.a]
	if not _mesh_cache.has(key):
		if _mesh_cache.size() > 64:
			_mesh_cache.clear()
		_mesh_cache[key] = _build_inner(rect.size, r, offset, spread, color)
	var entry: Dictionary = _mesh_cache[key]
	if entry.is_empty():
		return
	var moved: PackedVector2Array = Transform2D(0.0, rect.position) * (entry["points"] as PackedVector2Array)
	RenderingServer.canvas_item_add_triangle_array(ci, entry["indices"], moved, entry["colors"])

func _build_inner(rect_size: Vector2, r: float, offset: Vector2, spread: float, color: Color) -> Dictionary:
	var edge := Rect2(Vector2.ZERO, rect_size).grow(-0.7)
	var rad := maxf(r - 0.7, 0.0)
	var outline := _rounded_poly(edge, rad)
	var count := outline.size()
	if count < 3:
		return {}
	var center := edge.get_center()
	var max_depth := minf(edge.size.x, edge.size.y) * 0.5 * 0.92
	var depth_cap := max_depth
	if rad > 1.0:
		depth_cap = minf(max_depth, rad * 0.9 + 4.0)
	var t_stops := [0.0, 0.25, 0.5, 0.75, 1.0]
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in count:
		points.append(outline[i])
		colors.append(color)
	var normals := PackedVector2Array()
	var ring_depths: Array = []
	for i in count:
		var tangent := outline[(i + 1) % count] - outline[(i - 1 + count) % count]
		var nrm := Vector2(tangent.y, -tangent.x).normalized()
		if nrm.dot(outline[i] - center) < 0.0:
			nrm = -nrm
		normals.append(nrm)
		# Thicker on the edges that face the light, thinner on the far side.
		var thick := spread * 0.5 - nrm.dot(offset)
		var d1 := clampf(thick - spread * 0.5, 0.0, depth_cap)
		ring_depths.append(Vector2(d1, clampf(thick + spread * 0.5, d1, depth_cap)))
	for stop in t_stops:
		var alpha: float = color.a * (1.0 - smoothstep(0.0, 1.0, stop))
		for i in count:
			var dd: Vector2 = ring_depths[i]
			points.append(outline[i] - normals[i] * lerpf(dd.x, dd.y, stop))
			colors.append(Color(color.r, color.g, color.b, alpha))
	var indices := PackedInt32Array()
	for ring in t_stops.size():
		for i in count:
			var i2 := (i + 1) % count
			var a0 := ring * count + i
			var a1 := ring * count + i2
			var b0 := (ring + 1) * count + i
			var b1 := (ring + 1) * count + i2
			indices.append_array([a0, a1, b0, a1, b1, b0])
	return {"points": points, "colors": colors, "indices": indices}

func _rim(ci: RID, rect: Rect2, r: float, fade: float) -> void:
	if rim <= 0.0:
		return
	var f := _flat()
	f.draw_center = false
	f.set_corner_radius_all(int(round(r)))
	f.border_width_left = 1
	f.border_width_top = 1
	f.border_color = Color(1.0, 1.0, 1.0, rim * fade * (0.45 if colored else 0.9))
	f.draw(ci, rect)

func _sheen(ci: RID, rect: Rect2, r: float, strength: float, convex: bool) -> void:
	var s: float = minf(strength, 1.2) * gradient
	var key := "s%.1f,%.1f,%.1f,%.3f,%d" % [rect.size.x, rect.size.y, r, s, 1 if convex else 0]
	if not _mesh_cache.has(key):
		if _mesh_cache.size() > 64:
			_mesh_cache.clear()
		var local := Rect2(Vector2.ZERO, rect.size)
		var pts := _rounded_poly(local.grow(-0.75), maxf(r - 0.75, 0.0))
		var c := local.get_center()
		var span := maxf(1.0, rect.size.x + rect.size.y)
		var cl := PackedColorArray()
		var cd := PackedColorArray()
		for p in pts:
			var t := clampf(0.5 + ((p.x - c.x) + (p.y - c.y)) / span, 0.0, 1.0)
			var la := s * 0.34 * (1.0 - t)
			var da := s * 0.20 * t
			if not convex:
				la = s * 0.16 * t
				da = s * 0.16 * (1.0 - t)
			cl.append(Color(1.0, 1.0, 1.0, la))
			cd.append(Color(dark.r * 0.6, dark.g * 0.6, dark.b * 0.7, da))
		_mesh_cache[key] = {"pts": pts, "cl": cl, "cd": cd}
	var entry: Dictionary = _mesh_cache[key]
	var moved: PackedVector2Array = Transform2D(0.0, rect.position) * (entry["pts"] as PackedVector2Array)
	RenderingServer.canvas_item_add_polygon(ci, moved, entry["cl"])
	RenderingServer.canvas_item_add_polygon(ci, moved, entry["cd"])

static func _rounded_poly(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	if r < 0.5:
		pts.append(rect.position)
		pts.append(Vector2(rect.end.x, rect.position.y))
		pts.append(rect.end)
		pts.append(Vector2(rect.position.x, rect.end.y))
		return pts
	var seg := clampi(int(r / 3.0), 3, 8)
	var centers := [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r)
	]
	for ci_idx in 4:
		var start := -PI * 0.5 + float(ci_idx) * PI * 0.5
		for i in seg + 1:
			var ang := start + (PI * 0.5) * float(i) / float(seg)
			var pt: Vector2 = centers[ci_idx] + Vector2(cos(ang), sin(ang)) * r
			# Pills and circles make neighbouring arcs meet at one point; duplicate
			# vertices make the triangulator reject the polygon, so skip repeats.
			if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(pt) > 0.01:
				pts.append(pt)
	if pts.size() > 1 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.01:
		pts.remove_at(pts.size() - 1)
	return pts
