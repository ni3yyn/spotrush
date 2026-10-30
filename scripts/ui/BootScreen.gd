extends Control

const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

# SpotRush boot / loading screen.
#
# A quiet neumorphic stage, pressed rather than printed: the SPOTRUSH wordmark
# is engraved into the surface (dark letterforms with the lit lip below), the
# progress module is a raised tray holding a deep inset well with a muted
# graphite bar, the corner discs are pressed wells instead of raised dials, and
# the signature spot-mark (NeuKit.draw_spot_mark) is a monochrome sculpture -
# well, engraved groove, deep dimple and three small raised beads. Colour is
# kept to a whisper; all depth comes from the one top-left light source.
#
# The handoff never fades: the centre mark is drawn with the EXACT geometry of
# NeuWipe's sealed-curtain mark (same pressed sculpture, same bead orbit), and
# the backdrop keeps its corner lighting at full strength so the pad matches
# the sealed curtain pixel-for-pixel. When loading finishes the supporting
# illustration melts away, SceneRouter.boot_to() seals the real curtain
# invisibly behind the identical mark, swaps scenes and OPENS the wipe onto the
# main menu. The menu's own entrance (items rising in) plays exactly as it does
# after any normal scene change.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")

const MENU_SCENE: String = "res://scenes/main/MainMenu.tscn"

@onready var wordmark: RichTextLabel = %Wordmark
@onready var tagline: Label = %Tagline
@onready var caption: Label = %Caption
@onready var progress: ProgressBar = %Progress

var decor_layer: DecorLayer
var mark_layer: MarkLayer

# Raised tray that seats the inset progress well (fades with the module).
var tray_strength: float = 0.0:
        set(value):
                tray_strength = value
                queue_redraw()

var _tray: StyleBox
var _glow_cache: Dictionary = {}
var _caption_time: float = 0.0
var _dots: int = -1
var _finished: bool = false

func _ready() -> void:
        _build_layers()
        _style_progress()
        wordmark.add_theme_font_override("bold_font", NeuKit.bold_font(wordmark, 0.34))
        # Letterpress: the engraved wordmark catches light along its lower edge.
        wordmark.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.9))
        wordmark.add_theme_constant_override("shadow_offset_x", 0)
        wordmark.add_theme_constant_override("shadow_offset_y", 2)
        NeuKit.etch(tagline)
        NeuKit.etch(caption)
        _apply_responsive_layout()
        get_viewport().size_changed.connect(_apply_responsive_layout)
        Feel.warm_up() # spread the sound-bank build across the loading time; no later hitch
        _play_entrance()

func _build_layers() -> void:
        _tray = NeuKit.raised(21.0, 8.0, 18.0)
        decor_layer = DecorLayer.new()
        decor_layer.name = "DecorLayer"
        decor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(decor_layer)
        move_child(decor_layer, 0) # behind the text nodes, above the root's own backdrop
        decor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mark_layer = MarkLayer.new()
        mark_layer.name = "MarkLayer"
        mark_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(mark_layer) # on top: the mark must sit over every fading element
        mark_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _style_progress() -> void:
        progress.show_percentage = false
        progress.min_value = 0.0
        progress.max_value = 1.0
        progress.value = 0.0
        var trough := NeuKit.inset(12.0, 4.0, 9.0)
        trough.content_margin_left = 0.0
        trough.content_margin_right = 0.0
        trough.content_margin_top = 0.0
        trough.content_margin_bottom = 0.0
        # Muted graphite fill instead of the loud cobalt: colour stays a whisper,
        # the raised bar inside the pressed well carries the depth.
        var fill := NeuKit.accent(Color("5E6E94"), 12.0, 2.5, 6.0)
        fill.content_margin_left = 0.0
        fill.content_margin_right = 0.0
        fill.content_margin_top = 0.0
        fill.content_margin_bottom = 0.0
        progress.add_theme_stylebox_override("background", trough)
        progress.add_theme_stylebox_override("fill", fill)

