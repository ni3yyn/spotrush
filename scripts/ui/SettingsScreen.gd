extends Control

# Full-screen settings page. Kept separate from MainMenu so it has a real
# navigation lifecycle, an independent back handler and room to grow.

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const NeuSwitchScript = preload("res://scripts/ui/NeuSwitch.gd")
const SpotRushGlyph = preload("res://scripts/ui/SpotRushGlyph.gd")
const VisionPreviewScript = preload("res://scripts/ui/VisionPreview.gd")
const BackdropScript = preload("res://scripts/ui/NeuMenuBackdrop.gd")
const Settings = preload("res://scripts/core/Settings.gd")
const ColorVision = preload("res://scripts/ui/ColorVision.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const LogExport = preload("res://scripts/core/LogExport.gd")

var _round_buttons: Dictionary = {}
var _vision_buttons: Dictionary = {}
var _content: VBoxContainer
var _safe_area: MarginContainer
var _vision_hint: Label
var _vision_preview: Control
var _slider_thumb_texture: Texture2D = null
var _toggle_layouts: Array[Dictionary] = []
var _reminder_status: Label = null
var _diagnostics_status: Label = null
var _copy_logs_btn: Button = null
var _export_logs_btn: Button = null

func _ready() -> void:
        BackNav.register(self)
        Music.play_menu()
        _build_page()
        if not DailyReminder.permission_state_changed.is_connected(_on_reminder_permission_state_changed):
                DailyReminder.permission_state_changed.connect(_on_reminder_permission_state_changed)
        _refresh_reminder_status()
        # Android may report the final cutout/safe-area rectangle one frame
        # after the scene enters the tree. Read it after layout, then once more
        # after the platform window settles so the header never sits under a notch.
        await get_tree().process_frame
        _apply_safe_area_insets()
        await get_tree().process_frame
        _apply_safe_area_insets()
        _sync_round_buttons()
        _sync_vision_buttons()
        get_viewport().size_changed.connect(_on_viewport_resized)
        _on_viewport_resized()
        _play_entrance()

func _exit_tree() -> void:
        BackNav.unregister(self)

func handle_back() -> bool:
        if SceneRouter.is_transitioning:
                return true
        _go_back()
        return true

func _go_back() -> void:
        if SceneRouter.is_transitioning:
                return
        SceneRouter.goto_main_menu()

func _build_page() -> void:
        var backdrop := Control.new()
        backdrop.name = "Backdrop"
        backdrop.set_script(BackdropScript)
        backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
        backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(backdrop)
        move_child(backdrop, 0)

        var safe := MarginContainer.new()
        safe.name = "SafeArea"
        safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # OS cutout offsets are applied explicitly in _apply_safe_area_insets().
        # The additional top margin is intentional breathing room BELOW the
        # status bar / camera island, not a substitute for the actual inset.
        safe.add_theme_constant_override("margin_left", 24)
        safe.add_theme_constant_override("margin_right", 24)
        safe.add_theme_constant_override("margin_top", 30)
        safe.add_theme_constant_override("margin_bottom", 30)
        add_child(safe)
        _safe_area = safe

        var page := VBoxContainer.new()
        page.name = "Page"
        page.add_theme_constant_override("separation", 16)
        safe.add_child(page)

        page.add_child(_build_header())
        var scroll := ScrollContainer.new()
        scroll.name = "SettingsScroll"
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        # Leave a small tap deadzone, but let vertical finger drags begin on
        # the option controls instead of requiring an empty background strip.
        scroll.scroll_deadzone = 12
        page.add_child(scroll)

        _content = VBoxContainer.new()
        _content.mouse_filter = Control.MOUSE_FILTER_PASS
        _content.name = "SettingsContent"
        _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _content.add_theme_constant_override("separation", 30)
        scroll.add_child(_content)

        _build_audio_section()
        _build_gameplay_section()
        _build_accessibility_section()
        _build_match_section()
        _build_reminder_section()
        _build_diagnostics_section()

        # Buttons, labels and nested card containers default to MOUSE_FILTER_STOP.
        # That prevents the ScrollContainer from seeing a swipe that starts on an
        # option. PASS preserves each control's own input while bubbling the
        # gesture through the content hierarchy to SettingsScroll.
        _set_scroll_event_passthrough(_content)

        var note := Label.new()
        note.text = "CHANGES ARE SAVED AUTOMATICALLY"
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_override("font", NeuKit.bold_font(note, 0.30))
        SpotRushTypography.apply_as(note, SpotRushTypography.Role.CAPTION)
        note.add_theme_color_override("font_color", NeuKit.SLATE)
        note.custom_minimum_size.y = 48
        _content.add_child(note)

func _set_scroll_event_passthrough(node: Node) -> void:
        if node is Control:
                var control := node as Control
                control.mouse_filter = Control.MOUSE_FILTER_PASS
        for child in node.get_children():
                _set_scroll_event_passthrough(child)

func _build_header() -> Control:
        # Keep this bar geometrically identical to LocalLobby: same back key,
        # centred title, equal-width right spacer and 12px control gap.
        var header := HBoxContainer.new()
        header.name = "HeaderBar"
        header.custom_minimum_size.y = 56
        header.add_theme_constant_override("separation", 12)

        var back := Button.new()
        back.name = "BtnBack"
        back.text = "BACK"
        back.custom_minimum_size = Vector2(100, 56)
        back.focus_mode = Control.FOCUS_NONE
        back.add_theme_font_override("font", NeuKit.bold_font(back))
        SpotRushTypography.apply_as(back, SpotRushTypography.Role.BUTTON)
        for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
                back.add_theme_color_override(key, NeuKit.INK)
        NeuKit.style_button(back, "raised", 22.0)
        back.pressed.connect(_go_back)
        header.add_child(back)

        var title := Label.new()
        title.name = "LobbyTitle"
        title.text = "SETTINGS"
        title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.add_theme_font_override("font", NeuKit.bold_font(title, 0.68))
        SpotRushTypography.apply_as(title, SpotRushTypography.Role.SCREEN_TITLE)
        title.add_theme_color_override("font_color", NeuKit.COBALT)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        NeuKit.etch(title)
        header.add_child(title)

        var balance := Control.new()
        balance.name = "HeaderPad"
        balance.custom_minimum_size = Vector2(100, 0)
        balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
        header.add_child(balance)
        return header

func _section(title_text: String, hint_text: String = "") -> VBoxContainer:
        var section := VBoxContainer.new()
        section.add_theme_constant_override("separation", 13)
        var title := Label.new()
        title.text = title_text.to_upper()
        title.add_theme_font_override("font", NeuKit.bold_font(title, 0.45))
        SpotRushTypography.apply_as(title, SpotRushTypography.Role.SECTION_TITLE)
        title.add_theme_color_override("font_color", NeuKit.INK)
        section.add_child(title)
        if not hint_text.is_empty():
                var hint := Label.new()
                hint.text = hint_text
                hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                SpotRushTypography.apply_as(hint, SpotRushTypography.Role.BODY)
                hint.add_theme_color_override("font_color", NeuKit.SLATE)
                section.add_child(hint)
        _content.add_child(section)
        return section

func _make_toggle_row(glyph_name: String, title_text: String, detail_text: String,
                initial: bool, callback: Callable) -> PanelContainer:
        var card := PanelContainer.new()
        card.add_theme_stylebox_override("panel", NeuKit.raised(24.0, 5.0, 12.0))
        var margin := MarginContainer.new()
        _set_margins(margin, 20, 16, 20, 16)
        card.add_child(margin)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 18)
        row.custom_minimum_size.y = 98
        margin.add_child(row)

        var glyph := SpotRushGlyph.new()
        glyph.glyph = glyph_name
        glyph.glyph_color = NeuKit.SLATE
        glyph.custom_minimum_size = Vector2(52, 52)
        row.add_child(glyph)

        var labels := VBoxContainer.new()
        labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        labels.add_theme_constant_override("separation", 4)
        var title := Label.new()
        title.text = title_text
        title.add_theme_font_override("font", NeuKit.bold_font(title, 0.48))
        SpotRushTypography.apply_as(title, SpotRushTypography.Role.CARD_TITLE)
        title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        title.add_theme_color_override("font_color", NeuKit.INK)
        labels.add_child(title)
        var detail := Label.new()
        detail.text = detail_text
        detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        SpotRushTypography.apply_as(detail, SpotRushTypography.Role.BODY)
        detail.add_theme_color_override("font_color", NeuKit.SLATE)
        labels.add_child(detail)
        row.add_child(labels)

        var toggle := CheckButton.new()
        toggle.set_script(NeuSwitchScript)
        toggle.custom_minimum_size = Vector2(108, 76)
        toggle.set_pressed_no_signal(initial)
        toggle.toggled.connect(callback)
        row.add_child(toggle)
        _toggle_layouts.append({"margin": margin, "row": row, "glyph": glyph, "toggle": toggle})
        return card

