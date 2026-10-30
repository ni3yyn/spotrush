extends Control

# Rank medal: raised plate with etched minute marks, a sunken ring and a raised, tinted
# face carrying the grade letter. `pop()` plays a springy entrance.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

var rank: String = "A":
	set(value):
		rank = value
		queue_redraw()

var _plate: NeuStyle
var _well: NeuStyle
var _face: NeuStyle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 190.0), maxf(custom_minimum_size.y, 190.0))
	_plate = NeuKit.raised(100.0, 10.0, 24.0)
	_plate.gradient = 0.7
	_well = NeuKit.inset(100.0, 6.0, 14.0)
	_face = NeuKit.accent(NeuKit.COBALT, 100.0, 6.0, 14.0)
	_face.gradient = 0.9
	pivot_offset = size * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
		queue_redraw()

func face_color() -> Color:
	match rank:
		"S": return NeuKit.CANARY
		"A": return NeuKit.COBALT
		"B": return NeuKit.MINT
		_: return Color("8A99B8")

func pop(delay: float = 0.0) -> void:
	scale = Vector2(0.55, 0.55)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.55).set_delay(delay)
	tw.tween_property(self, "modulate:a", 1.0, 0.2).set_delay(delay)

func _draw() -> void:
	if _plate == null:
		return
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 14.0
	NeuKit.disc(self, _plate, c, r)
	for i in 16:
		var a := TAU * float(i) / 16.0 - PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * r * 0.93
		draw_circle(p + Vector2(0.8, 0.9), 1.7, Color(1.0, 1.0, 1.0, 0.9))
		draw_circle(p, 1.7, Color(NeuKit.MUTED.r, NeuKit.MUTED.g, NeuKit.MUTED.b, 0.55))
	NeuKit.disc(self, _well, c, r * 0.84)
	var col := face_color()
	_face.surface = col
	_face.glow = Color(col.r, col.g, col.b, 0.5 if rank == "S" else 0.35)
	NeuKit.disc(self, _face, c, r * 0.68)
	var font: Font = NeuKit.bold_font(self, 0.7)
	var fs := mini(int(r * 1.05), SpotRushTypography.size(SpotRushTypography.Role.HERO_SCORE))
	var w := font.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.1)
	var deep := col.darkened(0.6)
	var high := col.lightened(0.55)
	draw_string(font, pos + Vector2(3.0, 4.5), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(deep.r, deep.g, deep.b, 0.30))
	draw_string(font, pos + Vector2(1.6, 2.4), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(deep.r, deep.g, deep.b, 0.55))
	draw_string(font, pos + Vector2(-1.0, -1.4), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(high.r, high.g, high.b, 0.55))
	draw_string(font, pos, rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
