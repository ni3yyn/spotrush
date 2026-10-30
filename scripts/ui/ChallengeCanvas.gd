class_name ChallengeCanvas
extends Control

signal item_tapped(index: int, item_data: Dictionary)
signal item_untapped(index: int, item_data: Dictionary)
signal side_tapped(side_name: String)

var current_challenge: ChallengeDefinition = null
var tapped_indices: Array[int] = []
var is_interactive: bool = true
var selected_side: String = ""

# Animation state
var entrance_tween: Tween = null

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const ColorVision = preload("res://scripts/ui/ColorVision.gd")

# Legacy names kept for any external reference; the field itself is now drawn with NeuStyle.
const COLOR_MINT: Color = NeuKit.MINT
const COLOR_WHITE: Color = NeuKit.SURFACE
const COLOR_INK: Color = NeuKit.INK

var _tray: NeuStyle
var _tray_left: NeuStyle
var _tray_right: NeuStyle
var _chip_left: NeuStyle
var _chip_right: NeuStyle
var _pad: NeuStyle
var _token_styles: Dictionary = {}
var _tint: StyleBoxFlat
var _ring: StyleBoxFlat

# Per-item press animation (index -> 0..1) and the answer-result flash.
var _sink: Dictionary = {}
# Per-item pressed amount (index -> 0..1, 1 = fully seated). Follows membership of
# tapped_indices so a token can be pressed AND released again (unselect).
var _press_anim: Dictionary = {}
var _result: int = 0
var _result_t: float = 0.0
var _result_tween: Tween = null
var _ring_layer: Control

# Round-start entrance: tokens rise out of their sockets one after another.
var _rise_active: bool = false
var _rise_t: float = 0.0
var _rise_total: float = 0.0
var _rise_rank: Array = [] # item index -> position in the top-left to bottom-right wave
var _token_shadow_steps: int = 5
var _token_detail_segments: int = 48
var _last_perf_draw_log_usec: int = 0

func _ready() -> void:
        custom_minimum_size = Vector2(280, 360)
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        size_flags_vertical = Control.SIZE_EXPAND_FILL
        mouse_filter = Control.MOUSE_FILTER_STOP
        # Quiet, matte play surfaces: enough depth to separate the field from its frame,
        # without the bright double halo that can compete with small tokens.
        _tray = NeuKit.inset(26.0, 7.0, 16.0, NeuKit.SURFACE.darkened(0.018))
        _tray.depth = -0.72
        _tray.gradient = 0.32
        _tray.light = Color(1.0, 1.0, 1.0, 0.42)
        _tray.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.40)
        _tray_left = NeuKit.inset(24.0, 7.0, 16.0, NeuKit.SURFACE.darkened(0.018))
        _tray_right = NeuKit.inset(24.0, 7.0, 16.0, NeuKit.SURFACE.darkened(0.018))
        for tray in [_tray_left, _tray_right]:
                tray.gradient = 0.32
                tray.light = Color(1.0, 1.0, 1.0, 0.42)
                tray.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.40)
        _chip_left = NeuKit.raised(15.0, 3.0, 8.0, NeuKit.SURFACE.lerp(NeuKit.COBALT, 0.045))
        _chip_right = NeuKit.raised(15.0, 3.0, 8.0, NeuKit.SURFACE.lerp(NeuKit.CORAL, 0.04))
        for chip in [_chip_left, _chip_right]:
                chip.depth = 0.58
                chip.depth_rest = 0.58
                chip.gradient = 0.38
                chip.rim = 0.38
                chip.light = Color(1.0, 1.0, 1.0, 0.46)
                chip.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.32)
        _pad = NeuKit.inset(40.0, 2.5, 7.0, NeuKit.SURFACE.darkened(0.012))
        _pad.gradient = 0.30
        _pad.light = Color(1.0, 1.0, 1.0, 0.46)
        _pad.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.34)
        _tint = StyleBoxFlat.new()
        _ring = StyleBoxFlat.new()
        _ring.draw_center = false
        _ring_layer = Control.new()
        _ring_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        _ring_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ring_layer.draw.connect(_on_ring_layer_draw)
        add_child(_ring_layer)
        set_process(false)