func _build_audio_section() -> void:
        var section := _section("Sound", "Set the balance between the theme and in-game effects.")
        section.add_child(_make_volume_row("Theme music", Settings.music_volume(),
                func(v: float) -> void: Settings.set_music_volume(v)))
        section.add_child(_make_volume_row("Effects volume", Settings.sfx_volume(),
                func(v: float) -> void: Settings.set_sfx_volume(v)))
        section.add_child(_make_toggle_row("sound", "Sound effects", "Button presses, feedback and game cues.",
                Settings.sfx(), func(on: bool) -> void: Settings.set_bool("sfx", on)))

func _make_volume_row(title_text: String, value: float, setter: Callable) -> PanelContainer:
        var card := PanelContainer.new()
        card.custom_minimum_size.y = 224
        card.add_theme_stylebox_override("panel", NeuKit.raised(26.0, 6.0, 14.0))

        var margin := MarginContainer.new()
        _set_margins(margin, 24, 18, 24, 18)
        card.add_child(margin)

        var column := VBoxContainer.new()
        column.add_theme_constant_override("separation", 16)
        margin.add_child(column)

        var top := HBoxContainer.new()
        top.custom_minimum_size.y = 72
        top.add_theme_constant_override("separation", 14)

        var label := Label.new()
        label.text = title_text
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.add_theme_font_override("font", NeuKit.bold_font(label, 0.48))
        SpotRushTypography.apply_as(label, SpotRushTypography.Role.CARD_TITLE)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.add_theme_color_override("font_color", NeuKit.INK)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        top.add_child(label)

        var percent_well := PanelContainer.new()
        percent_well.name = "VolumeValueWell"
        percent_well.custom_minimum_size = Vector2(136, 74)
        var percent_style := NeuKit.inset(18.0, 4.0, 10.0)
        percent_style.content_margin_left = 8.0
        percent_style.content_margin_right = 8.0
        percent_style.content_margin_top = 3.0
        percent_style.content_margin_bottom = 3.0
        percent_well.add_theme_stylebox_override("panel", percent_style)

        var percent := Label.new()
        percent.name = "VolumePercent"
        percent.text = "%d%%" % int(round(value * 100.0))
        percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        percent.add_theme_font_override("font", NeuKit.bold_font(percent, 0.62))
        SpotRushTypography.apply_as(percent, SpotRushTypography.Role.DISPLAY)
        percent.add_theme_color_override("font_color", NeuKit.COBALT)
        percent_well.add_child(percent)
        top.add_child(percent_well)
        column.add_child(top)

        var slider := HSlider.new()
        slider.name = "VolumeSlider"
        slider.min_value = 0.0
        slider.max_value = 100.0
        slider.step = 1.0
        slider.value = roundf(value * 100.0)
        slider.custom_minimum_size = Vector2(0, 84)
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slider.focus_mode = Control.FOCUS_ALL
        slider.add_theme_constant_override("center_grabber", 1)
        slider.add_theme_constant_override("grabber_max_size", 68)
        slider.add_theme_icon_override("grabber", _slider_thumb())
        slider.add_theme_icon_override("grabber_highlight", _slider_thumb())
        slider.add_theme_icon_override("grabber_disabled", _slider_thumb())

        var track := StyleBoxFlat.new()
        track.bg_color = Color("B8C5D9")
        track.set_corner_radius_all(10)
        track.content_margin_top = 12.0
        track.content_margin_bottom = 12.0
        track.shadow_color = Color(0.30, 0.38, 0.54, 0.18)
        track.shadow_size = 3
        track.shadow_offset = Vector2(1, 2)
        slider.add_theme_stylebox_override("slider", track)

        var fill := StyleBoxFlat.new()
        fill.bg_color = NeuKit.COBALT
        fill.set_corner_radius_all(10)
        fill.content_margin_top = 12.0
        fill.content_margin_bottom = 12.0
        slider.add_theme_stylebox_override("grabber_area", fill)
        slider.add_theme_stylebox_override("grabber_area_highlight", fill)
        slider.value_changed.connect(func(v: float) -> void:
                percent.text = "%d%%" % int(round(v))
                setter.call(v / 100.0))
        slider.drag_ended.connect(func(changed: bool) -> void:
                if changed and Settings.sfx() and Settings.sfx_volume() > 0.0:
                        Feel.sfx("pip"))
        column.add_child(slider)
        return card

