extends Control

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Records = preload("res://scripts/core/Records.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const SpotRushButton = preload("res://scripts/ui/SpotRushButton.gd")

@onready var hero_card: Control = %HeroCard
@onready var medal: Control = %Medal
@onready var lbl_outcome: NeuText = %LblOutcome
@onready var lbl_final_scores: NeuText = %LblFinalScores
@onready var new_best_chip: Control = %NewBestChip
@onready var versus_box: Control = %VersusBox
@onready var versus_bar: Control = %VersusBar
@onready var lbl_vs_mine: NeuText = %LblVsMine
@onready var lbl_vs_opp: NeuText = %LblVsOpp
@onready var gauge: Control = %AccuracyGauge
@onready var lbl_gauge_pct: NeuText = %LblGaugePct
@onready var lbl_gauge_sub: NeuText = %LblGaugeSub
@onready var val_correct: NeuText = %ValCorrect
@onready var val_wrong: NeuText = %ValWrong
@onready var val_timeouts: NeuText = %ValTimeouts
@onready var val_streak: NeuText = %ValStreak
@onready var val_avg: NeuText = %ValAvg
@onready var val_fastest: NeuText = %ValFastest
@onready var lbl_best_round: NeuText = %LblBestRound
@onready var round_chart: Control = %RoundChart
@onready var btn_rematch: Button = %BtnRematch
@onready var btn_menu: Button = %BtnMenu
@onready var burst_layer: Control = %BurstLayer

var is_navigating: bool = false
var _final_score: int = 0
var _accuracy: float = 0.0
var _is_new_best: bool = false
var _last_count_tick_ms: int = 0
var _challenge_correct: int = 0
var _challenge_rounds: int = 0

func _ready() -> void:
        SpotRushSkin.apply_screen(self, "results")
        BackNav.register(self)
        NeuSafe.fit(get_node_or_null("SafeArea"))
        Music.play_menu()
        _tighten_stat_tiles()
        _apply_column_layout()
        _apply_results_typography()
        resized.connect(_apply_column_layout)
        if not get_viewport().size_changed.is_connected(_apply_column_layout):
                get_viewport().size_changed.connect(_apply_column_layout)
        # Android can settle its viewport after the scene is mounted. Reapply
        # the safe-area baseline and the centered content measure after layout.
        await get_tree().process_frame
        if not is_inside_tree():
                return
        _refresh_safe_area()
        await get_tree().process_frame
        if not is_inside_tree():
                return
        _refresh_safe_area()
        _label_button(btn_rematch, "PLAY AGAIN", 31)
        _label_button(btn_menu, "MAIN MENU", 26)
        btn_rematch.pressed.connect(_on_rematch_pressed)
        btn_menu.pressed.connect(_on_menu_pressed)
        _populate_results()
        _play_intro()

## Result actions use the shared raised SpotRushButton style.
func _label_button(btn: Button, caption: String, font_size: int) -> void:
        # Results actions use the exact same raised key and cobalt ink as the lobby tabs.
        var viewport_size := get_viewport_rect().size
        var portrait := viewport_size.x < 860.0 or viewport_size.y > viewport_size.x * 1.18
        var resolved_size := (28 if caption == "PLAY AGAIN" else 25) if portrait else font_size
        SpotRushButton.configure(btn, caption, {"font_size": resolved_size, "radius": 22.0})

## Keep the results content centered and capped on wide/stale Android
## viewports, while preserving the idempotent safe-area baseline.
func _apply_column_layout() -> void:
        var safe := get_node_or_null("SafeArea") as MarginContainer
        if safe == null:
                return
        var viewport_size := get_viewport_rect().size
        if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
                return
        var insets := NeuSafe.canvas_insets()
        var available := maxf(280.0, viewport_size.x - insets.x - insets.z)
        var is_portrait_phone := available < 860.0 or viewport_size.y > viewport_size.x * 1.18
        var max_content_width := 760.0 if not is_portrait_phone else 720.0
        var content_width := minf(max_content_width, available)
        var side := maxf(0.0, (available - content_width) * 0.5)
        # NeuSafe.fit() already moves the SafeArea edges inward. Do not add the
        # OS insets a second time as the old code did; only apply the inner gutter.
        safe.add_theme_constant_override("margin_left", int(round(side + (12.0 if is_portrait_phone else 20.0))))
        safe.add_theme_constant_override("margin_right", int(round(side + (12.0 if is_portrait_phone else 20.0))))
        safe.add_theme_constant_override("margin_top", 14 if is_portrait_phone else 26)
        safe.add_theme_constant_override("margin_bottom", 14 if is_portrait_phone else 26)
        safe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        safe.custom_minimum_size = Vector2(0.0, 0.0)
        if is_portrait_phone:
                _apply_portrait_results_layout()

## Portrait hierarchy: score summary, full-width accuracy, a 3x2 stat grid,
## chart and actions. No side-by-side minimum widths can push the screen off-canvas.
func _apply_portrait_results_layout() -> void:
        var main := get_node_or_null("SafeArea/VBoxMain") as VBoxContainer
        var mid := get_node_or_null("SafeArea/VBoxMain/MidRow") as HBoxContainer
        var gauge_card := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard") as PanelContainer
        var grid := get_node_or_null("SafeArea/VBoxMain/MidRow/StatGrid") as GridContainer
        if main == null or mid == null or gauge_card == null or grid == null:
                return

        # Keep the gauge and stats side by side, but give the gauge a fixed,
        # deliberately narrow column. The old 200px dial plus a 2-column grid
        # could exceed a phone's inner width and push the right tiles off-screen.
        mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        mid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        mid.custom_minimum_size = Vector2(0.0, 248.0)
        mid.add_theme_constant_override("separation", 10)
        gauge_card.size_flags_horizontal = Control.SIZE_FILL
        gauge_card.size_flags_stretch_ratio = 0.0
        gauge_card.custom_minimum_size = Vector2(148.0, 248.0)
        var gauge_node := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox/AccuracyGauge") as Control
        if gauge_node != null:
                gauge_node.custom_minimum_size = Vector2(112.0, 112.0)
        var gauge_vbox := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox") as VBoxContainer
        if gauge_vbox != null:
                gauge_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
                gauge_vbox.add_theme_constant_override("separation", 2)
        var gauge_caption := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox/LblGaugeCap") as Control
        if gauge_caption != null:
                gauge_caption.custom_minimum_size.y = 26.0
        var gauge_sub := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox/LblGaugeSub") as Control
        if gauge_sub != null:
                gauge_sub.custom_minimum_size.y = 22.0

        # Two columns of three tiles. This preserves the compact dashboard feel
        # while assigning the grid only the width that remains beside the gauge.
        grid.columns = 2
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        grid.custom_minimum_size = Vector2(0.0, 0.0)
        grid.add_theme_constant_override("h_separation", 8)
        grid.add_theme_constant_override("v_separation", 8)
        for tile in grid.get_children():
                if tile is PanelContainer:
                        tile.custom_minimum_size = Vector2(0.0, 76.0)
                        var col := tile.get_node_or_null("Col") as VBoxContainer
                        if col != null:
                                col.add_theme_constant_override("separation", 2)
                        var cap := tile.get_node_or_null("Col/Cap") as Control
                        if cap != null:
                                cap.custom_minimum_size.y = 22.0
                        var value := tile.get_node_or_null("Col/ValRow") as HBoxContainer
                        if value != null:
                                value.add_theme_constant_override("separation", 4)
                                var icon := value.get_node_or_null("Icon") as Control
                                if icon != null:
                                        icon.custom_minimum_size = Vector2(20.0, 20.0)
                                var value_text: Control = null
                                if value.get_child_count() > 1:
                                        value_text = value.get_child(1) as Control
                                if value_text != null:
                                        value_text.custom_minimum_size.y = 40.0

        var chart_card := get_node_or_null("SafeArea/VBoxMain/ChartCard") as PanelContainer
        if chart_card != null:
                chart_card.custom_minimum_size.y = 280.0
        var chart_vbox := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox") as VBoxContainer
        if chart_vbox != null:
                chart_vbox.add_theme_constant_override("separation", 6)
                var old_header := chart_vbox.get_node_or_null("ChartHeader") as HBoxContainer
                if old_header != null and chart_vbox.get_node_or_null("ChartHeaderStack") == null:
                        var header_index := old_header.get_index()
                        var stack := VBoxContainer.new()
                        stack.name = "ChartHeaderStack"
                        stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                        stack.add_theme_constant_override("separation", 2)
                        for child in old_header.get_children():
                                old_header.remove_child(child)
                                stack.add_child(child)
                        chart_vbox.remove_child(old_header)
                        chart_vbox.add_child(stack)
                        chart_vbox.move_child(stack, header_index)
                        old_header.queue_free()
        var chart_title := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/ChartHeaderStack/LblChartTitle") as Control
        if chart_title != null:
                chart_title.custom_minimum_size.y = 34.0
                chart_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var best_label := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/ChartHeaderStack/LblBestRound") as NeuText
        if best_label != null:
                best_label.custom_minimum_size.y = 58.0
                best_label.autowrap = true
                best_label.align = HORIZONTAL_ALIGNMENT_LEFT
                best_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var chart := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/RoundChart") as Control
        if chart != null:
                chart.custom_minimum_size.y = 150.0
                chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                chart.queue_redraw()

        var hero_row := get_node_or_null("SafeArea/VBoxMain/HeroCard/HeroRow") as HBoxContainer
        if hero_row != null:
                hero_row.add_theme_constant_override("separation", 14)
        var medal_node := get_node_or_null("SafeArea/VBoxMain/HeroCard/HeroRow/Medal") as Control
        if medal_node != null:
                medal_node.custom_minimum_size = Vector2(112.0, 112.0)
        var outcome := get_node_or_null("SafeArea/VBoxMain/HeroCard/HeroRow/HeroText/LblOutcome") as Control
        if outcome != null:
                outcome.custom_minimum_size.y = 42.0
        var score_caption := get_node_or_null("SafeArea/VBoxMain/HeroCard/HeroRow/HeroText/LblScoreCaption") as Control
        if score_caption != null:
                score_caption.custom_minimum_size.y = 20.0
        var score_value := get_node_or_null("SafeArea/VBoxMain/HeroCard/HeroRow/HeroText/LblFinalScores") as Control
        if score_value != null:
                score_value.custom_minimum_size.y = 64.0

        main.add_theme_constant_override("separation", 7)
        var actions := get_node_or_null("SafeArea/VBoxMain/ActionsContainer") as HBoxContainer
        if actions != null:
                actions.add_theme_constant_override("separation", 10)
        for button in [btn_rematch, btn_menu]:
                button.custom_minimum_size = Vector2(0.0, 64.0)
                button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _refresh_safe_area() -> void:
        NeuSafe.fit(get_node_or_null("SafeArea") as Control)
        _apply_column_layout()

## Slimmer stat wells so the six tiles never force the row past the column.
func _tighten_stat_tiles() -> void:
        var grid := get_node_or_null("SafeArea/VBoxMain/MidRow/StatGrid") as GridContainer
        if grid == null:
                return
        for tile in grid.get_children():
                if tile is PanelContainer:
                        var style := (tile as PanelContainer).get_theme_stylebox("panel") as NeuStyle
                        if style != null:
                                style.content_margin_left = 8.0
                                style.content_margin_right = 8.0
                                style.content_margin_top = 6.0
                                style.content_margin_bottom = 6.0
                                style.emit_changed()

## Results cards use dedicated semantic roles so their captions remain readable
## without changing the compact typography used elsewhere in the game.
func _apply_results_typography() -> void:
        var gauge_title := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox/LblGaugeCap") as Control
        if gauge_title != null:
                SpotRushTypography.apply_as(gauge_title, SpotRushTypography.Role.CARD_TITLE)
        SpotRushTypography.apply_as(lbl_gauge_pct, SpotRushTypography.Role.DISPLAY)
        SpotRushTypography.apply_as(lbl_gauge_sub, SpotRushTypography.Role.BODY)

        var stat_grid := get_node_or_null("SafeArea/VBoxMain/StatGrid") as GridContainer
        if stat_grid == null:
                stat_grid = get_node_or_null("SafeArea/VBoxMain/MidRow/StatGrid") as GridContainer
        if stat_grid != null:
                for tile in stat_grid.get_children():
                        var title := tile.get_node_or_null("Col/Cap") as Control
                        if title != null:
                                SpotRushTypography.apply_as(title, SpotRushTypography.Role.STAT_LABEL)

        var chart_title := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/ChartHeaderStack/LblChartTitle") as Control
        if chart_title == null:
                chart_title = get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/ChartHeader/LblChartTitle") as Control
        if chart_title != null:
                SpotRushTypography.apply_as(chart_title, SpotRushTypography.Role.CARD_TITLE)
        SpotRushTypography.apply_as(lbl_best_round, SpotRushTypography.Role.STAT_LABEL)

static func rank_for(accuracy: float) -> String:
        if accuracy >= 95.0:
                return "S"
        if accuracy >= 80.0:
                return "A"
        if accuracy >= 60.0:
                return "B"
        return "C"

static func _get_stats(player_stats: Dictionary, id: int) -> Dictionary:
        return player_stats.get(id, player_stats.get(str(id), {}))

func _populate_results() -> void:
        var results: Dictionary = GameManager.last_match_results
        var is_multiplayer: bool = GameManager.current_game_mode != GameConfig.GameMode.SINGLE_PLAYER
        if results.is_empty():
                lbl_outcome.text = "MATCH COMPLETE"
                medal.rank = "C"
                return

        var local_id: int = NetworkSession.get_local_id() if is_multiplayer else 1
        var winner_id: int = results.get("winner_id", -1)
        var player_stats: Dictionary = results.get("player_stats", {})
        var my_stats: Dictionary = _get_stats(player_stats, local_id)
        _final_score = int(my_stats.get("total_score", 0))
        _accuracy = float(my_stats.get("accuracy", 0.0))

        var correct: int = int(my_stats.get("correct_count", 0))
        var wrong: int = int(my_stats.get("incorrect_count", 0))
        var missed: int = int(my_stats.get("missed_count", 0))
        var rounds: int = correct + wrong + missed
        var rank := rank_for(_accuracy)
        medal.rank = rank

        # --- headline ---------------------------------------------------------------------
        if not is_multiplayer:
                match rank:
                        "S": lbl_outcome.text = "OUTSTANDING!"
                        "A": lbl_outcome.text = "GREAT RUN!"
                        "B": lbl_outcome.text = "NICE WORK!"
                        _: lbl_outcome.text = "KEEP SPOTTING!"
                lbl_outcome.color = NeuKit.INK
                if GameManager.is_challenge_match:
                        # Rival Codes: a replayable seeded run can never touch the solo
                        # records - the same code would farm the leaderboard forever.
                        # The result is remembered only for the invite brag, and only
                        # when the run was played on the player's own code.
                        _challenge_correct = correct
                        _challenge_rounds = rounds
                        lbl_outcome.text = "CHALLENGE RUN DONE!"
                        lbl_outcome.color = Color("1F9F70")
                        Records.challenge_record_own_result(GameManager.challenge_code_value,
                                        _final_score, correct, rounds)
                        _rematch_as_share("COPY RESULT")
                else:
                        if Records.submit(_final_score):
                                _is_new_best = true
                                new_best_chip.visible = true
                        if GameManager.is_daily_match:
                                _record_daily(my_stats, correct, rounds)
        else:
                if results.get("is_tie", false):
                        lbl_outcome.text = "IT'S A TIE!"
                        lbl_outcome.color = Color("B07A0A")
                elif winner_id == local_id:
                        lbl_outcome.text = "VICTORY!"
                        lbl_outcome.color = Color("1F9F70")
                else:
                        lbl_outcome.text = "DEFEAT"
                        lbl_outcome.color = Color("D63A4A")
                var opp_id := -1
                for pid in GameManager.match_controller.player_ids:
                        if pid != local_id:
                                opp_id = pid
                                break
                var opp_stats := _get_stats(player_stats, opp_id)
                var opp_score: int = int(opp_stats.get("total_score", 0))
                versus_box.visible = true
                lbl_vs_mine.text = "YOU  %s" % Records.format(_final_score)
                lbl_vs_opp.text = "%s  OPP" % Records.format(opp_score)
                versus_bar.set_scores(_final_score, opp_score)

        # --- stats ----------------------------------------------------------------------
        lbl_gauge_sub.text = "%d / %d correct" % [correct, rounds]
        val_correct.text = str(correct)
        val_wrong.text = str(wrong)
        val_timeouts.text = str(missed)
        var best_streak_val: int = int(my_stats.get("max_streak", 0))
        val_streak.text = str(best_streak_val)
        if not is_multiplayer and best_streak_val > 0 and Records.submit_streak(best_streak_val):
                val_streak.text = "%d NEW!" % best_streak_val
        var times: Array = my_stats.get("response_times", [])
        val_avg.text = "%.2fs" % float(my_stats.get("avg_response_time", 0.0))
        if times.is_empty():
                val_fastest.text = "--"
        else:
                var fastest := 999.0
                for t in times:
                        fastest = minf(fastest, float(t))
                val_fastest.text = "%.2fs" % fastest

        var best_idx: int = int(my_stats.get("best_round_index", -1))
        var best_score: int = int(my_stats.get("best_round_score", 0))
        var best_parts := PackedStringArray()
        if best_idx >= 0:
                best_parts.append("BEST R%d  +%s" % [best_idx + 1, Records.format(best_score)])
        if best_idx >= 0 and best_score > 0 and not is_multiplayer and Records.submit_round(best_score):
                best_parts.append("NEW PB")
        var grade_counts: Dictionary = my_stats.get("grade_counts", {})
        var s_ranks: int = int(grade_counts.get("S", 0))
        if s_ranks > 0:
                best_parts.append("S-RANK ×%d" % s_ranks)
        lbl_best_round.text = "  •  ".join(best_parts)
        round_chart.set_data(my_stats.get("round_scores", []), best_idx)

        gauge.custom_color = Color("2DBE88") if _accuracy >= 80.0 else (NeuKit.CANARY if _accuracy >= 50.0 else Color("EE4458"))
        lbl_gauge_pct.color = gauge.custom_color.darkened(0.12)

func _play_intro() -> void:
        var ratio := clampf(_accuracy / 100.0, 0.0, 1.0)
        if Feel.reduced():
                # Reduce Motion: show the final numbers straight away, no rising / counting / sweeping.
                _set_score_text(float(_final_score))
                _set_gauge(ratio)
                _chime_for_rank(0.1)
                return
        # Cards rise in one after another; numbers count up and the gauge/bars sweep in.
        var cards: Array = [hero_card, get_node("SafeArea/VBoxMain/MidRow")]
        var stat_grid := get_node_or_null("SafeArea/VBoxMain/StatGrid")
        if stat_grid != null:
                cards.append(stat_grid)
        cards.append(get_node("SafeArea/VBoxMain/ChartCard"))
        cards.append(get_node("SafeArea/VBoxMain/ActionsContainer"))
        for card in cards:
                (card as Control).modulate.a = 0.0 # hidden immediately so nothing flashes before the stagger
        await get_tree().process_frame
        Feel.sfx("whoosh", 1.0, -3.0)
        for i in cards.size():
                var card: Control = cards[i]
                card.pivot_offset = card.size * 0.5
                card.modulate.a = 0.0
                card.scale = Vector2(0.94, 0.94)
                var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
                tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_delay(0.08 * i)
                tw.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.08 * i)
        medal.pop(0.12)
        _chime_for_rank(0.34)

        lbl_final_scores.text = "0"
        create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
                .tween_method(_set_score_text_animated, 0.0, float(_final_score), 1.1).set_delay(0.25)

        gauge.set_time(0.0, 1.0)
        lbl_gauge_pct.text = "0%"
        create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
                .tween_method(_set_gauge, 0.0, ratio, 1.0).set_delay(0.4)
        round_chart.animate_in(0.55)

        # Celebration once the count-up lands: new personal best or an S rank.
        if _is_new_best or medal.rank == "S":
                get_tree().create_timer(1.45).timeout.connect(_celebrate)

