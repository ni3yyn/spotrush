extends Control

# Row of neumorphic round pips: upcoming = empty sunken socket, current = lit LED,
# answered = raised mint (correct) or coral (wrong) bead.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var total: int = 10
var current: int = 0
var results: Dictionary = {} # round index -> true / false

var _pop: Dictionary = {} # round index -> 0..1 animation progress
var _well: NeuStyle
var _good: NeuStyle
var _bad: NeuStyle

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 32.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_well = NeuKit.inset(10.0, 2.5, 6.0)
	_good = NeuKit.accent(NeuKit.MINT, 10.0, 3.0, 7.0)
	_bad = NeuKit.accent(NeuKit.CORAL, 10.0, 3.0, 7.0)
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func start(total_rounds: int) -> void:
	total = maxi(1, total_rounds)
	results.clear()
	current = 0
	queue_redraw()

func set_current(round_index: int, total_rounds: int = -1) -> void:
	if total_rounds > 0 and total_rounds != total:
		total = total_rounds
	current = round_index
	queue_redraw()

func mark(round_index: int, correct: bool) -> void:
	results[round_index] = correct
	if not Feel.reduced():
		_pop[round_index] = 0.0
		set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	for key in _pop.keys():
		_pop[key] = float(_pop[key]) + delta / 0.5
		if float(_pop[key]) >= 1.0:
			_pop.erase(key)
	queue_redraw()
	if _pop.is_empty():
		set_process(false)

func _draw() -> void:
	if _well == null or total <= 0:
		return
	var spacing := minf(size.x / float(total), 36.0)
	var r := minf(spacing * 0.32, 11.0)
	var start_x := (size.x - spacing * float(total - 1)) * 0.5
	var y := size.y * 0.5
	for i in total:
		var c := Vector2(start_x + spacing * float(i), y)
		if results.has(i):
			var good: bool = bool(results[i])
			var t: float = float(_pop.get(i, 1.0))
			# Overshoot pop plus an expanding ring so a freshly marked pip reads as an event.
			var grow := 1.0 + 0.55 * sin(t * PI) * (1.0 - t * 0.6) if t < 1.0 else 1.0
			NeuKit.disc(self, _good if good else _bad, c, r * grow)
			if t < 1.0:
				var ring: Color = Color("2DBE88") if good else Color("EE4458")
				draw_arc(c, r * (1.2 + 2.0 * t), 0.0, TAU, 28, Color(ring.r, ring.g, ring.b, 0.55 * (1.0 - t)), 2.5, true)
		else:
			NeuKit.disc(self, _well, c, r)
			if i == current:
				draw_circle(c, r * 1.5, Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.14))
				draw_circle(c, r * 0.55, NeuKit.COBALT)
				draw_circle(c + Vector2(-r * 0.16, -r * 0.18), r * 0.18, Color(1.0, 1.0, 1.0, 0.7))