func _slider_thumb() -> Texture2D:
        # Large, high-contrast touch thumb with a soft surface and cobalt rim.
        # It is cached so both volume controls share one consistent thumb.
        if _slider_thumb_texture != null:
                return _slider_thumb_texture
        var image := Image.create(72, 72, false, Image.FORMAT_RGBA8)
        image.fill(Color(0.0, 0.0, 0.0, 0.0))
        var centre := Vector2(36.0, 35.0)
        for y in range(72):
                for x in range(72):
                        var distance := Vector2(float(x), float(y)).distance_to(centre)
                        if distance <= 28.0:
                                var col := Color("2B52E2")
                                if distance <= 22.0:
                                        var light := clampf(1.0 - distance / 56.0, 0.0, 1.0)
                                        col = Color("DCE4F2").lerp(Color("FFFFFF"), light)
                                image.set_pixel(x, y, col)
                        elif distance <= 32.0:
                                var alpha := clampf((32.0 - distance) / 4.0, 0.0, 1.0) * 0.24
                                image.set_pixel(x, y, Color(0.20, 0.28, 0.45, alpha))
        _slider_thumb_texture = ImageTexture.create_from_image(image)
        return _slider_thumb_texture

func _build_gameplay_section() -> void:
        var section := _section("Game feel", "Small details that shape movement and feedback.")
        section.add_child(_make_toggle_row("sparkle", "Particles", "Keep the soft bursts and shape trails.",
                Settings.particles(), func(on: bool) -> void: Settings.set_bool("particles", on)))
        section.add_child(_make_toggle_row("vibrate", "Haptics", "Subtle vibration on taps and game events.",
                Settings.haptics(), func(on: bool) -> void: Settings.set_bool("haptics", on)))
        section.add_child(_make_toggle_row("target", "Reduce motion", "Shorter transitions and fewer animated effects.",
                Settings.reduce_motion(), func(on: bool) -> void: Settings.set_bool("reduce_motion", on)))