func _chime_for_rank(delay: float) -> void:
        var pitch: float = {"S": 1.25, "A": 1.0, "B": 0.9}.get(medal.rank, 0.75)
        get_tree().create_timer(delay).timeout.connect(func(): Feel.sfx("chime", pitch))

func _celebrate() -> void:
        Feel.sfx("fanfare")
        Feel.haptic("success")
        var origin: Vector2 = burst_layer.get_global_transform().affine_inverse() * (medal.global_position + medal.size * 0.5)
        var palette: Array = [NeuKit.CANARY, NeuKit.COBALT, NeuKit.MINT, NeuKit.CORAL, NeuKit.LAVENDER]
        burst_layer.burst(origin, palette, 34, 1.15, 2.0)

## Count-up variant that also ticks softly (throttled, pitch rising toward the final value).
func _set_score_text_animated(v: float) -> void:
        _set_score_text(v)
        var now := Time.get_ticks_msec()
        if _final_score > 0 and v < float(_final_score) * 0.985 and now - _last_count_tick_ms > 70:
                _last_count_tick_ms = now
                Feel.sfx("count", 0.85 + 0.6 * (v / float(_final_score)))

func _set_score_text(v: float) -> void:
        lbl_final_scores.text = Records.format(int(round(v)))

func _set_gauge(v: float) -> void:
        gauge.set_time(v, 1.0)
        lbl_gauge_pct.text = "%d%%" % int(round(v * 100.0))

