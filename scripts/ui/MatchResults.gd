extends Control

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Records = preload("res://scripts/core/Records.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

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
        _apply_results_typography()
        # Results uses the exact same full-rect SafeArea and authored margins
        # as GameScreen. There is no independent max-width column or centering
        # calculation: all cards inherit the gameplay content width.
        get_viewport().size_changed.connect(_refresh_safe_area)
        await get_tree().process_frame
        if not is_inside_tree():
                return
        _refresh_safe_area()
        await get_tree().process_frame
        if not is_inside_tree():
                return
        _refresh_safe_area()
        _label_button(btn_rematch, "PLAY AGAIN", 3, 31, Color.WHITE, NeuKit.COBALT)
        _label_button(btn_menu, "MAIN MENU", 0, 26, NeuKit.SLATE, NeuKit.COBALT)
        btn_rematch.pressed.connect(_on_rematch_pressed)
        btn_menu.pressed.connect(_on_menu_pressed)
        _populate_results()
        _play_intro()

## Button captions are NeuText children so they can be engraved / lit and dip with the key.
func _label_button(btn: Button, caption: String, look: int, font_size: int, color: Color, base: Color) -> void:
        btn.text = ""
        var label := NeuText.new()
        label.text = caption
        label.font_size = font_size
        label.color = color
        label.look = look
        label.accent_base = base
        label.tracking = 2.0
        label.set_anchors_preset(Control.PRESET_FULL_RECT)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(label)
        if btn.has_meta("neu_style"):
                label.bind_style(btn.get_meta("neu_style"))

## Reapply the shared safe-area offsets when Android reports its settled viewport.
## NeuSafe.fit() is idempotent, so this cannot accumulate margins across visits.
func _refresh_safe_area() -> void:
        NeuSafe.fit(get_node_or_null("SafeArea") as Control)

## Slimmer stat wells so the six tiles never force the row past the column.
func _tighten_stat_tiles() -> void:
        var grid := get_node_or_null("SafeArea/VBoxMain/MidRow/StatGrid") as GridContainer
        if grid == null:
                return
        for tile in grid.get_children():
                if tile is PanelContainer:
                        var style := (tile as PanelContainer).get_theme_stylebox("panel") as NeuStyle
                        if style != null:
                                style.content_margin_left = 12.0
                                style.content_margin_right = 12.0
                                style.content_margin_top = 9.0
                                style.content_margin_bottom = 9.0
                                style.emit_changed()

## Results cards use dedicated semantic roles so their captions remain readable
## without changing the compact typography used elsewhere in the game.
func _apply_results_typography() -> void:
        var gauge_title := get_node_or_null("SafeArea/VBoxMain/MidRow/GaugeCard/VBox/LblGaugeCap") as Control
        if gauge_title != null:
                SpotRushTypography.apply_as(gauge_title, SpotRushTypography.Role.CARD_TITLE)
        SpotRushTypography.apply_as(lbl_gauge_pct, SpotRushTypography.Role.HUD_VALUE)
        SpotRushTypography.apply_as(lbl_gauge_sub, SpotRushTypography.Role.BODY)

        var stat_grid := get_node_or_null("SafeArea/VBoxMain/MidRow/StatGrid") as GridContainer
        if stat_grid != null:
                for tile in stat_grid.get_children():
                        var title := tile.get_node_or_null("Col/Cap") as Control
                        if title != null:
                                SpotRushTypography.apply_as(title, SpotRushTypography.Role.STAT_LABEL)

        var chart_title := get_node_or_null("SafeArea/VBoxMain/ChartCard/VBox/ChartHeader/LblChartTitle") as Control
        if chart_title != null:
                SpotRushTypography.apply_as(chart_title, SpotRushTypography.Role.CARD_TITLE)
        SpotRushTypography.apply_as(lbl_best_round, SpotRushTypography.Role.BODY_STRONG)

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
        var best_line := ("Best: Round %d  +%s" % [best_idx + 1, Records.format(best_score)]) if best_idx >= 0 else ""
        if best_idx >= 0 and best_score > 0 and not is_multiplayer and Records.submit_round(best_score):
                best_line += "  -  NEW BEST ROUND!"
        var grade_counts: Dictionary = my_stats.get("grade_counts", {})
        var s_ranks: int = int(grade_counts.get("S", 0))
        if s_ranks > 0:
                best_line += "  -  %d x S-RANK" % s_ranks
        lbl_best_round.text = best_line
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
        var cards: Array = [hero_card, get_node("SafeArea/VBoxMain/MidRow"), get_node("SafeArea/VBoxMain/ChartCard"), get_node("SafeArea/VBoxMain/ActionsContainer")]
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

## Repurpose the rematch key as a copy key: the caption swaps to an engraved
## slate style, exactly like the daily's share key.
func _rematch_as_share(text: String) -> void:
        for k in btn_rematch.get_children():
                if k is NeuText:
                        var nt := k as NeuText
                        nt.text = text
                        nt.color = NeuKit.SLATE
                        nt.look = 0
                        break

func _share_challenge_result() -> void:
        DisplayServer.clipboard_set(Records.challenge_result_share_text(
                        _final_score, _challenge_correct, _challenge_rounds,
                        GameManager.challenge_code_value))
        Feel.sfx("pop")
        for k in btn_rematch.get_children():
                if k is NeuText:
                        (k as NeuText).text = "COPIED!"
                        break
        get_tree().create_timer(1.2).timeout.connect(func():
                if is_instance_valid(btn_rematch) and btn_rematch.is_inside_tree():
                        for k in btn_rematch.get_children():
                                if k is NeuText:
                                        (k as NeuText).text = "COPY RESULT"
                                        break)

func _share_daily_result() -> void:
        DisplayServer.clipboard_set(Records.daily_share_text())
        Feel.sfx("pop")
        for k in btn_rematch.get_children():
                if k is NeuText:
                        (k as NeuText).text = "COPIED!"
                        break
        get_tree().create_timer(1.2).timeout.connect(func():
                if is_instance_valid(btn_rematch) and btn_rematch.is_inside_tree():
                        for k in btn_rematch.get_children():
                                if k is NeuText:
                                        (k as NeuText).text = "SHARE RESULT"
                                        break)

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