func _build_accessibility_section() -> void:
        var section := _section("Colour vision", "Adjust the token palette to make each shape easier to distinguish.")
        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 12)
        grid.add_theme_constant_override("v_separation", 12)
        section.add_child(grid)
        var options := [
                ["Normal", ColorVision.MODE_OFF],
                ["Deuteranopia", ColorVision.MODE_DEUTAN],
                ["Protanopia", ColorVision.MODE_PROTAN],
                ["Tritanopia", ColorVision.MODE_TRITAN],
        ]
        for option in options:
                var button := Button.new()
                button.text = str(option[0])
                button.custom_minimum_size = Vector2(0, 90)
                button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                button.add_theme_font_override("font", NeuKit.bold_font(button, 0.36))
                SpotRushTypography.apply_as(button, SpotRushTypography.Role.BUTTON)
                button.add_theme_color_override("font_color", NeuKit.SLATE)
                NeuKit.style_button(button, "raised", 18.0)
                var mode := str(option[1])
                button.pressed.connect(_select_vision.bind(mode))
                _vision_buttons[mode] = button
                grid.add_child(button)
        _vision_hint = Label.new()
        _vision_hint.name = "VisionHint"
        _vision_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        SpotRushTypography.apply_as(_vision_hint, SpotRushTypography.Role.BODY)
        _vision_hint.add_theme_color_override("font_color", NeuKit.SLATE)
        _vision_hint.text = ColorVision.mode_hint(ColorVision.mode())
        section.add_child(_vision_hint)
        _vision_preview = VisionPreviewScript.new() as Control
        _vision_preview.name = "VisionPreview"
        _vision_preview.custom_minimum_size = Vector2(0, 104)
        section.add_child(_vision_preview)