func _process(delta: float) -> void:
        var busy := false
        for key in _sink.keys():
                _sink[key] = float(_sink[key]) + delta / 0.30
                if float(_sink[key]) >= 1.0:
                        _sink.erase(key)
        if not _sink.is_empty():
                busy = true
        # Advance every token's pressed amount toward its target (selected = pressed in,
        # deselected = sprung back out). Both legs are a quick tween - never an instant
        # cut - with the press-in snapping noticeably faster than the release spring.
        for key in _press_anim.keys():
                var target := 1.0 if (int(key) in tapped_indices) else 0.0
                var current := float(_press_anim[key])
                var step := delta / (0.09 if target > current else 0.22)
                if current < target:
                        current = minf(current + step, target)
                elif current > target:
                        current = maxf(current - step, target)
                _press_anim[key] = current
                if current != target:
                        busy = true
                elif target == 0.0:
                        _press_anim.erase(key)
        if _rise_active:
                _rise_t += delta
                if _rise_t >= _rise_total:
                        _rise_active = false
                else:
                        busy = true
        queue_redraw()
        if not busy:
                set_process(false)

## Rank items by distance along the light direction (x + y) so they rise as a diagonal wave.
static func _wave_ranks(items: Array) -> Array:
        var order: Array = range(items.size())
        order.sort_custom(func(a, b): return (float(items[a]["x"]) + float(items[a]["y"])) < (float(items[b]["x"]) + float(items[b]["y"])))
        var ranks: Array = []
        ranks.resize(items.size())
        for r in order.size():
                ranks[order[r]] = r
        return ranks

static func _back(t: float) -> float:
        var c1 := 1.70158
        var c3 := c1 + 1.0
        return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

## Flash the tray with a mint (correct) or coral (wrong) ring after an answer.
func show_result(correct: bool) -> void:
        _result = 1 if correct else -1
        if _result_tween != null and _result_tween.is_valid():
                _result_tween.kill()
        _result_tween = create_tween()
        _result_tween.tween_method(_set_result_t, 1.0, 0.0, 1.1)

func _set_result_t(v: float) -> void:
        _result_t = v
        _ring_layer.queue_redraw()

func _on_ring_layer_draw() -> void:
        if _result == 0 or _result_t <= 0.01 or current_challenge == null:
                return
        if current_challenge.visual_data.get("split_view", false):
                var mid_x: float = size.x * 0.5
                _draw_result_ring(Rect2(4.0, 4.0, mid_x - 9.0, size.y - 8.0), 24)
                _draw_result_ring(Rect2(mid_x + 5.0, 4.0, size.x - mid_x - 9.0, size.y - 8.0), 24)
        else:
                _draw_result_ring(Rect2(4.0, 4.0, size.x - 8.0, size.y - 8.0), 26)

func set_challenge(challenge: ChallengeDefinition, animate: bool = true) -> void:
        current_challenge = challenge
        tapped_indices.clear()
        selected_side = ""
        is_interactive = true
        _sink.clear()
        _press_anim.clear()
        _result = 0
        _result_t = 0.0
        if _ring_layer != null:
                _ring_layer.queue_redraw()
        
        queue_redraw()
        
        # Small single-field boards reveal their tokens in a staggered diagonal wave, not just
        # tap rounds. This keeps the opening round's particles feeling alive even when its
        # input mode is choice-based. Split comparisons animate as a whole, while crowded
        # counting boards use a cheaper whole-field entrance.
        var items_count: int = current_challenge.visual_data.get("items", []).size()
        if current_challenge.visual_data.get("split_view", false):
                items_count = current_challenge.visual_data.get("left_items", []).size() \
                        + current_challenge.visual_data.get("right_items", []).size()
        # A dense playfield has many more repeated shadow meshes. Keep the same
        # visual language, but use fewer falloff layers when there are many tokens.
        _token_shadow_steps = 3 if items_count >= 34 else (4 if items_count >= 18 else 5)
        _token_detail_segments = 24 if items_count >= 34 else (32 if items_count >= 18 else 48)
        _rise_active = animate and not Feel.reduced() \
                and not current_challenge.visual_data.get("split_view", false) \
                and items_count > 0 and items_count <= 18
        _rise_t = 0.0
        _rise_total = 0.55 + 0.04 * float(items_count)
        _rise_rank = _wave_ranks(current_challenge.visual_data.get("items", []))
        if entrance_tween != null and entrance_tween.is_valid():
                entrance_tween.kill()
        if not animate:
                scale = Vector2.ONE
                modulate.a = 1.0
                set_process(false)
                return
        if _rise_active:
                scale = Vector2.ONE
                modulate.a = 1.0
                set_process(true)
                return
        if Feel.reduced():
                scale = Vector2.ONE
                modulate.a = 1.0
                return

        # Tactile elastic scale entrance on the control node
        pivot_offset = size * 0.5 if size.x > 0 else Vector2(200, 200)
        scale = Vector2(0.94, 0.94)
        modulate.a = 0.7
                
        entrance_tween = create_tween()
        entrance_tween.set_parallel(true)
        entrance_tween.set_trans(Tween.TRANS_BACK)
        entrance_tween.set_ease(Tween.EASE_OUT)
        entrance_tween.tween_property(self, "scale", Vector2.ONE, 0.28)
        entrance_tween.tween_property(self, "modulate:a", 1.0, 0.18)

