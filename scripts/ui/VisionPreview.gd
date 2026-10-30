extends Control

## v18 COLOUR VISION - live palette preview strip.
##
## Draws the four gameplay token colours (RED / BLUE / YELLOW / MINT) exactly
## the way the play field sculpts them (same NeuStyle recipe as
## ChallengeCanvas._token_style), so a player can pick their mode by eye.
## Reads the ACTIVE mode on every redraw: queue_redraw() after a pick.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const ColorVision = preload("res://scripts/ui/ColorVision.gd")

const TOKEN_ORDER := ["RED", "BLUE", "YELLOW", "MINT"]

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        custom_minimum_size = Vector2(0.0, 72.0)

func _draw() -> void:
        var n := TOKEN_ORDER.size()
        var radius := minf(size.x / float(n), size.y) * 0.30
        var slot := size.x / float(n)
        for i in range(n):
                var col := ColorVision.resolve(TOKEN_ORDER[i])
                var center := Vector2(slot * (float(i) + 0.5), size.y * 0.5)
                # Mirror the field tokens: accent enamel + the token light/dark rim.
                var style: NeuStyle = NeuKit.accent(col, 10.0, 3.0, 7.0)
                style.light = Color(1.0, 1.0, 1.0, 0.50)
                style.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.34)
                style.rim = 0.42
                style.gradient = 0.68
                style.glow = Color(col.r, col.g, col.b, 0.24)
                style.depth = 1.0
                style.distance = clampf(radius * 0.15, 3.0, 6.5)
                style.blur = clampf(radius * 0.36, 7.0, 14.0)
                NeuKit.sphere_token(self, style, center, radius, 0.38)