func _select_vision(mode: String) -> void:
        ColorVision.set_mode(mode)
        _sync_vision_buttons()
        if is_instance_valid(_vision_hint):
                _vision_hint.text = ColorVision.mode_hint(mode)
        if is_instance_valid(_vision_preview):
                _vision_preview.queue_redraw()

func _sync_vision_buttons() -> void:
        var current := ColorVision.mode()
        for mode in _vision_buttons:
                var button: Button = _vision_buttons[mode]
                var selected := str(mode) == current
                NeuKit.set_selected(button, selected)
                var tint := NeuKit.COBALT if selected else NeuKit.SLATE
                for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
                        button.add_theme_color_override(key, tint)

func _build_match_section() -> void:
        var section := _section("Match length", "Choose the default number of rounds for solo play.")
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        section.add_child(row)
        for count in [5, 10, 15]:
                var button := Button.new()
                button.text = "%d rounds" % count
                button.custom_minimum_size = Vector2(0, 90)
                button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                button.add_theme_font_override("font", NeuKit.bold_font(button, 0.4))
                SpotRushTypography.apply_as(button, SpotRushTypography.Role.BUTTON)
                NeuKit.style_button(button, "raised", 18.0)
                button.pressed.connect(_set_rounds.bind(count))
                _round_buttons[count] = button
                row.add_child(button)

func _set_rounds(count: int) -> void:
        Settings.set_match_rounds(count)
        _sync_round_buttons()

func _sync_round_buttons() -> void:
        var current := Settings.match_rounds()
        for count in _round_buttons:
                var button: Button = _round_buttons[count]
                var selected := int(count) == current
                NeuKit.set_selected(button, selected)
                var tint := NeuKit.COBALT if selected else NeuKit.SLATE
                for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
                        button.add_theme_color_override(key, tint)

func _build_reminder_section() -> void:
        var section := _section("Daily reminder", "One optional nudge if your daily streak is at risk.")
        section.add_child(_make_toggle_row("flame", "Daily streak reminder", "Off by default. You can turn it off at any time.",
                Settings.reminder_enabled(), _on_reminder_toggled))
        _reminder_status = Label.new()
        _reminder_status.name = "ReminderPermissionStatus"
        _reminder_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        SpotRushTypography.apply_as(_reminder_status, SpotRushTypography.Role.BODY)
        _reminder_status.add_theme_color_override("font_color", NeuKit.SLATE)
        section.add_child(_reminder_status)
        _refresh_reminder_status()
        if OS.is_debug_build():
                var debug_btn := Button.new()
                debug_btn.text = "SEND TEST NOTIFICATION (DEBUG, 5s)"
                debug_btn.custom_minimum_size = Vector2(0, 90)
                debug_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                debug_btn.add_theme_font_override("font", NeuKit.bold_font(debug_btn, 0.36))
                SpotRushTypography.apply_as(debug_btn, SpotRushTypography.Role.BUTTON)
                debug_btn.add_theme_color_override("font_color", NeuKit.SLATE)
                NeuKit.style_button(debug_btn, "raised", 18.0)
                debug_btn.pressed.connect(func() -> void: DailyReminder.debug_fire_test_notification())
                section.add_child(debug_btn)