func set_item_tapped(index: int) -> void:
        if not index in tapped_indices:
                tapped_indices.append(index)
                _press_anim[index] = 1.0
                queue_redraw()

func _gui_input(event: InputEvent) -> void:
        if not is_interactive or current_challenge == null:
                return
                
        var is_press = false
        var click_pos = Vector2.ZERO

        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
                is_press = true
                click_pos = event.position
        elif event is InputEventScreenTouch and event.pressed:
                is_press = true
                click_pos = event.position

        if not is_press:
                return

        # Project Settings has both touch<->mouse emulation flags on (desktop testing
        # needs emulate_touch_from_mouse; real phones ship with emulate_mouse_from_touch
        # on by default), so every physical tap arrives here TWICE: once as the real
        # event and once as its synthetic echo of the other type, both landing on the
        # same position in the same input flush. Godot tags the synthetic one with
        # DEVICE_ID_EMULATION - drop it here, or a single tap double-fires the hit test
        # below (select then immediately unselect), which reads as "nothing happened"
        # even though the tap sound/haptic still played for both passes.
        if event.device == InputEvent.DEVICE_ID_EMULATION:
                return

        accept_event()
        
        # 1. Split view side-by-side touch dispatch
        if current_challenge.visual_data.get("split_view", false):
                var mid_x = size.x * 0.5
                Feel.sfx("pop", 0.85)
                Feel.haptic("light")
                if click_pos.x < mid_x:
                        selected_side = "LEFT"
                        queue_redraw()
                        side_tapped.emit("LEFT")
                else:
                        selected_side = "RIGHT"
                        queue_redraw()
                        side_tapped.emit("RIGHT")
                return
                
        # 2. Tap targets selection mode - tap a token to select it, tap it again to
        # release it (unselect) before confirming.
        if current_challenge.input_mode == "tap_targets":
                var items: Array = current_challenge.visual_data.get("items", [])
                var pad = 24.0
                var play_w = size.x - (pad * 2.0)
                var play_h = size.y - (pad * 2.0)
                
                # Check from last to first (topmost drawn item)
                for i in range(items.size() - 1, -1, -1):
                        var it = items[i]
                        var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
                        var base_sz = float(it.get("size", 28.0))
                        var touch_radius = maxf(base_sz * 0.9, 28.0)
                        
                        if click_pos.distance_to(center) <= touch_radius:
                                if i in tapped_indices:
                                        # UNSELECT: release the token back to its raised seat.
                                        tapped_indices.erase(i)
                                        if not Feel.reduced():
                                                _press_anim[i] = float(_press_anim.get(i, 1.0))
                                                set_process(true)
                                        Feel.sfx("pop", 0.68)
                                        Feel.haptic("light")
                                        item_untapped.emit(i, it)
                                else:
                                        tapped_indices.append(i)
                                        if not Feel.reduced():
                                                _press_anim[i] = float(_press_anim.get(i, 0.0))
                                                _sink[i] = 0.0
                                                set_process(true)
                                        # Each collected target rings a little higher, so progress is audible.
                                        Feel.sfx("pop", 1.0 + 0.08 * float(mini(tapped_indices.size() - 1, 8)))
                                        Feel.haptic("light")
                                        item_tapped.emit(i, it)
                                queue_redraw()
                                return
                return
                
        # 3. Withhold response tap dispatch
        if current_challenge.input_mode == "withhold_response":
                side_tapped.emit("TAP")
                return

