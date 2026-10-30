extends RefCounted

# One source of truth for every text size in SpotRush.
#
# Godot's font sizes are logical UI pixels (not Android sp or iOS pt), so these
# tokens are tuned for the project's 720x1280 portrait canvas. Keep body copy at
# 19px, supporting copy at 17px, and never push essential mobile copy below 16px.
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
        HUD_VALUE,
        COUNTDOWN,
        HERO_SCORE,
        WORDMARK,
        INPUT_VALUE,
}

const SIZES := {
        Role.MICRO: 16,
        Role.CAPTION: 17,
        Role.BODY: 19,
        Role.BODY_STRONG: 20,
        Role.BUTTON_COMPACT: 18,
        Role.BUTTON: 20,
        Role.BUTTON_LARGE: 22,
        Role.CARD_TITLE: 22,
        Role.STAT_LABEL: 20,
        Role.SECTION_TITLE: 24,
        Role.SCREEN_TITLE: 32,
        Role.DISPLAY: 44,
        Role.HUD_VALUE: 56,
        Role.COUNTDOWN: 64,
        Role.HERO_SCORE: 84,
        Role.WORDMARK: 76,
        Role.INPUT_VALUE: 24,
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
        if current_px <= 16:
                return size(Role.MICRO)
        if current_px <= 17:
                return size(Role.CAPTION)
        if current_px <= 20:
                return size(Role.BODY_STRONG) if current_px == 20 else size(Role.BODY)
        if current_px <= 22:
                return size(Role.CARD_TITLE)
        if current_px <= 24:
                return size(Role.SECTION_TITLE)
        if current_px <= 28:
                return size(Role.SECTION_TITLE)
        if current_px <= 36:
                return size(Role.SCREEN_TITLE)
        if current_px <= 48:
                return size(Role.DISPLAY)
        if current_px <= 56:
                return size(Role.HUD_VALUE)
        if current_px <= 70:
                return size(Role.COUNTDOWN)
        # Wordmarks sit between countdown numerals and hero scores. Keep this
        # range explicit so a second normalization pass is idempotent.
        if current_px <= 78:
                return size(Role.WORDMARK)
        if current_px <= 84:
                return size(Role.HERO_SCORE)
        return size(Role.WORDMARK)

static func _button_role_for(current_px: int) -> int:
        if current_px <= 18:
                return size(Role.BUTTON_COMPACT)
        if current_px <= 20:
                return size(Role.BUTTON)
        if current_px <= 28:
                return size(Role.BUTTON_LARGE)
        return _label_role_for(current_px, true)

## Practical mobile hit target. It is a minimum, not a forced size, so larger
## custom buttons and sliders keep their existing layout.
static func _ensure_touch_target(control: Control) -> void:
        if control is Button or control is LineEdit or control is TextEdit:
                var minimum := control.custom_minimum_size
                minimum.x = maxf(minimum.x, 48.0)
                minimum.y = maxf(minimum.y, 48.0)
                control.custom_minimum_size = minimum

## NeuText is a custom Control with its own exported font_size property.
## Mapping is idempotent, so animation code can safely change it mid-round.
static func resolve_neu_text(current_px: int) -> int:
        return _label_role_for(current_px, true)
