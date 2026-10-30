extends Control

# Gameplay FX layer for GameScreen: light that answers the player.
#   edge_flash() - soft accent wash bleeding in from the screen edges on every answer
#   spotlight()  - searchlight ring that sweeps out over the challenge as a round begins
#   halo()       - a spotlight ring that closes in on the countdown card, then snaps out
#   pop()        - punch-scale for readouts (score settle), like a physical key
# Purely additive drawing, mouse-transparent, sleeps when idle.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _flashes: Array = [] # {"col", "a", "decay"}
var _sweeps: Array = []  # {"rect", "t", "dur", "col"}
var _halos: Array = []   # {"rect", "t", "dur", "col"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _has_work() -> bool:
	return not _flashes.is_empty() or not _sweeps.is_empty() or not _halos.is_empty()

## Accent light from the four edges. strength 0..1.5; decays exponentially.
func edge_flash(color: Color, strength := 1.0) -> void:
	if Feel.reduced():
		strength *= 0.35
	_flashes.append({"col": color, "a": 0.34 * strength, "decay": 2.6})
	_wake()

## Expanding searchlight ring that settles over the freshly dealt challenge.
func spotlight(global_rect: Rect2, color: Color = NeuKit.COBALT) -> void:
	if Feel.reduced():
		return
	var xf := get_global_transform()
	_sweeps.append({"rect": Rect2(xf.affine_inverse() * global_rect.position, global_rect.size * xf.get_scale()), "t": 0.0, "dur": 0.6, "col": color})
	_wake()

## Ring that contracts around `global_rect` over `duration`, throb-quickens, then snaps.
func halo(global_rect: Rect2, duration: float, color: Color = NeuKit.COBALT) -> void:
	if duration <= 0.05:
		return
	var xf := get_global_transform()
	_halos.append({"rect": Rect2(xf.affine_inverse() * global_rect.position, global_rect.size * xf.get_scale()), "t": 0.0, "dur": duration, "col": color})
	_wake()

## Punch-scale a readout: peak then settle.
func pop(control: Control, peak := 1.14) -> void:
	if Feel.reduced() or control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "scale", Vector2(peak, peak), 0.09)
	tw.tween_property(control, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _wake() -> void:
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	for fl in _flashes:
		fl.a = float(fl.a) * exp(-float(fl.decay) * delta)
	_flashes = _flashes.filter(func(fl): return float(fl.a) > 0.012)
	for sw in _sweeps:
		sw.t = float(sw.t) + delta
	_sweeps = _sweeps.filter(func(sw): return float(sw.t) < float(sw.dur))
	for hh in _halos:
		hh.t = float(hh.t) + delta
	_halos = _halos.filter(func(hh): return float(hh.t) < float(hh.dur) + 0.22)
	if not _has_work():
		set_process(false)
	queue_redraw()

func _draw() -> void:
	var sw := size.x
	var sh := size.y
	if sw < 4.0 or sh < 4.0:
		return
	# Answer washes: accent light bleeding in from the four edges.
	var band := minf(sw, sh) * 0.16
	for fl in _flashes:
		var wash: Color = fl.col
		var wa: float = fl.a
		var wcol := Color(wash.r, wash.g, wash.b, wa)
		var wzero := Color(wash.r, wash.g, wash.b, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sw, 0), Vector2(sw, band), Vector2(0, band)]), PackedColorArray([wcol, wcol, wzero, wzero]))
		draw_polygon(PackedVector2Array([Vector2(0, sh), Vector2(sw, sh), Vector2(sw, sh - band), Vector2(0, sh - band)]), PackedColorArray([wcol, wcol, wzero, wzero]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(band, 0), Vector2(band, sh), Vector2(0, sh)]), PackedColorArray([wcol, wzero, wzero, wcol]))
		draw_polygon(PackedVector2Array([Vector2(sw, 0), Vector2(sw, sh), Vector2(sw - band, sh), Vector2(sw - band, 0)]), PackedColorArray([wcol, wcol, wzero, wzero]))
	# Round-start searchlight sweep.
	for sww in _sweeps:
		var k := clampf(float(sww.t) / float(sww.dur), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var srect: Rect2 = sww.rect
		var sc := srect.get_center()
		var sr := lerpf(srect.size.length() * 0.18, srect.size.length() * 0.5 + 46.0, e)
		var sa := (1.0 - e) * 0.8
		var scol: Color = sww.col
		draw_arc(sc, sr, 0.0, TAU, 96, Color(scol, sa), 5.0)
		draw_arc(sc, sr, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, sa * 0.5), 2.0)
		_soft_disc(sc, sr, scol, sa * 0.10)
	# Countdown halo: the spotlight closes in on the card, then snaps out.
	for hh in _halos:
		var hrect: Rect2 = hh.rect
		var hc := hrect.get_center()
		var hbase := hrect.size.length() * 0.5
		var hk := clampf(float(hh.t) / float(hh.dur), 0.0, 1.0)
		var hover := maxf(0.0, float(hh.t) - float(hh.dur))
		var hcol: Color = hh.col
		if hover > 0.0:
			var rel := clampf(hover / 0.22, 0.0, 1.0)
			var ease_out := 1.0 - pow(1.0 - rel, 2.0)
			var fade := (1.0 - rel) * (1.0 - rel)
			if fade > 0.0:
				var rr := hbase * (1.0 + ease_out * 0.65)
				draw_arc(hc, rr, 0.0, TAU, 96, Color(hcol, 0.9 * fade), 6.0)
				draw_arc(hc, rr, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.5 * fade), 2.5)
			continue
		var throb := sin(float(hh.t) * 9.0) * 2.0
		var hr := lerpf(hbase * 1.22, hbase * 0.94, hk) + throb
		var urg := smoothstep(0.75, 1.0, hk)
		if urg > 0.0:
			hcol = hcol.lerp(NeuKit.CANARY, urg * 0.7)
		var ha := 0.55 + urg * 0.35
		draw_arc(hc, hr, 0.0, TAU, 96, Color(hcol, ha), 5.0)
		draw_arc(hc, hr, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, ha * 0.4), 2.0)

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
