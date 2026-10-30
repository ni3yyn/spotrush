extends Control

# A whisper of life behind the playfield: oversized, ultra-faint accent orbs on
# slow Lissajous drift, plus the same top-left light wash as the menu art so the
# key light stays consistent. ~8 gradient-disc draw calls; Reduce Motion renders
# one static frame.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _orbs: Array = []
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_orbs()
	set_process(not Feel.reduced())
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _seed_orbs() -> void:
	_orbs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028 # Fixed seed: the composition is art direction, not randomness.
	var palette := [NeuKit.COBALT, NeuKit.MINT, NeuKit.LAVENDER, NeuKit.CANARY, NeuKit.CORAL]
	for i in 6:
		_orbs.append({
			"ux": rng.randf_range(0.04, 0.96),
			"uy": rng.randf_range(0.04, 0.96),
			"ur": rng.randf_range(0.10, 0.20),
			"amp": rng.randf_range(0.015, 0.045),
			"speed": rng.randf_range(0.05, 0.11) * (1.0 if i % 2 == 0 else -1.0),
			"phase": rng.randf_range(0.0, TAU),
			"col": palette[i % palette.size()],
			"alpha": rng.randf_range(0.05, 0.085),
		})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var m := minf(w, h)
	# Ambient key light: bright wash top-left, cool shade bottom-right.
	_soft_disc(Vector2(w * -0.05, h * -0.08), m * 0.75, Color(1.0, 1.0, 1.0), 0.055)
	_soft_disc(Vector2(w * 1.05, h * 1.10), m * 0.80, Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b), 0.045)
	for orb in _orbs:
		var t: float = _time * float(orb.speed) + float(orb.phase)
		var p: Vector2 = Vector2(float(orb.ux) * w, float(orb.uy) * h) + Vector2(cos(t), sin(t * 0.83)) * (float(orb.amp) * m)
		_soft_disc(p, float(orb.ur) * m, orb.col, float(orb.alpha))

## One convex fan with per-vertex alpha falloff - a real soft gradient, not stacked rings.
func _soft_disc(center: Vector2, radius: float, color: Color, alpha: float) -> void:
	if alpha <= 0.001 or radius < 2.0:
		return
	var seg := 28
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(center)
	cols.append(Color(color.r, color.g, color.b, alpha))
	for i in seg + 1:
		var ang := TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
		cols.append(Color(color.r, color.g, color.b, 0.0))
	draw_polygon(pts, cols)
