extends Node

# The game-wide confirmation sheet (v19) - neumorphic, code-built, floats
# above every scene on its own layer.
#
#   NeuDialog.ask("QUIT THIS RUN?", "Round 3 of 10 - ...", "QUIT",
#                 "KEEP PLAYING", func(): leave_run())          # danger: true
#   NeuDialog.inform("DUEL ENDED", "The host left mid-duel.", "GOT IT")
#
# Design notes:
#   * Same anatomy as the menu sheets: a raised card (radius 32 / dist 12 /
#     blur 26), a wordmark-weight title, a slate message, and results-screen
#     style keys - the coral key is the irreversible action, the plain key
#     is the safe one.
#   * The scrim eats every touch, so a run can't be answered underneath a
#     quit question; tapping outside the card = stay.
#   * Hardware back / Escape cancels (BackNav protocol).
#   * Sits on CanvasLayer 110 - above all scene UI, under the transition
#     curtain (120), so a confirmed quit wipes over the sheet cleanly.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

const SCRIM_COLOR: Color = Color(0.62, 0.68, 0.80, 0.40)

var _layer: CanvasLayer
var _scrim: ColorRect
var _card: PanelContainer
var _title: Label
var _message: Label
var _btn_confirm: Button
var _btn_cancel: Button
var _confirm_label: NeuText
var _cancel_label: NeuText

var _on_confirm: Callable = Callable()
var _open: bool = false
var _tween: Tween = null

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        _build()
        _layer.visible = false
        BackNav.register(self)
        SceneRouter.transition_started.connect(_force_close)
        get_viewport().size_changed.connect(_reflow)

func _build() -> void:
        _layer = CanvasLayer.new()
        _layer.layer = 110
        add_child(_layer)

        _scrim = ColorRect.new()
        _scrim.color = SCRIM_COLOR
        _scrim.mouse_filter = Control.MOUSE_FILTER_STOP
        _scrim.gui_input.connect(_on_scrim_input)
        _layer.add_child(_scrim)
        _scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

        var center := CenterContainer.new()
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _layer.add_child(center)
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

        _card = PanelContainer.new()
        var style := NeuKit.raised(32.0, 12.0, 26.0)
        _card.add_theme_stylebox_override("panel", style)
        center.add_child(_card)

        var margin := MarginContainer.new()
        for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
                margin.add_theme_constant_override(side, 26)
        _card.add_child(margin)

        var vbox := VBoxContainer.new()
        vbox.add_theme_constant_override("separation", 18)
        margin.add_child(vbox)

        _title = Label.new()
        _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var base: Font = _title.get_theme_default_font()
        if base == null:
                base = ThemeDB.fallback_font
        _title.add_theme_font_override("font", NeuKit.weighted_font(base, 800.0, 0.40))
        SpotRushTypography.apply_as(_title, SpotRushTypography.Role.SCREEN_TITLE)
        _title.add_theme_color_override("font_color", NeuKit.INK)
        NeuKit.etch(_title)
        vbox.add_child(_title)

        _message = Label.new()
        _message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _message.add_theme_font_override("font", NeuKit.bold_font(_message, 0.4))
        SpotRushTypography.apply_as(_message, SpotRushTypography.Role.BODY)
        _message.add_theme_color_override("font_color", NeuKit.SLATE)
        vbox.add_child(_message)

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 14)
        vbox.add_child(row)

        _btn_cancel = _make_key(false)
        row.add_child(_btn_cancel)
        _btn_confirm = _make_key(true)
        row.add_child(_btn_confirm)

# --- public API ------------------------------------------------------------------

## Ask a yes/no question. `danger = true` paints the confirm key coral
## (irreversible); false paints it cobalt (a plain choice).
func ask(title: String, message: String, confirm_text: String, cancel_text: String,
                on_confirm: Callable, danger: bool = true) -> void:
        if _open:
                push_warning("NeuDialog.ask ignored - a sheet is already open")
                return
        _on_confirm = on_confirm
        _title.text = title
        _message.text = message
        _btn_cancel.visible = true
        _set_key_caption(_btn_confirm, _confirm_label, confirm_text)
        _set_key_caption(_btn_cancel, _cancel_label, cancel_text)
        _paint_confirm(danger)
        _present()

## A one-key notice (nothing to decide - just say why something happened).
func inform(title: String, message: String, ok_text: String = "GOT IT") -> void:
        if _open:
                push_warning("NeuDialog.inform ignored - a sheet is already open")
                return
        _on_confirm = Callable()
        _title.text = title
        _message.text = message
        _btn_cancel.visible = false
        _set_key_caption(_btn_confirm, _confirm_label, ok_text)
        _paint_confirm(false)
        _present()

