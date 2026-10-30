extends Control

# Multiplayer tug-of-war: a sunken track filled by two raised accent segments sized by score.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")

var mine: float = 1.0
var theirs: float = 1.0
var _shown: float = 0.5
var _track: NeuStyle
var _left: NeuStyle
var _right: NeuStyle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 44.0)
	_track = NeuKit.inset(40.0, 4.0, 10.0)
	_left = NeuKit.accent(NeuKit.COBALT, 40.0, 3.0, 7.0)
	_right = NeuKit.accent(Color("EE4458"), 40.0, 3.0, 7.0)

func set_scores(my_score: int, opp_score: int, animate: bool = true) -> void:
	mine = float(my_score)
	theirs = float(opp_score)
	var total := maxf(1.0, mine + theirs)
	var target := clampf(mine / total, 0.08, 0.92) if (mine + theirs) > 0.0 else 0.5
	if animate and is_inside_tree():
		_shown = 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_method(_set_shown, 0.5, target, 0.8)
	else:
		_shown = target
		queue_redraw()

func _set_shown(v: float) -> void:
	_shown = v
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if _track == null:
		return
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	var pad := 6.0
	var inner := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var split := inner.position.x + inner.size.x * _shown
	var gap := 3.0
	var lw := split - inner.position.x - gap
	var rw := inner.end.x - split - gap
	if lw > 4.0:
		_left.corner_radius = inner.size.y * 0.5
		draw_style_box(_left, Rect2(inner.position, Vector2(lw, inner.size.y)))
	if rw > 4.0:
		_right.corner_radius = inner.size.y * 0.5
		draw_style_box(_right, Rect2(Vector2(split + gap, inner.position.y), Vector2(rw, inner.size.y)))
