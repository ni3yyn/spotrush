extends Control

# Neumorphic countdown dial: raised plate, sunken groove, a lit arc that drains as time
# runs out (cobalt -> canary -> coral) and a raised knob that carries the seconds label.
# The plate/groove are static (redrawn on resize/state only); the arc layer redraws per tick.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const ArcLayerScript = preload("res://scripts/ui/NeuTimerArc.gd")

var ratio: float = 1.0
var state: String = "calm"
var pulse: float = 0.0
## 0..1, decays quickly: pressed-in look of the knob after bump() (a clock-tick feel).
var bump_amount: float = 0.0
## When alpha > 0 the arc uses this colour regardless of state (used as an accuracy gauge).
var custom_color: Color = Color(0, 0, 0, 0)

var _plate: NeuStyle
var _well: NeuStyle
var _arc_layer: Control
var _last_ratio_redraw_usec: int = 0
var _pulse_redraw_accumulator: float = 0.0
const VISUAL_REFRESH_INTERVAL: float = 1.0 / 30.0

func _ready() -> void:
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 132.0), maxf(custom_minimum_size.y, 132.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = NeuKit.raised(100.0, 8.0, 18.0)
	_plate.gradient = 0.7
	_well = NeuKit.inset(100.0, 5.0, 11.0)
	_arc_layer = Control.new()
	_arc_layer.set_script(ArcLayerScript)
	_arc_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arc_layer)
	move_child(_arc_layer, 0) # arc + knob sit under the seconds label
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func radius() -> float:
	return minf(size.x, size.y) * 0.5 - 10.0

func arc_color() -> Color:
	if custom_color.a > 0.0:
		return custom_color
	match state:
		"warn": return NeuKit.CANARY
		"urgent": return NeuKit.CORAL
		_: return NeuKit.COBALT

func set_time(remaining: float, total: float) -> void:
	var next_ratio := clampf(remaining / maxf(total, 0.001), 0.0, 1.0)
	if is_equal_approx(next_ratio, ratio):
		return
	ratio = next_ratio
	var now_usec := Time.get_ticks_usec()
	var should_redraw := _last_ratio_redraw_usec == 0 \
			or now_usec - _last_ratio_redraw_usec >= int(VISUAL_REFRESH_INTERVAL * 1000000.0) \
			or ratio <= 0.0 or ratio >= 1.0
	if should_redraw:
		_last_ratio_redraw_usec = now_usec
		_arc_layer.queue_redraw()

func set_state(new_state: String) -> void:
	if new_state == state:
		return
	state = new_state
	set_process(state == "urgent" or bump_amount > 0.0)
	if state != "urgent":
		pulse = 0.0
	_arc_layer.queue_redraw()

func bump() -> void:
	bump_amount = 1.0
	set_process(true)

func _process(delta: float) -> void:
	pulse += delta
	bump_amount = move_toward(bump_amount, 0.0, delta * 7.0)
	_pulse_redraw_accumulator += delta
	if _pulse_redraw_accumulator >= VISUAL_REFRESH_INTERVAL:
		_pulse_redraw_accumulator = fmod(_pulse_redraw_accumulator, VISUAL_REFRESH_INTERVAL)
		_arc_layer.queue_redraw()
	if state != "urgent" and bump_amount <= 0.0:
		set_process(false)
		_pulse_redraw_accumulator = 0.0

func _draw() -> void:
	var c := size * 0.5
	var r := radius()
	if r <= 4.0:
		return
	NeuKit.disc(self, _plate, c, r)
	NeuKit.disc(self, _well, c, r * 0.86)
	# Etched minute marks on the rim of the plate.
	for i in 12:
		var a := TAU * float(i) / 12.0 - PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * r * 0.93
		var rad := 2.1 if i % 3 == 0 else 1.4
		draw_circle(p + Vector2(0.8, 0.9), rad, Color(1.0, 1.0, 1.0, 0.9))
		draw_circle(p, rad, Color(NeuKit.MUTED.r, NeuKit.MUTED.g, NeuKit.MUTED.b, 0.6))