## Diagnostics: lets the player (or a tester) get CrashLogger's logs off the
## device themselves without needing adb - copy a ready-to-paste report to
## the clipboard, or export every kept session as one zip they can attach to
## an email or a bug report app. See LogExport.gd for what each pulls in.
func _build_diagnostics_section() -> void:
        var section := _section("Diagnostics", "Grab the on-device logs to attach to a bug report.")

        _diagnostics_status = Label.new()
        _diagnostics_status.name = "DiagnosticsStatus"
        _diagnostics_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        SpotRushTypography.apply_as(_diagnostics_status, SpotRushTypography.Role.BODY)
        _diagnostics_status.add_theme_color_override("font_color", NeuKit.SLATE)
        section.add_child(_diagnostics_status)
        _refresh_diagnostics_status()

        _copy_logs_btn = _diagnostics_button("COPY LOGS TO CLIPBOARD")
        _copy_logs_btn.pressed.connect(_on_copy_logs_pressed)
        section.add_child(_copy_logs_btn)

        _export_logs_btn = _diagnostics_button("EXPORT LOGS (.ZIP)")
        _export_logs_btn.pressed.connect(_on_export_logs_pressed)
        section.add_child(_export_logs_btn)

func _diagnostics_button(label: String) -> Button:
        var btn := Button.new()
        btn.text = label
        btn.custom_minimum_size = Vector2(0, 90)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.add_theme_font_override("font", NeuKit.bold_font(btn, 0.36))
        SpotRushTypography.apply_as(btn, SpotRushTypography.Role.BUTTON)
        btn.add_theme_color_override("font_color", NeuKit.SLATE)
        NeuKit.style_button(btn, "raised", 18.0)
        return btn

func _refresh_diagnostics_status() -> void:
        if not is_instance_valid(_diagnostics_status):
                return
        if LogExport.has_logs():
                _diagnostics_status.text = "Logs folder: %s" % CrashLogger.log_dir
        else:
                _diagnostics_status.text = "No logs yet this install."

## Disabled while the action runs so a double-tap can't fire it twice, then
## restored - whatever happens, success or failure, so a slow device or an
## error never leaves the button stuck.
func _on_copy_logs_pressed() -> void:
        if not is_instance_valid(_copy_logs_btn):
                return
        _copy_logs_btn.disabled = true
        var ok := LogExport.copy_report_to_clipboard()
        _copy_logs_btn.disabled = false
        if ok:
                NeuDialog.inform("LOGS COPIED", "The latest sessions' breadcrumbs and logcat tail are on your clipboard. Paste them into your bug report.", "GOT IT")
        else:
                NeuDialog.inform("NOTHING TO COPY", "No logs exist yet on this install.", "GOT IT")

func _on_export_logs_pressed() -> void:
        if not is_instance_valid(_export_logs_btn):
                return
        _export_logs_btn.disabled = true
        var zip_path := LogExport.export_zip()
        _export_logs_btn.disabled = false
        if zip_path.is_empty():
                NeuDialog.inform("EXPORT FAILED", "No logs exist yet on this install, or the zip could not be written.", "GOT IT")
                return
        DisplayServer.clipboard_set(zip_path)
        NeuDialog.inform("LOGS EXPORTED", "Saved to:\n%s\n\nThe path is also on your clipboard." % zip_path, "GOT IT")