func _draw() -> void:
        if current_challenge == null or size.x <= 0 or size.y <= 0 or _tray == null:
                return
        var perf_started_usec: int = Time.get_ticks_usec() if OS.is_debug_build() else 0
        var pad = 24.0
        var play_w = size.x - (pad * 2.0)
        var play_h = size.y - (pad * 2.0)
        if current_challenge.visual_data.get("split_view", false):
                _draw_split_view(pad, play_w, play_h)
        else:
                _draw_single_field(pad, play_w, play_h)
        if OS.is_debug_build():
                var elapsed_usec := Time.get_ticks_usec() - perf_started_usec
                var now_usec := Time.get_ticks_usec()
                if elapsed_usec >= 6000 and now_usec - _last_perf_draw_log_usec >= 2000000:
                        _last_perf_draw_log_usec = now_usec
                        print("[PERF] ChallengeCanvas draw %.2f ms | token shadow steps: %d" % [float(elapsed_usec) / 1000.0, _token_shadow_steps])

func _draw_result_ring(rect: Rect2, radius: int) -> void:
        if _result == 0 or _result_t <= 0.01:
                return
        var base: Color = NeuKit.MINT if _result > 0 else NeuKit.CORAL
        _ring.set_corner_radius_all(radius)
        for i in 3:
                _ring.set_border_width_all(2 + i * 2)
                _ring.border_color = Color(base.r, base.g, base.b, _result_t * (0.55 - float(i) * 0.17))
                _ring_layer.draw_style_box(_ring, rect.grow(float(i) * 2.0))

func _draw_split_view(pad: float, play_w: float, play_h: float) -> void:
        var mid_x: float = size.x * 0.5
        var left_zone := Rect2(4.0, 4.0, mid_x - 9.0, size.y - 8.0)
        var right_zone := Rect2(mid_x + 5.0, 4.0, size.x - mid_x - 9.0, size.y - 8.0)
        # Two sunken trays; the chosen one is pressed deeper and tinted in its colour.
        _tray_left.depth = -1.0 if selected_side == "LEFT" else -0.72
        _tray_right.depth = -1.0 if selected_side == "RIGHT" else -0.72
        draw_style_box(_tray_left, left_zone)
        draw_style_box(_tray_right, right_zone)
        if selected_side != "":
                var zone: Rect2 = left_zone if selected_side == "LEFT" else right_zone
                var accent: Color = NeuKit.COBALT if selected_side == "LEFT" else NeuKit.CORAL
                _tint.bg_color = Color(accent.r, accent.g, accent.b, 0.07)
                _tint.set_corner_radius_all(24)
                draw_style_box(_tint, zone)
                _ring.set_corner_radius_all(24)
                _ring.set_border_width_all(2)
                _ring.border_color = Color(accent.r, accent.g, accent.b, 0.55)
                draw_style_box(_ring, zone)

        var badge_w: float = minf(116.0, mid_x * 0.7)
        var badge_h: float = 40.0
        var left_badge := Rect2(mid_x * 0.5 - badge_w * 0.5, 16.0, badge_w, badge_h)
        var right_badge := Rect2(mid_x + mid_x * 0.5 - badge_w * 0.5, 16.0, badge_w, badge_h)
        draw_style_box(_chip_left, left_badge)
        draw_style_box(_chip_right, right_badge)
        var font: Font = NeuKit.bold_font(self)
        var badge_text_size := SpotRushTypography.size(SpotRushTypography.Role.BODY)
        draw_string(font, Vector2(left_badge.position.x, left_badge.position.y + 27.0), "LEFT", HORIZONTAL_ALIGNMENT_CENTER, badge_w, badge_text_size, NeuKit.COBALT)
        draw_string(font, Vector2(right_badge.position.x, right_badge.position.y + 27.0), "RIGHT", HORIZONTAL_ALIGNMENT_CENTER, badge_w, badge_text_size, Color("E04555"))

        for it in current_challenge.visual_data.get("left_items", []):
                _draw_shape_item(Vector2(pad + float(it["x"]) * play_w, pad + float(it["y"]) * play_h), it, 0.0)
        for it in current_challenge.visual_data.get("right_items", []):
                _draw_shape_item(Vector2(pad + float(it["x"]) * play_w, pad + float(it["y"]) * play_h), it, 0.0)

