extends Control

# Neumorphic text. Godot's Label only has one hard shadow, which cannot fake a soft
# raised or engraved letterform, so this control lays the text out itself and draws
# stacked, offset copies (light from the top-left, like everything else in the UI).
#
#   DEBOSS    engraved into the surface: dark letters, light lip below-right
#   EMBOSS    raised out of the surface: surface-coloured letters, soft dual shadow
#   LIT       glowing LED digits: accent letters with a soft halo (scores, readouts)
#   ON_ACCENT letters on a coloured surface: light face, tinted shadow + highlight
#
# Drop-in friendly: exposes `text`, `color`, `font_size`; sizes itself in containers.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

enum Look { DEBOSS, EMBOSS, LIT, ON_ACCENT }

@export_multiline var text: String = "":
        set(value):
                if text == value:
                        return
                text = value
                _dirty()
@export var font_size: int = 20:
        set(value):
                var resolved := SpotRushTypography.resolve_neu_text(value)
                if font_size == resolved:
                        return
                font_size = resolved
                _dirty()
@export var color: Color = Color("1E2432"):
        set(value):
                color = value
                queue_redraw()
@export_enum("Deboss", "Emboss", "Lit", "OnAccent") var look: int = 0:
        set(value):
                look = value
                queue_redraw()
@export var bold: bool = true:
        set(value):
                bold = value
                _dirty()
## Extra pixels between letters (nice for small caps captions).
@export var tracking: float = 0.0:
        set(value):
                tracking = value
                _dirty()
@export_enum("Left", "Center", "Right") var align: int = 1:
        set(value):
                align = value
                queue_redraw()
@export var autowrap: bool = false:
        set(value):
                autowrap = value
                _dirty()
## Highlights ALL-CAPS words (3+ letters) in `emphasis_color`, e.g. "Tap ALL SQUARE shapes!".
@export var auto_emphasis: bool = false:
        set(value):
                auto_emphasis = value
                _dirty()
@export var emphasis_color: Color = Color("2B52E2")
## The accent surface the text sits on (ON_ACCENT only): tints its shadow/highlight.
@export var accent_base: Color = Color("2B52E2"):
        set(value):
                accent_base = value
                queue_redraw()
@export var line_spacing: float = 4.0:
        set(value):
                line_spacing = value
                _dirty()

var _font: Font
var _lines: Array = []
var _line_h: float = 0.0
var _content: Vector2 = Vector2.ZERO
var _laid_width: float = -1.0
var _nudge: Vector2 = Vector2.ZERO
var _press_k: float = 0.0

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        # Normalize values loaded from older scenes as well as runtime updates.
        font_size = SpotRushTypography.resolve_neu_text(font_size)
        _layout()

func _notification(what: int) -> void:
        if what == NOTIFICATION_RESIZED:
                if autowrap and absf(size.x - _laid_width) > 0.5:
                        _layout()
                queue_redraw()
        elif what == NOTIFICATION_THEME_CHANGED:
                _dirty()

func _get_minimum_size() -> Vector2:
        return Vector2(0.0 if autowrap else ceilf(_content.x) + 8.0, ceilf(_content.y) + 8.0)

func get_text_size() -> Vector2:
        return _content

## Shared typography hooks used by SpotRushTypography for both scene-authored
## and runtime-created NeuText controls.
func set_typography_size(px: int) -> void:
        font_size = px

func apply_typography_scale() -> void:
        font_size = SpotRushTypography.resolve_neu_text(font_size)

## Makes the text follow a NeuStyle press: it dips and its shadows tighten with the key.
func bind_style(style: StyleBox) -> void:
        if style != null and style.has_signal("changed"):
                style.changed.connect(_on_style_changed.bind(style))

func _on_style_changed(style: StyleBox) -> void:
        var d: float = style.get("depth")
        _press_k = clampf((1.0 - d) / 1.9, 0.0, 1.0)
        _nudge = Vector2(0.0, _press_k * 2.0)
        queue_redraw()

# --- layout ---------------------------------------------------------------------------

func _dirty() -> void:
        if is_inside_tree():
                _layout()
        queue_redraw()

func _make_font() -> Font:
        var base: Font = get_theme_default_font()
        if base == null:
                base = ThemeDB.fallback_font
        if not bold and tracking == 0.0:
                return base
        var fv := FontVariation.new()
        fv.base_font = base
        fv.fallbacks = base.fallbacks # keep emoji / symbol fallbacks working
        if bold:
                # Real weight first (Baloo 2 Bold, wght 700) with a light embolden
                # kick on top - heavy without clogging the counters at any size.
                fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
                fv.variation_embolden = 0.22
        fv.spacing_glyph = int(round(tracking))
        return fv