## Daily Spot bookkeeping: record the day's result (streak + shield rules live
## in Records), then repurpose the rematch key as the share key - the daily is
## once per day, so "play again" would break the loop's scarcity.
func _record_daily(my_stats: Dictionary, correct: int, rounds: int) -> void:
        var max_mult: int = int(my_stats.get("max_multiplier", 1))
        var grade_counts_daily: Dictionary = my_stats.get("grade_counts", {})
        var dres: Dictionary = Records.daily_record(_final_score, correct, rounds, max_mult, int(grade_counts_daily.get("S", 0)))
        lbl_outcome.text = "DAILY #%d DONE!" % int(dres.get("daily_no", 1))
        _rematch_as_share("SHARE RESULT")

## Repurpose the rematch key as a copy key while retaining the shared button style.
func _rematch_as_share(text: String) -> void:
        # Keep dynamic labels on Button.text so the shared label component mirrors them.
        btn_rematch.text = text

func _share_challenge_result() -> void:
        DisplayServer.clipboard_set(Records.challenge_result_share_text(
                        _final_score, _challenge_correct, _challenge_rounds,
                        GameManager.challenge_code_value))
        Feel.sfx("pop")
        btn_rematch.text = "COPIED!"
        get_tree().create_timer(1.2).timeout.connect(func():
                if is_instance_valid(btn_rematch) and btn_rematch.is_inside_tree():
                        btn_rematch.text = "COPY RESULT")

