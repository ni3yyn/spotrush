extends CheckButton

# Neumorphic toggle: sunken track, raised thumb that slides and lights up cobalt when on.
# Drop-in replacement for a CheckButton node: same `toggled` / `button_pressed` API.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _t: float = 0.0
var _squeeze: float = 0.0
var _track: NeuStyle
var _thumb: NeuStyle

func _ready() -> void:
        custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 88.0), maxf(custom_minimum_size.y, 52.0))
        focus_mode = Control.FOCUS_NONE
        # Hide Godot's built-in check icons and state frames; we draw everything ourselves.
        var blank := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
        for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
                add_theme_icon_override(icon_name, blank)
        var empty := StyleBoxEmpty.new()
        for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
                add_theme_stylebox_override(state, empty)
        _track = NeuKit.inset(18.0, 3.5, 8.0)
        _track.depth = -0.9
        _thumb = NeuKit.raised(14.0, 3.0, 7.0)
        _thumb.colored = true
        _t = 1.0 if button_pressed else 0.0
        toggled.connect(_on_toggled)
        button_down.connect(func() -> void: _animate_squeeze(1.0, 0.07))
        button_up.connect(func() -> void: _animate_squeeze(0.0, 0.25))
        queue_redraw()

## Call after set_pressed_no_signal() so the thumb jumps to the right side without animating.
func sync_visual() -> void:
        _t = 1.0 if button_pressed else 0.0
        queue_redraw()

func _on_toggled(on: bool) -> void:
        Feel.sfx("toggle_on" if on else "toggle_off")
        Feel.haptic("light")
        var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_method(_set_t, _t, 1.0 if on else 0.0, 0.26)

func _animate_squeeze(target: float, dur: float) -> void:
        var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tw.tween_method(_set_squeeze, _squeeze, target, dur)

func _set_t(v: float) -> void:
        _t = v
        queue_redraw()

func _set_squeeze(v: float) -> void:
        _squeeze = v
        queue_redraw()

func _draw() -> void:
        # Fill the row's full allocated height (capped only so the pill never
        # turns into an oversized blob on a very tall/compact row) instead of
        # pinning every switch to a flat 44px regardless of the space it's given.
        var h := clampf(size.y, 44.0, 64.0)
        var track_rect := Rect2(Vector2(0.0, (size.y - h) * 0.5), Vector2(size.x, h))
        _track.corner_radius = h * 0.5
        draw_style_box(_track, track_rect)
        var pad := 6.0
        var d := h - pad * 2.0
        var travel := size.x - pad * 2.0 - d
        var x := pad + travel * clampf(_t, 0.0, 1.0)
        var thumb_rect := Rect2(Vector2(x, track_rect.position.y + pad), Vector2(d, d))
        _thumb.surface = NeuKit.SURFACE.lerp(NeuKit.COBALT, clampf(_t, 0.0, 1.0))
        _thumb.glow = Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.40 * clampf(_t, 0.0, 1.0))
        _thumb.colored = _t > 0.5
        _thumb.depth = lerpf(1.0, 0.35, _squeeze)
        _thumb.corner_radius = d * 0.5
        draw_style_box(_thumb, thumb_rect)
        # Tiny specular on the thumb face.
        draw_circle(thumb_rect.get_center() + Vector2(-d * 0.18, -d * 0.2), d * 0.1, Color(1.0, 1.0, 1.0, 0.5 * (1.0 - _squeeze)))