func _on_reminder_toggled(on: bool) -> void:
        Settings.set_reminder_enabled(on)
        if on:
                # Ask first. A pause caused by the Android permission sheet must
                # not try to schedule anything until the user grants permission.
                DailyReminder.request_permission()
        else:
                DailyReminder.cancel_reminder()
        _refresh_reminder_status()

func _on_reminder_permission_state_changed(_granted: bool, _denied: bool) -> void:
        _refresh_reminder_status()

func _refresh_reminder_status() -> void:
        if is_instance_valid(_reminder_status):
                _reminder_status.text = DailyReminder.permission_description()

func _inset_style() -> StyleBox:
        var style := NeuKit.inset(22.0, 5.0, 12.0)
        style.content_margin_left = 0.0
        style.content_margin_right = 0.0
        style.content_margin_top = 0.0
        style.content_margin_bottom = 0.0
        return style

func _set_margins(node: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
        node.add_theme_constant_override("margin_left", left)
        node.add_theme_constant_override("margin_top", top)
        node.add_theme_constant_override("margin_right", right)
        node.add_theme_constant_override("margin_bottom", bottom)

func _apply_safe_area_insets() -> void:
        if not is_instance_valid(_safe_area):
                return
        var inset := NeuSafe.canvas_insets()
        # NeuSafe includes the OS cutout/status inset plus a mobile fallback
        # when an edge-to-edge build reports an empty safe rectangle.
        # Set absolute offsets rather than calling NeuSafe.fit() repeatedly;
        # this keeps rotation / resize updates from accumulating old insets.
        _safe_area.offset_left = inset.x
        _safe_area.offset_top = inset.y
        _safe_area.offset_right = -inset.z
        _safe_area.offset_bottom = -inset.w

func _on_viewport_resized() -> void:
        _apply_safe_area_insets()
        if _content == null:
                return
        var width := get_viewport_rect().size.x
        var compact := width < 420.0
        var safe := get_node_or_null("SafeArea") as MarginContainer
        if safe != null:
                safe.add_theme_constant_override("margin_left", 18 if compact else 24)
                safe.add_theme_constant_override("margin_right", 18 if compact else 24)
        var header_back := get_node_or_null("SafeArea/Page/HeaderBar/BtnBack") as Button
        var header_title := get_node_or_null("SafeArea/Page/HeaderBar/LobbyTitle") as Label
        var header_pad := get_node_or_null("SafeArea/Page/HeaderBar/HeaderPad") as Control
        if header_back != null:
                header_back.custom_minimum_size = Vector2(88 if compact else 100, 56)
        if header_pad != null:
                header_pad.custom_minimum_size.x = 88 if compact else 100
        if header_title != null:
                SpotRushTypography.apply_as(header_title, SpotRushTypography.Role.SCREEN_TITLE)
        for button in _round_buttons.values():
                SpotRushTypography.apply_as(button as Button, SpotRushTypography.Role.BUTTON)
        # On narrow phones the icon and switch must not squeeze the explanatory
        # copy into a thin column. Keep type readable; reclaim space from chrome.
        for layout in _toggle_layouts:
                var margin := layout["margin"] as MarginContainer
                var row := layout["row"] as HBoxContainer
                var glyph := layout["glyph"] as Control
                var toggle := layout["toggle"] as Control
                glyph.visible = not compact
                row.add_theme_constant_override("separation", 12 if compact else 18)
                toggle.custom_minimum_size = Vector2(92, 72) if compact else Vector2(108, 76)
                _set_margins(margin, 14 if compact else 20, 14 if compact else 18,
                        14 if compact else 20, 14 if compact else 18)

func _play_entrance() -> void:
        if Feel.reduced():
                return
        var page := get_node_or_null("SafeArea/Page") as Control
        if page == null:
                return
        page.modulate.a = 0.0
        page.position.y += 12.0
        var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        tw.tween_property(page, "modulate:a", 1.0, 0.24)
        tw.tween_property(page, "position:y", page.position.y - 12.0, 0.34)