static func _is_emphasis(word: String) -> bool:
        var letters := 0
        for i in word.length():
                var ch := word.substr(i, 1)
                if ch.to_upper() != ch.to_lower():
                        letters += 1
                        if ch != ch.to_upper():
                                return false
        return letters >= 3

func _layout() -> void:
        _font = _make_font()
        _lines.clear()
        var space_w: float = _font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking
        var limit: float = size.x - 8.0 if (autowrap and size.x > 24.0) else 1.0e9
        _laid_width = size.x
        var asc: float = _font.get_ascent(font_size)
        _line_h = asc + _font.get_descent(font_size)
        var max_w := 0.0
        for paragraph in text.split("\n"):
                var words: Array = []
                var cur_w := 0.0
                for raw in paragraph.split(" ", false):
                        var w: float = _font.get_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
                        if not words.is_empty() and cur_w + space_w + w > limit:
                                _lines.append({"words": words, "w": cur_w})
                                max_w = maxf(max_w, cur_w)
                                words = []
                                cur_w = 0.0
                        var x := cur_w + (space_w if not words.is_empty() else 0.0)
                        words.append({"t": raw, "x": x, "e": auto_emphasis and _is_emphasis(raw)})
                        cur_w = x + w
                _lines.append({"words": words, "w": cur_w})
                max_w = maxf(max_w, cur_w)
        var lines := maxi(1, _lines.size())
        _content = Vector2(max_w, float(lines) * _line_h + float(lines - 1) * line_spacing)
        update_minimum_size()
        queue_redraw()

# --- drawing --------------------------------------------------------------------------

func _draw() -> void:
        if _lines.is_empty() or _font == null:
                return
        var asc: float = _font.get_ascent(font_size)
        var y0 := (size.y - _content.y) * 0.5 + _nudge.y
        for li in _lines.size():
                var line: Dictionary = _lines[li]
                var lw: float = line["w"]
                var x0 := 0.0
                match align:
                        1: x0 = (size.x - lw) * 0.5
                        2: x0 = size.x - lw - 4.0
                        _: x0 = 4.0
                x0 += _nudge.x
                var top := y0 + float(li) * (_line_h + line_spacing)
                for word in line["words"]:
                        _paint_word(Vector2(x0 + float(word["x"]), top + asc), str(word["t"]), bool(word["e"]))

func _word(pos: Vector2, word: String, offset: Vector2, col: Color) -> void:
        draw_string(_font, pos + offset, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

func _paint_word(pos: Vector2, word: String, emphasized: bool) -> void:
        var face: Color = emphasis_color if emphasized else color
        var s: float = 1.0 - 0.65 * _press_k # shadows tighten as the key sinks
        match look:
                1: # EMBOSS: soft dark shadow down-right, bright edge up-left
                        _word(pos, word, Vector2(4.2, 5.0) * s, Color(0.45, 0.52, 0.68, 0.16))
                        _word(pos, word, Vector2(2.4, 3.0) * s, Color(0.45, 0.52, 0.68, 0.34))
                        _word(pos, word, Vector2(-2.0, -2.2) * s, Color(1.0, 1.0, 1.0, 0.95))
                        _word(pos, word, Vector2.ZERO, face)
                2: # LIT: halo, light lip, glowing face
                        for g in [[9.0, 0.07], [6.0, 0.10], [3.0, 0.16]]:
                                draw_string_outline(_font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(g[0]), Color(face.r, face.g, face.b, float(g[1])))
                        _word(pos, word, Vector2(1.0, 1.6), Color(1.0, 1.0, 1.0, 0.9))
                        _word(pos, word, Vector2.ZERO, face)
                3: # ON_ACCENT: tinted shadow + highlight on a coloured surface
                        var deep := accent_base.darkened(0.6)
                        var high := accent_base.lightened(0.55)
                        _word(pos, word, Vector2(3.0, 4.2) * s, Color(deep.r, deep.g, deep.b, 0.28))
                        _word(pos, word, Vector2(1.6, 2.4) * s, Color(deep.r, deep.g, deep.b, 0.55))
                        _word(pos, word, Vector2(-1.0, -1.4) * s, Color(high.r, high.g, high.b, 0.55))
                        _word(pos, word, Vector2.ZERO, face)
                _: # DEBOSS: engraved, light lip below-right, faint inner edge top-left
                        _word(pos, word, Vector2(1.2, 1.7) * s, Color(1.0, 1.0, 1.0, 0.95))
                        _word(pos, word, Vector2(-0.7, -0.9) * s, Color(0.35, 0.42, 0.58, 0.20))
                        _word(pos, word, Vector2.ZERO, face)