func _draw_single_field(pad: float, play_w: float, play_h: float) -> void:
        var tray_rect := Rect2(4.0, 4.0, size.x - 8.0, size.y - 8.0)
        draw_style_box(_tray, tray_rect)
        var items: Array = current_challenge.visual_data.get("items", [])
        for i in range(items.size()):
                var it = items[i]
                var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
                # Animated pressed amount: follows selection, so unselect springs back out.
                var press: float = float(_press_anim.get(i, 1.0 if i in tapped_indices else 0.0))
                var ripple_t: float = float(_sink.get(i, -1.0))
                var rise := 1.0
                if _rise_active:
                        rise = clampf((_rise_t - 0.05 - float(_rise_rank[i] if i < _rise_rank.size() else i) * 0.04) / 0.32, 0.0, 1.0)
                _draw_shape_item(center, it, press, rise, ripple_t)

func _token_style(color_name: String, col: Color) -> NeuStyle:
        # Keyed by vision mode too: switching the palette mid-session (settings
        # sheet between rounds) must not serve a stale sculpted style.
        var cache_key := "%s|%s" % [ColorVision.mode(), color_name]
        if not _token_styles.has(cache_key):
                # Elevated resting shadow: deeper distance/blur than a generic raised
                # surface so each token reads as a piece genuinely lifted off the tray.
                var style: NeuStyle = NeuKit.raised(10.0, 5.0, 11.0, col) if color_name == "WHITE" else NeuKit.accent(col, 10.0, 5.0, 11.0)
                style.light = Color(1.0, 1.0, 1.0, 0.58)
                style.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.40)
                style.rim = 0.56
                style.gradient = 0.74
                if color_name == "WHITE":
                        style.surface = col.lightened(0.018)
                        style.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.50)
                else:
                        style.glow = Color(col.r, col.g, col.b, 0.30)
                _token_styles[cache_key] = style
        return _token_styles[cache_key]