func _apply_responsive_layout() -> void:
        var view := get_viewport_rect().size
        if view.x <= 0.0:
                return
        SpotRushTypography.apply_as(wordmark, SpotRushTypography.Role.WORDMARK)
        SpotRushTypography.apply_as(tagline, SpotRushTypography.Role.BODY)
        SpotRushTypography.apply_as(caption, SpotRushTypography.Role.BODY)

func _draw() -> void:
        var w := size.x
        var h := size.y
        if w <= 0.0 or h <= 0.0:
                return
        # Base surface + the two corner glows, exactly like NeuKit.draw_backdrop.
        # The lighting stays at full strength all the way into the handoff so the
        # pad matches the sealed curtain pixel-for-pixel (no settle to flat).
        draw_rect(Rect2(Vector2.ZERO, size), NeuKit.SURFACE)
        var big := maxf(w, h) * 1.5
        draw_texture_rect(_glow_tex(Color(1.0, 1.0, 1.0, 0.65)), Rect2(Vector2(-big * 0.5, -big * 0.42), Vector2(big, big)), false)
        draw_texture_rect(_glow_tex(Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.24)), Rect2(Vector2(w - big * 0.45, h - big * 0.45), Vector2(big, big)), false)
        # Raised tray behind the progress well. Keep this geometry in step with
        # BootScreen.tscn: Progress is anchored 0.27..0.73 with offsets 288..304
        # from the vertical centre; the tray pads that rect by 13px.
        if tray_strength > 0.003:
                var tray_rect := Rect2(Vector2(w * 0.27 - 13.0, h * 0.5 + 275.0), Vector2(w * 0.46 + 26.0, 42.0))
                draw_style_box(_tray, tray_rect)

func _glow_tex(color: Color) -> GradientTexture2D:
        var key := color.to_html(true)
        if _glow_cache.has(key):
                return _glow_cache[key]
        var g := Gradient.new()
        g.set_color(0, color)
        g.set_color(1, Color(color.r, color.g, color.b, 0.0))
        var t := GradientTexture2D.new()
        t.gradient = g
        t.fill = GradientTexture2D.FILL_RADIAL
        t.fill_from = Vector2(0.5, 0.5)
        t.fill_to = Vector2(1.0, 0.5)
        t.width = 256
        t.height = 256
        _glow_cache[key] = t
        return t

func _process(delta: float) -> void:
        if _finished:
                return
        _caption_time += delta
        var dots := int(_caption_time * 2.4) % 4
        if dots != _dots:
                _dots = dots
                caption.text = "WARMING UP" + ".".repeat(dots)

func _play_entrance() -> void:
        if Feel.reduced():
                # Reduce Motion: no bloom, no stagger - a brief quiet hold, then the open.
                mark_layer.mark_alpha = 1.0
                mark_layer.orbit_enabled = false
                tray_strength = 1.0
                progress.value = 0.7
                await get_tree().create_timer(0.55).timeout
                if not is_inside_tree():
                        return
                _finish()
                return
        decor_layer.modulate.a = 0.0
        mark_layer.mark_alpha = 0.0
        mark_layer.mark_scale = 0.55
        tray_strength = 0.0
        for node: Control in [wordmark, tagline, caption, progress]:
                node.modulate.a = 0.0

        var tw := create_tween()
        tw.set_parallel(true)
        tw.tween_property(mark_layer, "mark_alpha", 1.0, 0.40).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        tw.tween_property(mark_layer, "mark_scale", 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_property(decor_layer, "modulate:a", 1.0, 0.50).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.06)
        tw.tween_property(wordmark, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.22)
        tw.tween_property(tagline, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.34)
        for node: Control in [caption, progress]:
                tw.tween_property(node, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.42)
        tw.tween_property(self, "tray_strength", 1.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.42)
        tw.tween_property(progress, "value", 0.86, 1.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.42)
        tw.chain().tween_callback(_finish)

