extends Control

# Round-by-round score chart inside a sunken tray. Raised capsule bars:
# mint = scored, coral = lost points, hollow socket = timeout, gold + crown = best round.
# Bars grow in with a stagger (animate_in) and overshoot slightly like a spring.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Records = preload("res://scripts/core/Records.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

var scores: Array = []
var best_index: int = -1

var _grow: float = 1.0
var _tray: NeuStyle
var _good: NeuStyle
var _bad: NeuStyle
var _best: NeuStyle
var _hollow: NeuStyle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 230.0)
	_tray = NeuKit.inset(26.0, 8.0, 18.0)
	_tray.depth = -0.9
	_good = NeuKit.accent(Color("2DBE88"), 20.0, 4.0, 9.0)
	_bad = NeuKit.accent(Color("EE4458"), 20.0, 4.0, 9.0)
	_best = NeuKit.accent(NeuKit.CANARY, 20.0, 5.0, 11.0)
	_hollow = NeuKit.inset(20.0, 2.5, 6.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func set_data(round_scores: Array, best: int) -> void:
	scores = round_scores
	best_index = best
	queue_redraw()

func animate_in(delay: float = 0.0) -> void:
	_grow = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_LINEAR)
	tw.tween_interval(delay)
	tw.tween_method(_set_grow, 0.0, 1.0, 0.7 + 0.05 * float(scores.size()))

func _set_grow(v: float) -> void:
	_grow = v
	queue_redraw()

static func _back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

func _draw() -> void:
	if _tray == null:
		return
	draw_style_box(_tray, Rect2(Vector2.ZERO, size))
	var n := scores.size()
	if n == 0:
		return
	var area := Rect2(26.0, 46.0, size.x - 52.0, size.y - 46.0 - 46.0)
	var max_abs := 1.0
	var has_neg := false
	for s in scores:
		max_abs = maxf(max_abs, absf(float(s)))
		if float(s) < 0.0:
			has_neg = true
	var base_y := area.end.y if not has_neg else area.position.y + area.size.y * 0.72
	var up_h := base_y - area.position.y
	var down_h := area.end.y - base_y

	# Etched guide lines.
	for g in 3:
		var gy := base_y - up_h * float(g) / 2.0
		draw_line(Vector2(area.position.x - 8.0, gy + 1.0), Vector2(area.end.x + 8.0, gy + 1.0), Color(1.0, 1.0, 1.0, 0.9), 1.5)
		draw_line(Vector2(area.position.x - 8.0, gy), Vector2(area.end.x + 8.0, gy), Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.32), 1.5)

	if not has_neg and max_abs <= 1.0:
		# Nothing scored: say so instead of leaving an empty tray.
		var f: Font = NeuKit.bold_font(self, 0.5)
		var msg := "No points this time"
		var sub := "Answer faster next round!"
		var title_size := SpotRushTypography.size(SpotRushTypography.Role.SCREEN_TITLE)
		var sub_size := SpotRushTypography.size(SpotRushTypography.Role.CARD_TITLE)
		var mw := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var my := area.position.y + area.size.y * 0.30
		draw_string(f, Vector2((size.x - mw) * 0.5 + 1.0, my + 1.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(1.0, 1.0, 1.0, 0.95))
		draw_string(f, Vector2((size.x - mw) * 0.5, my), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, NeuKit.SLATE)
		draw_string(f, Vector2((size.x - sw) * 0.5 + 1.0, my + 38.0 + 1.5), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(1.0, 1.0, 1.0, 0.95))
		draw_string(f, Vector2((size.x - sw) * 0.5, my + 38.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, NeuKit.MUTED)

	var cell := area.size.x / float(n)
	var bar_w := clampf(cell * 0.58, 12.0, 58.0)
	var font: Font = NeuKit.bold_font(self, 0.5)
	for i in n:
		var cx := area.position.x + cell * (float(i) + 0.5)
		var val := float(scores[i])
		var p := clampf(_grow * float(n + 3) - float(i), 0.0, 1.0)
		var e := _back(p) if p > 0.0 else 0.0
		var is_best := i == best_index and val > 0.0
		if absf(val) < 0.5:
			_hollow.corner_radius = bar_w * 0.5
			var hs := minf(bar_w, 44.0)
			draw_style_box(_hollow, Rect2(Vector2(cx - hs * 0.5, base_y - hs), Vector2(hs, hs)))
			# A tiny dash marks "no answer" so a timeout never looks like missing data.
			draw_line(Vector2(cx - hs * 0.18, base_y - hs * 0.5), Vector2(cx + hs * 0.18, base_y - hs * 0.5), NeuKit.MUTED, 3.0, true)
		else:
			var h := maxf(bar_w * 0.9, absf(val) / max_abs * (up_h if val > 0.0 else down_h)) * e
			var rect := Rect2(cx - bar_w * 0.5, base_y - h, bar_w, h) if val > 0.0 else Rect2(cx - bar_w * 0.5, base_y, bar_w, h)
			var style: NeuStyle = _best if is_best else (_good if val > 0.0 else _bad)
			style.corner_radius = bar_w * 0.5
			draw_style_box(style, rect)
			if is_best and p >= 1.0:
				_draw_crown(Vector2(cx, rect.position.y - 22.0))
				var label := "+%d" % int(val)
				var caption_size := SpotRushTypography.size(SpotRushTypography.Role.BODY)
				var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
				draw_string(font, Vector2(cx - lw * 0.5 + 1.0, rect.position.y - 36.0 + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, Color(1.0, 1.0, 1.0, 0.9))
				draw_string(font, Vector2(cx - lw * 0.5, rect.position.y - 36.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size, Color("B07A0A"))
		# Round number, engraved under the chart.
		var num := str(i + 1)
		var round_size := SpotRushTypography.size(SpotRushTypography.Role.BODY_STRONG)
		var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, round_size).x
		draw_string(font, Vector2(cx - nw * 0.5 + 1.0, size.y - 16.0 + 1.5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, round_size, Color(1.0, 1.0, 1.0, 0.95))
		draw_string(font, Vector2(cx - nw * 0.5, size.y - 16.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, round_size, NeuKit.SLATE)

func _draw_crown(c: Vector2) -> void:
	var k := 22.0
	var pts := PackedVector2Array([
		c + Vector2(-k * 0.9, k * 0.5), c + Vector2(-k, -k * 0.4), c + Vector2(-k * 0.45, k * 0.05),
		c + Vector2(0.0, -k * 0.75), c + Vector2(k * 0.45, k * 0.05), c + Vector2(k, -k * 0.4), c + Vector2(k * 0.9, k * 0.5)
	])
	draw_colored_polygon(Transform2D(0.0, Vector2(1.2, 1.8)) * pts, Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.45))
	draw_colored_polygon(pts, NeuKit.CANARY)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color("C4891A"), 1.5, true)