func _share_daily_result() -> void:
        DisplayServer.clipboard_set(Records.daily_share_text())
        Feel.sfx("pop")
        btn_rematch.text = "COPIED!"
        get_tree().create_timer(1.2).timeout.connect(func():
                if is_instance_valid(btn_rematch) and btn_rematch.is_inside_tree():
                        btn_rematch.text = "SHARE RESULT")

func _on_rematch_pressed() -> void:
        if GameManager.is_daily_match:
                _share_daily_result()
                return
        if GameManager.is_challenge_match:
                _share_challenge_result()
                return
        if is_navigating:
                return
        is_navigating = true
        btn_rematch.disabled = true
        btn_menu.disabled = true
        
        if GameManager.current_game_mode == GameConfig.GameMode.SINGLE_PLAYER:
                # Queue (don't start) the rematch: GameScreen doesn't exist yet, so
                # starting the match directly here fires its opening countdown/round
                # signals into the void before anything is listening, leaving round 1
                # stuck on the view's placeholder text with no challenge ever loaded.
                # The queue is consumed only after GameScreen has connected its UI
                # signals (see GameManager.queue_single_player_start).
                GameManager.queue_single_player_start(GameManager.match_controller.total_rounds)
                SceneRouter.goto_game()
        elif GameManager.current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
                GameManager.queue_multiplayer_host_start(GameManager.match_controller.total_rounds)
                SceneRouter.goto_game()
        elif GameManager.current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
                # Wait for host to restart or return to lobby
                lbl_outcome.text = "WAITING FOR HOST..."
                is_navigating = false
                btn_menu.disabled = false

func _on_menu_pressed() -> void:
        if is_navigating:
                return
        is_navigating = true
        btn_rematch.disabled = true
        btn_menu.disabled = true
        NetworkSession.disconnect_session()
        SceneRouter.goto_main_menu()

# --- HARDWARE BACK (v19) ------------------------------------------------------------

func _exit_tree() -> void:
        BackNav.unregister(self)

## Android back / desktop Escape from the results screen: exactly what the
## MAIN MENU key does - plain "up" navigation, nothing to confirm.
func handle_back() -> bool:
        _on_menu_pressed()
        return true