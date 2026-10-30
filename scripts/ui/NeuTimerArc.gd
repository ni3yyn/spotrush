extends Control

# Dynamic half of NeuTimerDial: the lit arc inside the groove and the raised centre knob.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")

var _knob: NeuStyle

func _draw() -> void:
	var dial := get_parent()
	if dial == null or not dial.has_method("radius"):
		return
	if _knob == null:
		_knob = NeuKit.raised(50.0, 4.0, 9.0)
		_knob.gradient = 0.7
	var c := size * 0.5
	var r: float = dial.radius()
	if r <= 4.0:
		return
	var ratio: float = dial.ratio
	var col: Color = dial.arc_color()
	var mid: float = r * 0.74
	var width: float = r * 0.17
	if ratio > 0.004:
		var start := -PI * 0.5
		var end := start + TAU * ratio
		var segs := maxi(8, int(64.0 * ratio))
		var urgent: bool = dial.state == "urgent"
		var glow_a: float = 0.20 + (0.12 * (0.5 + 0.5 * sin(dial.pulse * 9.0)) if urgent else 0.0)
		draw_arc(c, mid, start, end, segs, Color(col.r, col.g, col.b, glow_a), width * 2.0, true)
		draw_arc(c, mid, start, end, segs, col.darkened(0.12), width, true)
		draw_arc(c, mid - width * 0.12, start, end, segs, col.lightened(0.18), width * 0.62, true)
		draw_arc(c, mid + width * 0.2, start, end, segs, Color(1.0, 1.0, 1.0, 0.30), width * 0.18, true)
		# Rounded caps.
		var cap_r := width * 0.5
		draw_circle(c + Vector2(cos(start), sin(start)) * mid, cap_r, col.darkened(0.12))
		draw_circle(c + Vector2(cos(end), sin(end)) * mid, cap_r, col.darkened(0.12))
		draw_circle(c + Vector2(cos(end), sin(end)) * mid + Vector2(-cap_r * 0.2, -cap_r * 0.25), cap_r * 0.55, col.lightened(0.18))
	_knob.depth = 1.0 + (0.22 * sin(dial.pulse * 9.0) if dial.state == "urgent" else 0.0) - 1.7 * float(dial.bump_amount)
	NeuKit.disc(self, _knob, c, r * 0.60)