func is_open() -> bool:
        return _open

## BackNav protocol: an open sheet swallows hardware back as "stay".
func handle_back() -> bool:
        if not _open:
                return false
        _finish(false)
        return true

# --- wiring ----------------------------------------------------------------------

## A results-screen style key: engraved slate text on the plain surface
## (cancel), or lit white text on an accent surface (confirm, tinted later).
func _make_key(is_confirm: bool) -> Button:
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(0, 62)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.focus_mode = Control.FOCUS_NONE
        NeuKit.style_button(btn, "raised", 24.0)
        var label := NeuText.new()
        SpotRushTypography.apply_as(label, SpotRushTypography.Role.BUTTON)
        label.tracking = 1.5
        label.set_anchors_preset(Control.PRESET_FULL_RECT)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(label)
        if btn.has_meta("neu_style"):
                label.bind_style(btn.get_meta("neu_style"))
        if is_confirm:
                _confirm_label = label
                label.look = NeuText.Look.ON_ACCENT
                label.color = Color.WHITE
                btn.pressed.connect(func(): _finish(true))
        else:
                _cancel_label = label
                label.look = NeuText.Look.DEBOSS
                label.color = NeuKit.SLATE
                btn.pressed.connect(func(): _finish(false))
        return btn

## Key captions are NeuText children, so a re-ask just rewrites them.
func _set_key_caption(btn: Button, label: NeuText, caption: String) -> void:
        btn.text = ""
        label.text = caption

func _paint_confirm(danger: bool) -> void:
        var accent: Color = NeuKit.CORAL if danger else NeuKit.COBALT
        NeuKit.set_accent(_btn_confirm, accent)
        _confirm_label.accent_base = accent

func _on_scrim_input(event: InputEvent) -> void:
        # Tap anywhere outside the card = the safe choice.
        if (event is InputEventMouseButton and event.pressed) \
                        or (event is InputEventScreenTouch and event.pressed):
                _finish(false)

# --- presentation ------------------------------------------------------------------

## Keep the card's measure responsive: edge-to-edge with breathing room on
## phones, capped width on tablets. Re-runs whenever the window resizes.
func _reflow() -> void:
        # Explicit typing: `:=` inference on viewport member access broke under
        # the 4.x analyzer when a dependency cycle degrades the type pass.
        var vp := get_viewport()
        if vp == null:
                return
        var view: Vector2 = vp.size
        if view.x <= 0.0 or view.y <= 0.0:
                return
        _card.custom_minimum_size = Vector2(minf(view.x - 56.0, 520.0), 0.0)

func _present() -> void:
        _reflow()
        # Kill any dismissal still in flight: its end-of-tween callback would
        # otherwise hide the layer right after this ask shows it.
        _kill_tween()
        _open = true
        _layer.visible = true
        Feel.sfx("pop")
        if Feel.reduced():
                return
        _card.modulate.a = 0.0
        _card.scale = Vector2(0.94, 0.94)
        # Wait one frame so the card has its final laid-out size (the message
        # may have re-wrapped) before pivoting the rise on its centre.
        await get_tree().process_frame
        if not _open:
                return
        _card.pivot_offset = _card.size * 0.5
        _kill_tween()
        _tween = create_tween().set_parallel(true) \
                        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        _tween.tween_property(_card, "scale", Vector2.ONE, 0.20)
        _tween.tween_property(_card, "modulate:a", 1.0, 0.16)

## Close, then run the chosen action. The action runs AFTER the sheet is gone
## so navigations triggered by it start from a clean UI.
func _finish(confirmed: bool) -> void:
        if not _open:
                return
        _open = false
        var action := _on_confirm if confirmed else Callable()
        _on_confirm = Callable()
        if not Feel.reduced():
                _kill_tween()
                _tween = create_tween().set_parallel(true) \
                                .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
                _tween.tween_property(_card, "scale", Vector2(0.97, 0.97), 0.10)
                _tween.tween_property(_card, "modulate:a", 0.0, 0.10)
                _tween.chain().tween_callback(func():
                                _card.scale = Vector2.ONE
                                _card.modulate.a = 1.0
                                _layer.visible = false
                                if action.is_valid():
                                        action.call())
                return
        _layer.visible = false
        if action.is_valid():
                action.call()

## SceneRouter is already moving: hide instantly and drop the pending action
## (whatever it asked for has been overtaken by the navigation).
func _force_close() -> void:
        _open = false
        _on_confirm = Callable()
        _kill_tween()
        _layer.visible = false
        _card.scale = Vector2.ONE
        _card.modulate.a = 1.0

func _kill_tween() -> void:
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _tween = null

