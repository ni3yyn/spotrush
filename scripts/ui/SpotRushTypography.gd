extends RefCounted

# One source of truth for every text size in SpotRush.
# Godot uses logical UI pixels. These values are tuned for the 720x1280
# portrait canvas and intentionally favour readable, confident type over
# fitting more copy into less space.
# The node-added hook in SceneRouter normalizes static and runtime-created
# Controls through this scale. NeuText uses resolve_neu_text() in its setter.

# Semantic roles for new UI. Change SIZES once to restyle the whole game.
enum Role {
        MICRO,
        CAPTION,
        BODY,
        BODY_STRONG,
        BUTTON_COMPACT,
        BUTTON,
        BUTTON_LARGE,
        CARD_TITLE,
        STAT_LABEL,
        SECTION_TITLE,
        SCREEN_TITLE,
        DISPLAY,
        DISPLAY_COMPACT,
        HUD_VALUE,
        COUNTDOWN,
        HERO_SCORE,
        WORDMARK,
        INPUT_VALUE,
}

const SIZES := {
        # The old scale was designed around desktop-sized previews and rendered
        # too quietly on real phones. The new baseline favours readable labels,
        # clear hierarchy, and generous touch targets.
        Role.MICRO: 20,
        Role.CAPTION: 24,
        Role.BODY: 28,
        Role.BODY_STRONG: 30,
        Role.BUTTON_COMPACT: 26,
        Role.BUTTON: 30,
        Role.BUTTON_LARGE: 34,
        Role.CARD_TITLE: 36,
        Role.STAT_LABEL: 24,
        Role.SECTION_TITLE: 38,
        Role.SCREEN_TITLE: 46,
        Role.DISPLAY: 56,
        Role.DISPLAY_COMPACT: 52,
        Role.HUD_VALUE: 72,
        Role.COUNTDOWN: 82,
        Role.HERO_SCORE: 104,
        Role.WORDMARK: 92,
        Role.INPUT_VALUE: 32,
}

static func size(role: int) -> int:
        return int(SIZES.get(role, SIZES[Role.BODY]))

## Apply a named role to a newly-created control. Prefer this over raw numbers.
static func apply_as(control: Control, role: int) -> void:
        if control == null or not is_instance_valid(control):
                return
        var px := size(role)
        if control is RichTextLabel:
                control.add_theme_font_size_override("normal_font_size", px)
                control.add_theme_font_size_override("bold_font_size", maxi(px, size(Role.BODY_STRONG)))
        elif control.has_method("set_typography_size"):
                control.call("set_typography_size", px)
        elif control is Label or control is Button or control is LineEdit or control is TextEdit:
                control.add_theme_font_size_override("font_size", px)
        _ensure_touch_target(control)
        control.set_meta("spotrush_typography_role", role)

## Normalize existing scene values and controls created by runtime code.
## Existing scene numbers act only as semantic hints; final sizes live in SIZES.
static func apply_control(control: Control) -> void:
        if control == null or not is_instance_valid(control):
                return
        # A semantic role assigned by a component is authoritative. The
        # SceneRouter's late node-added pass must not downgrade it by guessing
        # from an old scene's raw font-size override.
        if control.has_meta("spotrush_typography_role"):
                apply_as(control, int(control.get_meta("spotrush_typography_role")))
                return
        if control.has_method("apply_typography_scale"):
                control.call("apply_typography_scale")
                return

        if control is RichTextLabel:
                var normal_px := control.get_theme_font_size("normal_font_size")
                var bold_px := control.get_theme_font_size("bold_font_size")
                control.add_theme_font_size_override("normal_font_size", _label_role_for(normal_px, false))
                control.add_theme_font_size_override("bold_font_size", _label_role_for(bold_px, true))
        elif control is Button:
                var current_button_px := control.get_theme_font_size("font_size")
                control.add_theme_font_size_override("font_size", _button_role_for(current_button_px))
                _ensure_touch_target(control)
        elif control is LineEdit or control is TextEdit:
                var current_input_px := control.get_theme_font_size("font_size")
                control.add_theme_font_size_override("font_size", size(Role.INPUT_VALUE) if current_input_px > 20 else size(Role.BODY))
                _ensure_touch_target(control)
        elif control is Label:
                var current_label_px := control.get_theme_font_size("font_size")
                control.add_theme_font_size_override("font_size", _label_role_for(current_label_px, false))

static func _label_role_for(current_px: int, _bold: bool) -> int:
        # Preserve values already emitted by SIZES. This makes repeated
        # SceneRouter/NeuText normalization passes strictly idempotent.
        if current_px in [20, 24, 26, 28, 30, 32, 34, 36, 38, 42, 46, 52, 56, 64, 72, 82, 92, 104]:
                return current_px
        if current_px <= 17:
                return size(Role.MICRO)
        if current_px <= 21:
                return size(Role.CAPTION)
        if current_px <= 25:
                return size(Role.BODY)
        if current_px <= 29:
                return size(Role.BODY_STRONG)
        if current_px <= 33:
                return size(Role.BUTTON_LARGE)
        if current_px <= 37:
                return size(Role.CARD_TITLE)
        if current_px <= 41:
                return size(Role.SECTION_TITLE)
        if current_px <= 48:
                return size(Role.SCREEN_TITLE)
        if current_px <= 60:
                return size(Role.DISPLAY)
        if current_px <= 70:
                return size(Role.HUD_VALUE)
        if current_px <= 82:
                return size(Role.COUNTDOWN)
        if current_px <= 94:
                return size(Role.WORDMARK)
        return size(Role.HERO_SCORE)

static func _button_role_for(current_px: int) -> int:
        if current_px <= 21:
                return size(Role.BUTTON_COMPACT)
        if current_px <= 27:
                return size(Role.BUTTON)
        if current_px <= 32:
                return size(Role.BUTTON_LARGE)
        return _label_role_for(current_px, true)

## Practical mobile hit target. It is a minimum, not a forced size, so larger
## custom buttons and sliders keep their existing layout.
static func _ensure_touch_target(control: Control) -> void:
        if control is Button or control is LineEdit or control is TextEdit:
                var minimum := control.custom_minimum_size
                minimum.x = maxf(minimum.x, 56.0)
                minimum.y = maxf(minimum.y, 56.0)
                control.custom_minimum_size = minimum

## NeuText is a custom Control with its own exported font_size property.
## Mapping is idempotent, so animation code can safely change it mid-round.
static func resolve_neu_text(current_px: int) -> int:
        return _label_role_for(current_px, true)