func _draw_shape_item(center: Vector2, it: Dictionary, press: float, rise: float = 1.0, ripple_t: float = -1.0) -> void:
        # Tap rounds seat every token in its own sunken socket; counting rounds stay uncluttered.
        var use_pad: bool = current_challenge.input_mode in ["tap_targets", "withhold_response"]
        var sz: float = float(it.get("size", 24.0)) * (1.28 if use_pad else 1.22)
        var color_name: String = str(it.get("color", "MINT")).to_upper()
        var col: Color = _resolve_color(color_name)
        var shape: String = str(it.get("shape", "circle"))
        var k: float = clampf(sz / 42.0, 0.55, 1.0)
        var seated: bool = press > 0.5

        # 1.3 = floating well clear of the surface, -0.9 = pressed into it. `press`
        # animates between them, so selecting AND unselecting both play as a smooth
        # physical move. The raised end sits above NeuStyle's usual 1.0 resting depth
        # so every token/polygon reads as distinctly elevated, not just flush-raised.
        var e: float = 1.0 - pow(1.0 - clampf(press, 0.0, 1.0), 3.0)
        var depth: float = lerpf(1.3, -0.9, e)

        if use_pad:
                _pad.depth = lerpf(-0.8, -1.0, clampf(press, 0.0, 1.0))
                NeuKit.disc(self, _pad, center, sz * 0.80)
                # A fine machined rim makes each socket feel manufactured rather than flat.
                var socket_segments := mini(30, _token_detail_segments)
                draw_arc(center, sz * 0.68, PI * 1.08, PI * 1.88, socket_segments, Color(1.0, 1.0, 1.0, 0.22), 1.2, true)
                draw_arc(center, sz * 0.69, PI * 0.10, PI * 0.88, socket_segments, Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.14), 1.2, true)

        # Entrance: the token lifts out of its socket - small and flat at first, then it springs
        # up past full size while its shadows grow, which reads as physically rising.
        if rise < 1.0:
                if rise <= 0.0:
                        return
                var er: float = _back(rise)
                sz *= lerpf(0.35, 1.0, clampf(er, 0.0, 1.15))
                depth = lerpf(0.0, depth, clampf(er, 0.0, 1.0))

        # Don't Tap stimuli keep an alert halo so the rule stays readable.
        # The halo follows the active colour-vision red (v18): under a CVD
        # palette the ring can never disagree with the token it marks.
        if current_challenge.input_mode == "withhold_response" and color_name in ["RED", "CORAL"] and not seated:
                var halo := ColorVision.halo()
                var halo_r: float = sz * (0.95 if use_pad else 0.78)
                draw_circle(center, halo_r, Color(halo.r, halo.g, halo.b, 0.07))
                draw_arc(center, halo_r, 0.0, TAU, mini(36, _token_detail_segments), Color(halo.r, halo.g, halo.b, 0.42), 2.5, true)

        match shape:
                "square", "circle":
                        var style: NeuStyle = _token_style(color_name, col)
                        style.depth = depth
                        style.shadow_steps_override = _token_shadow_steps
                        style.distance = clampf(sz * 0.20, 4.5, 9.5)
                        style.blur = clampf(sz * 0.46, 10.0, 19.0)
                        if shape == "circle":
                                NeuKit.sphere_token(self, style, center, sz * 0.5, 0.38)
                                _draw_circle_polish(center, sz, col, depth)
                        else:
                                var side: float = sz * 0.92
                                style.corner_radius = side * 0.22
                                draw_style_box(style, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)))
                                _draw_square_polish(center, side, col, depth)
                _:
                        var pts: PackedVector2Array
                        if shape == "triangle":
                                var half: float = sz * 0.5
                                pts = PackedVector2Array([center + Vector2(0, -half * 1.1), center + Vector2(-half, half * 0.85), center + Vector2(half, half * 0.85)])
                        else:
                                var h2: float = sz * 0.56
                                pts = PackedVector2Array([center + Vector2(0, -h2), center + Vector2(h2, 0), center + Vector2(0, h2), center + Vector2(-h2, 0)])
                        # Full-strength cast shadow (polygons previously ran at 0.62 of the
                        # token's shadow, which read as flatter/less lifted than the circles
                        # and squares beside them) and an extra step for a smoother falloff.
                        var rounded := NeuKit.round_poly(pts, sz * 0.11)
                        NeuKit.poly_token(self, rounded, col, depth, k, mini(_token_shadow_steps, 4), 1.0)
                        _draw_polygon_polish(rounded, center, sz, col, depth, shape)

        if ripple_t >= 0.0 and ripple_t < 1.0:
                # Ripple: a mint ring spreads out from the freshly pressed token.
                draw_arc(center, sz * (0.55 + 0.95 * ripple_t), 0.0, TAU, mini(36, _token_detail_segments), Color(NeuKit.MINT.r, NeuKit.MINT.g, NeuKit.MINT.b, 0.55 * (1.0 - ripple_t)), 3.0, true)

        var badge_a: float = clampf((press - 0.35) / 0.4, 0.0, 1.0)
        if badge_a > 0.0:
                var ring_r: float = sz * (0.84 if use_pad else 0.64)
                draw_arc(center, ring_r, 0.0, TAU, mini(40, _token_detail_segments), Color(NeuKit.MINT.r, NeuKit.MINT.g, NeuKit.MINT.b, 0.85 * badge_a), 3.0, true)
                var badge := center + Vector2(sz * 0.48, -sz * 0.48) if use_pad else center + Vector2(sz * 0.40, -sz * 0.40)
                draw_circle(badge, sz * 0.22, Color(1.0, 1.0, 1.0, badge_a))
                draw_circle(badge, sz * 0.18, Color(NeuKit.MINT.r, NeuKit.MINT.g, NeuKit.MINT.b, badge_a))
                _draw_checkmark(badge, sz * 0.18, Color(1.0, 1.0, 1.0, badge_a))

