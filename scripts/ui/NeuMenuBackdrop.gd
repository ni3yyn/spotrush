extends Control

# Static neumorphic surface for the main menu: flat soft-UI material lit from the
# top-left plus sculpted corner decor. Drawn once and only again on resize.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	NeuKit.draw_backdrop(self, true)
