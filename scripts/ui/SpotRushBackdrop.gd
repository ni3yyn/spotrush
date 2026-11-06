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
	if challenge_focus:
		# Same SpotRush material and light direction, deliberately quieter so
		# challenge tokens retain clear edge contrast against the playfield.
		NeuKit.draw_backdrop(self, false, 0.38, 0.16, 0.008)
		return
	NeuKit.draw_backdrop(self, false)