## Fine surface lighting shared by the token family. These restrained details keep
## silhouettes instantly readable while giving every shape a premium enamel finish.
func _draw_circle_polish(center: Vector2, sz: float, col: Color, depth: float) -> void:
        var a := clampf(depth, 0.0, 1.0)
        var r := sz * 0.5
        var segments := _token_detail_segments
        draw_arc(center, r * 0.91, 0.0, TAU, segments, Color(1.0, 1.0, 1.0, 0.13 * a), 1.1, true)
        draw_arc(center, r * 0.86, PI * 0.14, PI * 0.86, maxi(12, int(round(float(segments) * 0.58))), Color(col.darkened(0.48), 0.20 * a), maxf(1.1, sz * 0.025), true)
        draw_arc(center, r * 0.88, PI * 1.12, PI * 1.68, maxi(10, int(round(float(segments) * 0.50))), Color(1.0, 1.0, 1.0, 0.34 * a), maxf(1.0, sz * 0.022), true)
        draw_line(center + Vector2(-r * 0.40, -r * 0.44), center + Vector2(-r * 0.16, -r * 0.55), Color(1.0, 1.0, 1.0, 0.48 * a), maxf(1.4, sz * 0.055), true)
        draw_circle(center + Vector2(r * 0.30, r * 0.34), r * 0.075, Color(col.lightened(0.65), 0.20 * a))

func _draw_square_polish(center: Vector2, side: float, col: Color, depth: float) -> void:
        var a := clampf(depth, 0.0, 1.0)
        var h := side * 0.5
        var inset := side * 0.14
        var top_left := center + Vector2(-h + inset, -h + inset * 0.58)
        var top_right := center + Vector2(h - inset * 1.35, -h + inset * 0.58)
        var bottom_left := center + Vector2(-h + inset * 0.58, h - inset)
        draw_line(top_left, top_right, Color(1.0, 1.0, 1.0, 0.35 * a), maxf(1.1, side * 0.025), true)
        draw_line(top_left + Vector2(-inset * 0.42, inset * 0.42), bottom_left, Color(1.0, 1.0, 1.0, 0.22 * a), maxf(1.0, side * 0.020), true)
        draw_line(center + Vector2(-h + inset * 1.4, h - inset * 0.62), center + Vector2(h - inset, h - inset * 0.62), Color(col.darkened(0.46), 0.20 * a), maxf(1.0, side * 0.022), true)
        draw_circle(center + Vector2(-side * 0.23, -side * 0.23), side * 0.042, Color(1.0, 1.0, 1.0, 0.40 * a))
        draw_circle(center + Vector2(side * 0.25, side * 0.26), side * 0.035, Color(col.lightened(0.65), 0.16 * a))

func _draw_polygon_polish(pts: PackedVector2Array, center: Vector2, sz: float, col: Color, depth: float, shape: String) -> void:
        # Facet hints only: NeuKit.poly_token now owns the sheen, rim lighting and
        # specular, so the polish just deepens the lower facets a touch.
        var a := clampf(depth, 0.0, 1.0)
        if shape == "triangle" and pts.size() >= 3:
                draw_line(pts[1].lerp(center, 0.10), pts[2].lerp(center, 0.10), Color(col.darkened(0.50), 0.18 * a), maxf(1.1, sz * 0.024), true)
        elif pts.size() >= 4:
                var lower := PackedVector2Array([pts[1].lerp(center, 0.10), pts[2].lerp(center, 0.10), pts[3].lerp(center, 0.10)])
                draw_polyline(lower, Color(col.darkened(0.50), 0.15 * a), maxf(1.1, sz * 0.022), true)

func _draw_checkmark(center: Vector2, sz: float, col: Color) -> void:
        var p1 = center + Vector2(-sz * 0.45, 0.0)
        var p2 = center + Vector2(-sz * 0.1, sz * 0.35)
        var p3 = center + Vector2(sz * 0.45, -sz * 0.35)
        draw_polyline(PackedVector2Array([p1, p2, p3]), col, maxf(2.0, sz * 0.3), true)

## v18: resolution goes through ColorVision so the active colour-vision
## palette applies at RENDER time only - challenge data, seeds and network
## packets still carry the abstract names, and every phone keeps its own view.
func _resolve_color(col_name: String) -> Color:
        return ColorVision.resolve(col_name)
