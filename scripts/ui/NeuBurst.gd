extends Control

# A short celebratory burst of small raised, tinted discs that fly out, arc under gravity and
# fade. Cheap: only redraws while particles are alive. Respects Particles + Reduce Motion.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const Settings = preload("res://scripts/core/Settings.gd")

var _parts: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## origin is in this control's local space. `spread` 1.0 = upward fan, 2.0 = full circle.
func burst(origin: Vector2, colors: Array, count: int = 18, power: float = 1.0, spread: float = 1.0) -> void:
	if Feel.reduced() or not Settings.particles():
		return
	for i in count:
		var angle := randf_range(-PI * (0.5 + 0.5 * spread), -PI * (0.5 - 0.5 * spread))
		var speed := randf_range(320.0, 720.0) * power
		_parts.append({
			"pos": origin,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"r": randf_range(5.0, 11.0),
			"col": colors[randi() % colors.size()],
			"t": 0.0,
			"ttl": randf_range(0.7, 1.15)
		})
	set_process(true)

func _process(delta: float) -> void:
	var alive: Array = []
	for p in _parts:
		p["vel"].y += 1700.0 * delta
		p["vel"] *= maxf(0.0, 1.0 - 2.1 * delta)
		p["pos"] += p["vel"] * delta
		p["t"] += delta
		if p["t"] < p["ttl"]:
			alive.append(p)
	_parts = alive
	queue_redraw()
	if _parts.is_empty():
		set_process(false)

func _draw() -> void:
	for p in _parts:
		var fade := 1.0 - smoothstep(0.55, 1.0, float(p["t"]) / float(p["ttl"]))
		var c: Color = p["col"]
		var r: float = p["r"]
		var pos: Vector2 = p["pos"]
		draw_circle(pos + Vector2(2.0, 3.0), r, Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.30 * fade))
		draw_circle(pos, r, Color(c.r, c.g, c.b, fade))
		draw_circle(pos + Vector2(-r * 0.3, -r * 0.34), r * 0.32, Color(1.0, 1.0, 1.0, 0.6 * fade))