func _finish() -> void:
        if _finished:
                return
        _finished = true
        caption.text = "READY!"
        # A whisper of success, not a colour pop: deep desaturated mint.
        caption.add_theme_color_override("font_color", NeuKit.MINT.darkened(0.35))
        if Feel.reduced():
                progress.value = 1.0
                _handoff()
                return
        Feel.sfx("spot")
        Feel.haptic("light")
        var tw := create_tween()
        tw.set_parallel(true)
        tw.tween_property(progress, "value", 1.0, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        tw.tween_property(decor_layer, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(0.20)
        tw.tween_property(self, "tray_strength", 0.0, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(0.30)
        for node: Control in [wordmark, tagline, caption, progress]:
                tw.tween_property(node, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(0.30)
        tw.chain().tween_callback(_handoff)

func _handoff() -> void:
        if not is_inside_tree():
                return
        # The supporting illustration is gone; only the lit pad and the centre
        # mark remain, exactly like the sealed curtain. Swap + open - the loading
        # screen "opens up" into the main menu instead of fading out.
        # The menu loop has been built in the background since process boot.
        # Queue it at the boot handoff so the first note lands with the menu,
        # rather than waiting for MainMenu's _ready() after its transition.
        Music.play_menu()
        SceneRouter.boot_to(MENU_SCENE, mark_layer.orbit_time)


class MarkLayer extends Control:
        # The SpotRush mark, drawn with the same pressed sculpture (and orbit
        # speed) as the NeuWipe curtain mark, so the boot -> curtain -> menu
        # handoff is seamless. Fades through modulate.a, driven by mark_alpha.
        const NeuKit = preload("res://scripts/ui/NeuKit.gd")

        var mark_alpha: float = 1.0:
                set(value):
                        mark_alpha = value
                        modulate.a = value
                        queue_redraw()
        var mark_scale: float = 1.0:
                set(value):
                        mark_scale = value
                        queue_redraw()
        var orbit_enabled: bool = true
        var orbit_time: float = 0.0
        var _redraw_accumulator: float = 0.0

        func _process(delta: float) -> void:
                if mark_alpha > 0.001 and orbit_enabled:
                        orbit_time += delta
                        _redraw_accumulator += delta
                        if _redraw_accumulator >= 1.0 / 30.0:
                                _redraw_accumulator = fmod(_redraw_accumulator, 1.0 / 30.0)
                                queue_redraw()

        func _draw() -> void:
                if modulate.a <= 0.001 or size.x <= 0.0:
                        return
                NeuKit.draw_spot_mark(self, size * 0.5, minf(size.x, size.y) * 0.085 * mark_scale, orbit_time, orbit_enabled)


class DecorLayer extends Control:
        # Pressed corner sculpture: the same inset language as the progress well.
        # Everything is concave - a large shallow well bottom-left with a deeper
        # dimple inside, a small dimple top-right, a quiet well bottom-right.
        const NeuKit = preload("res://scripts/ui/NeuKit.gd")

        var _built_size: Vector2 = Vector2.ZERO
        # Untyped on purpose: the sculpted pieces get depth/surface tweaks that
        # only exist on NeuStyle, and GDScript would reject those on a StyleBox
        # declaration. disc() consumes them as NeuStyle at runtime.
        var _well
        var _dimple
        var _sat
        var _foot

        func _draw() -> void:
                if modulate.a <= 0.003 or size.x <= 0.0:
                        return
                var w := size.x
                var h := size.y
                if _built_size != size:
                        _built_size = size
                        _well = NeuKit.inset(w * 0.30, 9.0, 20.0)
                        _well.depth = -0.95
                        _dimple = NeuKit.inset(w * 0.30 * 0.52, 6.0, 13.0)
                        _dimple.depth = -1.1
                        _dimple.surface = NeuKit.SURFACE.darkened(0.04)
                        _sat = NeuKit.inset(w * 0.085, 4.5, 10.0)
                        _sat.depth = -1.0
                        _foot = NeuKit.inset(w * 0.115, 5.0, 11.0)
                        _foot.depth = -0.9
                NeuKit.disc(self, _well, Vector2(-w * 0.04, h * 1.03), w * 0.30)
                NeuKit.disc(self, _dimple, Vector2(-w * 0.04, h * 1.03), w * 0.30 * 0.52)
                NeuKit.disc(self, _sat, Vector2(w * 1.03, h * 0.24), w * 0.085)
                NeuKit.disc(self, _foot, Vector2(w * 1.03, h * 0.99), w * 0.115)
