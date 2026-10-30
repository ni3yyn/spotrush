extends Control

# Quiet neumorphic surface used by non-menu screens: flat material with the same
# top-left light falloff as the menu, no decor competing with the play area.
# Non-interactive and drawn once (and again only on resize).

const NeuKit = preload("res://scripts/ui/NeuKit.gd")

## Challenge screens use a quieter light wash so pale tokens keep their edge contrast.
@export var challenge_focus: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if not challenge_focus:
		NeuKit.draw_backdrop(self, false)
		return
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	# A static, low-contrast light falloff: no extra ornaments or motion behind play.
	draw_rect(Rect2(Vector2.ZERO, size), NeuKit.SURFACE.darkened(0.008))
	var big := maxf(w, h) * 1.5
	draw_texture_rect(NeuKit._glow(Color(1.0, 1.0, 1.0, 0.38)), Rect2(Vector2(-big * 0.5, -big * 0.42), Vector2(big, big)), false)
	draw_texture_rect(NeuKit._glow(Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.16)), Rect2(Vector2(w - big * 0.45, h - big * 0.45), Vector2(big, big)), false)
