extends Control

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Records = preload("res://scripts/core/Records.gd")

# --- PATCH A ---
const NeuFocusFX = preload("res://scripts/ui/NeuFocusFX.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
# ---------------

@onready var lbl_round: NeuText = %LblRound
@onready var lbl_score_p1: NeuText = %LblScoreP1
@onready var lbl_score_p2: NeuText = %LblScoreP2
@onready var timer_dial: Control = %TimerDial
@onready var round_pips: Control = %RoundPips
@onready var cap_score: NeuText = %CapScore
@onready var burst_layer: Control = %BurstLayer
@onready var challenge_view: Control = %ChallengeView

# Optional HUD enhancement elements
@onready var lbl_timer: NeuText = (%LblTimer if has_node("%LblTimer") else null)
@onready var lbl_streak: Label = (%LblStreak if has_node("%LblStreak") else null)

# Feedback and countdown overlays
@onready var countdown_overlay: PanelContainer = %CountdownOverlay
@onready var lbl_countdown: NeuText = %LblCountdown
@onready var lbl_countdown_sub: NeuText = %LblCountdownSub
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var lbl_feedback: NeuText = %LblFeedback
@onready var lbl_feedback_detail: NeuText = %LblFeedbackDetail
@onready var lbl_points: NeuText = %LblPoints
@onready var feedback_badge: Control = %FeedbackBadge
@onready var countdown_scrim: ColorRect = %CountdownScrim

var is_multiplayer: bool = false
var displayed_score: float = 0.0
var score_tween: Tween = null
var feedback_tween: Tween = null
var countdown_tween: Tween = null
var _feedback_correct_style: StyleBox
var _feedback_wrong_style: StyleBox
var _countdown_style: NeuStyle
var _countdown_press_tween: Tween = null
var _timer_visual_state: String = ""
var _last_tick_second: int = -1
# Screen-entrance rise tween (played after the wipe reveals the new scene).
var _entrance_tween: Tween = null
# Original countdown overlay offsets, captured in _ready so the slide-in
# animation always returns to the same resting position even if a previous
# tween was interrupted mid-flight.
var _countdown_base_ot: float = -120.0
var _countdown_base_ob: float = 120.0
# SafeArea resting offsets + entrance priming state for the screen rise.
var _safe_base_ot: float = 0.0
var _safe_base_ob: float = 0.0
var _entrance_primed: bool = false
# Round index already dealt behind the wipe (skips the round-start reload/rise).
var _prepared_round_index: int = -1

# --- PATCH B ---
var fx: NeuFocusFX
# ---------------

var _prev_combo_mult: int = 1
# Difficulty band of the previous round, so adaptive band changes between
# rounds can be announced (the engine's moves made audible + visible).
var _prev_round_difficulty: int = -1
var _countdown_sub_base_color: Color = Color.WHITE

func _ready() -> void:
		SpotRushSkin.apply_screen(self, "game")
		BackNav.register(self)
		_polish_hud_surfaces()

		# --- PATCH C ---
		# Additive FX layer above everything: answer edge-washes, round spotlight, countdown halo.
		fx = NeuFocusFX.new()
		fx.name = "FocusFX"
		add_child(fx)
		# ---------------

		# Allocate result surfaces once rather than on every answer.
		_feedback_correct_style = _make_feedback_card(_feedback_color(true))
		_feedback_wrong_style = _make_feedback_card(_feedback_color(false))
		_countdown_style = NeuKit.accent(NeuKit.COBALT, 40.0, 12.0, 28.0)
		_countdown_style.content_margin_left = 36.0
		_countdown_style.content_margin_right = 36.0
		_countdown_style.content_margin_top = 26.0
		_countdown_style.content_margin_bottom = 26.0
		countdown_overlay.add_theme_stylebox_override("panel", _countdown_style)
		_set_timer_visual("calm")
		GameManager.ui_countdown_started.connect(_on_countdown_started)
		GameManager.ui_round_started.connect(_on_round_started)
		GameManager.ui_time_tick.connect(_on_time_tick)
		GameManager.ui_answer_feedback.connect(_on_answer_feedback)
		GameManager.ui_round_ended.connect(_on_round_ended)
		GameManager.ui_match_ended.connect(_on_match_ended)
		SceneRouter.transition_started.connect(_on_scene_transition_started)
		
		challenge_view.option_selected.connect(_on_player_choice)
		
		is_multiplayer = (GameManager.current_game_mode != GameConfig.GameMode.SINGLE_PLAYER)
		lbl_score_p2.visible = is_multiplayer
		cap_score.text = "YOU" if is_multiplayer else "SCORE"
		round_pips.start(GameManager.match_controller.total_rounds)
		
		if lbl_streak != null:
				lbl_streak.visible = true
				if lbl_streak.get_parent() is Control:
						(lbl_streak.get_parent() as Control).visible = false
		
		feedback_panel.visible = false
		countdown_overlay.visible = false
		countdown_scrim.visible = false
		# Capture the countdown overlay's resting offsets so the slide-in animation
		# always returns to the same position even if a previous tween was killed.
		_countdown_base_ot = countdown_overlay.offset_top
		_countdown_base_ob = countdown_overlay.offset_bottom
		_countdown_sub_base_color = lbl_countdown_sub.color
		# Capture SafeArea's resting offsets so the entrance rise always returns the
		# content area to the same position.
		var safe_ref := get_node_or_null("SafeArea") as Control
		if safe_ref != null:
				NeuSafe.fit(safe_ref) # real OS insets first, so the animation base includes them
				_safe_base_ot = safe_ref.offset_top
				_safe_base_ob = safe_ref.offset_bottom
		
		# Start a queued Solo Play match only after the GameScreen is ready and all
		# UI signals are connected. This preserves the opening countdown and keeps the
		# first challenge's staggered token entrance visible instead of skipping it.
		var pending_solo_rounds: int = GameManager.consume_pending_single_player_start()
		if pending_solo_rounds >= 0:
				# Let containers finish their first layout before animating the countdown card.
				call_deferred("_begin_queued_solo_presentation", pending_solo_rounds)
		else:
				var pending_host_rounds: int = GameManager.consume_pending_multiplayer_host_start()
				if pending_host_rounds >= 0:
						# Multiplayer host mirror of the solo queue: prepare the match (which
						# also tells the friend's phone to load the arena) while the curtain is
						# still closed, then run the countdown only once everything is visible.
						call_deferred("_begin_queued_host_presentation", pending_host_rounds)
				elif GameManager.match_controller.current_state == MatchController.MatchState.COUNTDOWN:
						# Recover a countdown signal that may have arrived before this scene existed
						# (for example, when entering from another already-started match flow).
						_on_countdown_started(
								GameManager.match_controller.current_round_index + 1,
								GameManager.match_controller.total_rounds
						)
				elif GameManager.match_controller.current_challenge != null:
						# If a match is already active upon scene load, display its current round.
						_on_round_started(
								GameManager.match_controller.current_round_index + 1,
								GameManager.match_controller.current_challenge,
								GameManager.match_controller.round_duration
						)


func _polish_hud_surfaces() -> void:
		# Keep the status cards present but visually subordinate to the challenge.
		for path in [
				"SafeArea/VBoxMain/HUD/TopRow/RoundChip",
				"SafeArea/VBoxMain/HUD/TopRow/ScoreChip"
		]:
				var chip := get_node_or_null(path) as PanelContainer
				if chip == null:
						continue
				var style := chip.get_theme_stylebox("panel") as NeuStyle
				if style == null:
						continue
				style.depth = -0.58
				style.gradient = 0.30
				style.light = Color(1.0, 1.0, 1.0, 0.44)
				style.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.36)
				style.emit_changed()

func _begin_queued_solo_presentation(rounds: int) -> void:
		# While the spotlight curtain is still closed: build the match state, deal
		# the first challenge and park the screen items below their rest position,
		# so the wipe opens straight onto the finished round - no placeholder flash.
		GameManager.prepare_single_player_match(rounds)
		_prepare_first_round_display()
		_prime_screen_entrance()
		# Hold until the curtain is completely open, rise the items in smoothly,
		# and only then start the countdown (GET READY popup -> SPOT! -> timer).
		await SceneRouter.wait_until_idle()
		if not is_inside_tree():
				return
		await _play_screen_entrance()
		if not is_inside_tree():
				return
		GameManager.start_prepared_match()

## Multiplayer host twin of the solo queued start (see _begin_queued_solo_presentation).
func _begin_queued_host_presentation(rounds: int) -> void:
		GameManager.prepare_multiplayer_host_match(rounds)
		_prepare_first_round_display()
		_prime_screen_entrance()
		await SceneRouter.wait_until_idle()
		if not is_inside_tree():
				return
		await _play_screen_entrance()
		if not is_inside_tree():
				return
		GameManager.start_prepared_match()

## Populate the HUD and deal the first challenge while the transition curtain is
## still closed, so the reveal never shows the placeholder instruction screen.
func _prepare_first_round_display() -> void:
		var mc := GameManager.match_controller
		lbl_round.text = "1 / %d" % mc.total_rounds
		round_pips.set_current(0, mc.total_rounds)
		countdown_overlay.visible = false
		countdown_scrim.visible = false
		feedback_panel.visible = false
		if mc.current_challenge != null:
				challenge_view.load_challenge(mc.current_challenge, false)
				challenge_view.lock_input()
		if lbl_timer != null:
				lbl_timer.text = "--"
				lbl_timer.modulate = Color.WHITE
		timer_dial.set_time(1.0, 1.0)
		_set_timer_visual("calm")
		_prepared_round_index = 0

## Park the screen items just below their rest position and transparent, while
## the curtain is still closed, so the entrance rises them in without a flash.
func _prime_screen_entrance() -> void:
		if Feel.reduced():
				return
		var safe_area := get_node_or_null("SafeArea") as Control
		var hud := get_node_or_null("SafeArea/VBoxMain/HUD") as Control
		if safe_area != null:
				safe_area.offset_top = _safe_base_ot + 36.0
				safe_area.offset_bottom = _safe_base_ob + 36.0
		if hud != null:
				hud.modulate.a = 0.0
		if challenge_view != null:
				challenge_view.modulate.a = 0.0
		_entrance_primed = true

## Screen items rise up smoothly: the content area translates up from below
## while the HUD and challenge view fade in with a slight stagger. The hidden
## state was primed behind the curtain, so this is pure motion - no content
## swap, no flash. Reduced Motion skips the rise entirely.
func _play_screen_entrance() -> void:
		if Feel.reduced():
				await get_tree().process_frame
				return
		var safe_area := get_node_or_null("SafeArea") as Control
		var hud := get_node_or_null("SafeArea/VBoxMain/HUD") as Control
		var cv := challenge_view
		if _entrance_tween != null and _entrance_tween.is_valid():
				_entrance_tween.kill()
		_entrance_tween = create_tween()
		_entrance_tween.set_parallel(true)
		if safe_area != null:
				_entrance_tween.tween_property(safe_area, "offset_top", _safe_base_ot, 0.46) \
						.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_entrance_tween.tween_property(safe_area, "offset_bottom", _safe_base_ob, 0.46) \
						.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if hud != null:
				_entrance_tween.tween_property(hud, "modulate:a", 1.0, 0.30) \
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.04)
		if cv != null:
				_entrance_tween.tween_property(cv, "modulate:a", 1.0, 0.34) \
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.12)
		await _entrance_tween.finished
		_entrance_primed = false

func _input(event: InputEvent) -> void:
		# Tap anywhere during feedback skips directly to the next challenge
		if feedback_panel != null and feedback_panel.visible:
				if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
						# Consume the skip tap so it cannot leak into the next round's answer controls.
						get_viewport().set_input_as_handled()
						GameManager.skip_feedback()

func _on_countdown_started(round_num: int, total_rounds: int) -> void:
		# Network/host flows can also arrive during a scene reveal. Hold their first
		# popup too, rather than letting the wipe rim cut through the card.
		await SceneRouter.wait_until_idle()
		if not is_inside_tree():
				return
		_kill_tweens()
		
		lbl_round.text = "%d / %d" % [round_num, total_rounds]
		round_pips.set_current(round_num - 1, total_rounds)
		countdown_overlay.visible = true
		countdown_scrim.visible = true
		countdown_scrim.modulate.a = 0.0
		feedback_panel.visible = false
		challenge_view.lock_input()

		# Solo/host challenges are prepared before countdown. Render the first level
		# behind GET READY instead of showing an empty playfield; keep it locked and
		# suppress its entrance until the countdown ends.
		if GameManager.current_game_mode in [GameConfig.GameMode.SINGLE_PLAYER, GameConfig.GameMode.MULTIPLAYER_HOST] \
				and GameManager.match_controller.current_challenge != null:
				# The opening round was already dealt behind the wipe; only later
				# rounds need a (static) reload here.
				if _prepared_round_index != GameManager.match_controller.current_round_index:
						challenge_view.load_challenge(GameManager.match_controller.current_challenge, false)
				challenge_view.lock_input()
		
		if lbl_timer != null:
				lbl_timer.text = "--"
				lbl_timer.modulate = Color.WHITE
		timer_dial.set_time(1.0, 1.0)
		_set_timer_visual("calm")
				
		# GET READY! floats on a raised cobalt card; SPOT! presses the card in and lights up.
		Feel.sfx("whoosh")
		# Scoring 2.0: name the upcoming difficulty band; when the adaptive engine
		# moves it between rounds, let the player hear (and see) the shift.
		var upcoming_difficulty: int = -1
		if GameManager.match_controller.current_challenge != null:
				upcoming_difficulty = clampi(GameManager.match_controller.current_challenge.difficulty, 1, 4)
		lbl_countdown_sub.color = _countdown_sub_base_color
		if upcoming_difficulty > 0:
				lbl_countdown_sub.text = "ROUND %d OF %d  -  %s" % [round_num, total_rounds, GameConfig.band_name(upcoming_difficulty)]
				if _prev_round_difficulty > 0 and upcoming_difficulty != _prev_round_difficulty:
						var band_up: bool = upcoming_difficulty > _prev_round_difficulty
						lbl_countdown_sub.color = NeuKit.CANARY if band_up else NeuKit.MINT
						Feel.band_change(band_up)
				_prev_round_difficulty = upcoming_difficulty
		else:
				lbl_countdown_sub.text = "ROUND %d OF %d" % [round_num, total_rounds]
		lbl_countdown.text = "GET READY!"
		lbl_countdown.font_size = 62
		lbl_countdown.color = Color.WHITE
		_countdown_style.depth = 1.0
		# Slide+crossfade entrance: the card starts just below its resting position
		# and fades in smoothly, then holds for the remainder of the GET READY beat.
		countdown_overlay.scale = Vector2.ONE
		countdown_overlay.offset_top = _countdown_base_ot + 28.0
		countdown_overlay.offset_bottom = _countdown_base_ob + 28.0
		countdown_overlay.modulate.a = 0.0
		
		countdown_tween = create_tween()
		countdown_tween.set_parallel(true)
		countdown_tween.tween_property(countdown_scrim, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		countdown_tween.tween_property(countdown_overlay, "offset_top", _countdown_base_ot, 0.26) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		countdown_tween.tween_property(countdown_overlay, "offset_bottom", _countdown_base_ob, 0.26) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		countdown_tween.tween_property(countdown_overlay, "modulate:a", 1.0, 0.22) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		countdown_tween.chain().tween_interval(maxf(0.14, (GameConfig.COUNTDOWN_DURATION * 0.5) - 0.26))
		countdown_tween.tween_callback(func():
				lbl_countdown.text = "SPOT!"
				lbl_countdown.font_size = 84
				lbl_countdown.color = NeuKit.CANARY
				Feel.sfx("spot")
				Feel.haptic("medium")
				_press_countdown_card()
		)

		# --- PATCH D ---
		# A spotlight closes in on the card while GET READY runs.
		# Use the card's final resting rect (not the slid-down start position).
		# The opening round skips the halo ring: the wipe's spot-mark already gave
		# the reveal its spotlight moment, and a second ring read as a duplicate orb.
		if fx != null and _prepared_round_index < 0:
				var halo_rect := countdown_overlay.get_global_rect()
				halo_rect.position.y -= 28.0
				fx.halo(halo_rect, GameConfig.COUNTDOWN_DURATION * 0.5)
		# ---------------

func _press_countdown_card() -> void:
		if _countdown_press_tween != null and _countdown_press_tween.is_valid():
				_countdown_press_tween.kill()
		_countdown_press_tween = create_tween()
		_countdown_press_tween.tween_property(_countdown_style, "depth", -0.9, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_countdown_press_tween.tween_property(_countdown_style, "depth", 0.55, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
		# Playback is requested once the first round is actually live. On the normal
		# menu path the gameplay loop has already been synthesized during idle time.
		Music.play_game()
		_kill_tweens()
		_last_tick_second = -1
		
		countdown_overlay.visible = false
		# Restore the overlay's resting offsets/alpha/scale so the next countdown
		# starts from a clean state even if the previous tween was interrupted.
		countdown_overlay.offset_top = _countdown_base_ot
		countdown_overlay.offset_bottom = _countdown_base_ob
		countdown_overlay.modulate.a = 1.0
		countdown_overlay.scale = Vector2.ONE
		countdown_scrim.visible = false
		countdown_scrim.modulate.a = 1.0
		feedback_panel.visible = false
		lbl_round.text = "%d / %d" % [round_num, GameManager.match_controller.total_rounds]
		round_pips.set_current(round_num - 1, GameManager.match_controller.total_rounds)
		
		timer_dial.set_time(duration, duration)
		_timer_visual_state = ""
		_set_timer_visual("calm")
		
		if lbl_timer != null:
				lbl_timer.text = "%.1f" % duration
				lbl_timer.modulate = Color.WHITE
				
		if _prepared_round_index == round_num - 1:
				# This round was already dealt behind the wipe and rose in with the screen
				# entrance - hand control back without reloading, re-rising or re-sweeping.
				_prepared_round_index = -1
				challenge_view.unlock_input()
		else:
				challenge_view.load_challenge(challenge)
						# ChallengeCanvas already animates token entrances. Avoid a second
				# full-screen expanding ring here: its 96-segment redraw is costly
				# on mobile exactly when the challenge first appears.


func _on_time_tick(remaining: float, total: float) -> void:
		timer_dial.set_time(remaining, total)
		if lbl_timer != null:
				lbl_timer.text = "%.1f" % remaining
				
		# Last three seconds: a clock-like tick each second that rises in pitch, plus a knob bump.
		if remaining > 0.0 and remaining <= 3.0:
				var whole_second := int(ceil(remaining))
				if whole_second != _last_tick_second:
						_last_tick_second = whole_second
						Feel.sfx("tick", 1.0 + float(3 - whole_second) * 0.14)
						Feel.haptic("light")
						timer_dial.bump()
		
		var ratio = remaining / maxf(total, 0.001)
		if ratio > 0.5:
				_set_timer_visual("calm")
		elif ratio > 0.25:
				_set_timer_visual("warn")
		else:
				_set_timer_visual("urgent")

func _set_timer_visual(state: String) -> void:
		# The dial owns the arc colour; only touch the label when the urgency band changes.
		timer_dial.set_state(state)
		if _timer_visual_state == state:
				return
		_timer_visual_state = state
		if lbl_timer != null:
				match state:
						"warn":
								lbl_timer.color = Color("B07A0A")
						"urgent":
								lbl_timer.color = Color("D63A4A")
						_:
								lbl_timer.color = NeuKit.COBALT
				lbl_timer.modulate = Color.WHITE

## Slightly deeper than the token colours so white lettering keeps strong contrast.
func _feedback_color(correct: bool) -> Color:
		return Color("26B07C") if correct else Color("EE4458")

## Sound + haptics + motion for an answer. Correct answers rise in pitch with the streak.
func _play_answer_feel(is_correct: bool, score_delta: int, streak: int, grade: String = "") -> void:
		# --- PATCH F ---
		if fx != null:
				fx.edge_flash(NeuKit.MINT if is_correct else NeuKit.CORAL, 1.0 if is_correct else 0.85)
		# ---------------

		if is_correct:
				Feel.sfx("correct", 1.0 + 0.06 * float(clampi(streak - 1, 0, 6)))
				Feel.haptic("success")
				var origin := burst_layer.get_global_transform().affine_inverse() * (feedback_panel.global_position + Vector2(feedback_panel.size.x * 0.5, 8.0))
				var palette: Array = [NeuKit.MINT, NeuKit.COBALT, NeuKit.CANARY, NeuKit.LAVENDER, NeuKit.CORAL]
				burst_layer.burst(origin, palette, 14 + 3 * mini(streak, 6), 1.0 + 0.08 * float(mini(streak, 5)))
		else:
				Feel.sfx("wrong")
				Feel.haptic("error")
				_shake_field()
		get_tree().create_timer(0.12).timeout.connect(func(): Feel.sfx("pip", 1.25 if is_correct else 0.8))
		_spawn_score_float(score_delta, is_correct, grade)

## The field jolts sideways and settles, like something knocked it.
func _shake_field() -> void:
		if Feel.reduced():
				return
		var base_x := challenge_view.position.x
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		for dx in [14.0, -12.0, 9.0, -6.0, 3.0, 0.0]:
				tw.tween_property(challenge_view, "position:x", base_x + dx, 0.045)

## The points number detaches from the feedback card and flies into the score readout, so
## the +120 you just earned visibly becomes part of the total.
func _spawn_score_float(score_delta: int, is_correct: bool, grade: String = "") -> void:
		if Feel.reduced() or score_delta == 0:
				return
		# The feedback card is shown this same frame; wait for it to be laid out so we read
		# the points readout's real position (otherwise the number starts in the wrong place).
		await get_tree().process_frame
		await get_tree().process_frame
		var label := NeuText.new()
		label.text = ("+%s" % Records.format(score_delta)) if score_delta > 0 else Records.format(score_delta)
		label.font_size = 54
		label.look = 3
		label.accent_base = NeuKit.CANARY if grade == "S" else _feedback_color(is_correct)
		label.color = Color.WHITE
		# Size via offsets (equal anchors): setting `size` directly on a control that
		# has not completed _ready yet trips Godot's "non-equal opposite anchors"
		# warning path whenever anchors drift from the equal default. Offsets define
		# the rect deterministically and never warn.
		label.offset_right = 220.0
		label.offset_bottom = 74.0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		var from_rect := lbl_points.get_global_rect()
		var to_rect := lbl_score_p1.get_global_rect()
		label.global_position = from_rect.get_center() - label.size * 0.5
		label.pivot_offset = label.size * 0.5
		var target := to_rect.get_center() - label.size * 0.5
		var tw := create_tween().set_parallel(true)
		tw.tween_property(label, "global_position", target, 0.62).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(label, "scale", Vector2(0.55, 0.55), 0.62).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(label, "modulate:a", 0.0, 0.18).set_delay(0.62)
		tw.chain().tween_callback(label.queue_free)

func _make_feedback_card(color: Color) -> StyleBox:
		var card := NeuKit.accent(color, 30.0, 10.0, 24.0)
		card.content_margin_left = 26.0
		card.content_margin_right = 26.0
		card.content_margin_top = 18.0
		card.content_margin_bottom = 18.0
		return card

## Scoring 2.0 score-math line for correct answers, e.g.
##   "S - BASE 1,250 + SPEED 318 + BOLT 150  x2"
## Teaches the system by showing exactly how the points were built. In solo
## play it also calls out a new all-time best round as it happens.
func _score_math_line(breakdown: Dictionary, details: String) -> String:
		if breakdown.is_empty() or str(breakdown.get("kind", "")) != "correct":
				return details
		var line: String = ""
		var grade_str: String = str(breakdown.get("grade", ""))
		if grade_str != "":
				line = grade_str + " - "
		line += "BASE %s" % Records.format(int(breakdown.get("base", 0)))
		line += " + SPEED %d" % int(breakdown.get("speed_bonus", 0))
		var bolt: int = int(breakdown.get("lightning_bonus", 0))
		if bolt > 0:
				line += " + BOLT %d" % bolt
		var mult: int = int(breakdown.get("mult", 1))
		if mult >= 2:
				line += "  x%d" % mult
		if not is_multiplayer:
				var total: int = int(breakdown.get("total", 0))
				if total > 0 and total > Records.best_round():
						line += "  -  NEW BEST ROUND!"
		return line

func _on_player_choice(choice: Variant) -> void:
		GameManager.submit_answer(choice)

func _on_answer_feedback(player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
		feedback_panel.visible = true
		
		var local_id = NetworkSession.get_local_id() if is_multiplayer else 1
		var stats = GameManager.match_controller.score_manager.get_player_stats(local_id)
		var streak = stats.get("current_streak", 0)
		# Scoring 2.0: the event player's breakdown (host computes it, the client
		# mirrors it from the packet) drives the grade, the score-math line and
		# the fly-up. Event stats (not local) so duel cards stay per-player.
		var event_stats: Dictionary = GameManager.match_controller.score_manager.get_player_stats(player_id)
		var event_streak: int = event_stats.get("current_streak", 0)
		var event_mult: int = ScoreManager.combo_multiplier(event_streak)
		var breakdown: Dictionary = GameManager.match_controller.score_manager.get_last_breakdown(player_id)
		var grade: String = str(breakdown.get("grade", "")) if is_correct else ""
		
		# Update HUD combo meter (tier multiplier, not the raw streak count)
		var mult := ScoreManager.combo_multiplier(streak)
		if lbl_streak != null:
				var streak_chip: Control = lbl_streak.get_parent() as Control
				if streak >= 2:
						lbl_streak.visible = true
						if streak_chip != null:
								streak_chip.visible = true
						if mult >= 2:
								lbl_streak.text = "x%d" % mult
						else:
								lbl_streak.text = "%d TO x2" % ScoreManager.tier_gap(streak)
						lbl_streak.add_theme_color_override("font_color",
								Color(0.67, 0.42, 0.08) if mult <= 2
								else (Color(0.84, 0.23, 0.29) if mult == 3
								else Color(0.90, 0.11, 0.16)))
						var pulse := 1.12 + 0.05 * float(mult)
						var tw_streak = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
						tw_streak.tween_property(streak_chip if streak_chip != null else lbl_streak, "scale", Vector2(pulse, pulse), 0.08)
						tw_streak.tween_property(streak_chip if streak_chip != null else lbl_streak, "scale", Vector2.ONE, 0.12)
				else:
						if streak_chip != null:
								streak_chip.visible = false
						lbl_streak.visible = true

		# Tier-up fanfare for the local player; a miss resets the multiplier bookkeeping.
		if player_id == local_id:
				if is_correct:
						if mult > _prev_combo_mult and mult >= 2:
								Feel.combo_jingle(mult)
								Feel.haptic("success")
						_prev_combo_mult = mult
				else:
						_prev_combo_mult = 1
		
		var title := ""
		var detail := details
		var accent: Color = _feedback_color(is_correct)
		feedback_panel.modulate = Color.WHITE
		feedback_panel.add_theme_stylebox_override("panel", _feedback_correct_style if is_correct else _feedback_wrong_style)
		if is_correct:
				if "Withheld" in details:
						title = "PERFECT RESTRAINT!"
				elif grade == "S" and event_mult >= 2:
						title = "S RANK x%d!" % event_mult
				elif grade == "S":
						title = "S RANK!"
				elif event_mult >= 2:
						title = "COMBO x%d!" % event_mult
				elif event_streak == 2:
						title = "ONE MORE TO x2!"
				else:
						title = "CORRECT!"
				detail = _score_math_line(breakdown, details)
		else:
				title = "IMPULSE FAULT!" if "Don't Tap" in details else "MISSED!"
				# Near-miss hook: losing a streak that was 1-2 answers from the
				# next tier stings just enough to try again (loss aversion).
				var broke: int = int(breakdown.get("broke", stats.get("last_break_streak", 0)))
				if player_id == local_id and broke >= 2:
						var gap: int = ScoreManager.tier_gap(broke)
						if gap == 1 or gap == 2:
								detail = "%s  SO CLOSE - %d away from x%d!" % [details, gap, ScoreManager.combo_multiplier(broke) + 1]
		
		lbl_feedback.text = title
		lbl_feedback.accent_base = accent
		lbl_feedback_detail.text = detail
		lbl_feedback_detail.accent_base = accent
		lbl_feedback_detail.visible = detail != ""
		lbl_points.text = ("+%s" % Records.format(score_delta)) if score_delta >= 0 else Records.format(score_delta)
		lbl_points.accent_base = accent
		var s_rank: bool = is_correct and grade == "S"
		feedback_badge.set("glyph", "bolt" if s_rank else ("check" if is_correct else "cross"))
		feedback_badge.set("glyph_color", Color.WHITE)
		feedback_badge.set("socket_surface", NeuKit.CANARY if s_rank else accent)
		feedback_badge.queue_redraw()
		
		if player_id == local_id:
				round_pips.mark(GameManager.match_controller.current_round_index, is_correct)
				if challenge_view.challenge_canvas != null:
						challenge_view.challenge_canvas.show_result(is_correct)
				_play_answer_feel(is_correct, score_delta, streak, grade)
		
		# Tactile bounce entrance animation
		feedback_panel.pivot_offset = feedback_panel.size * 0.5
		feedback_panel.scale = Vector2(0.9, 0.9)
		feedback_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		feedback_tween.tween_property(feedback_panel, "scale", Vector2.ONE, 0.18)
		
		# Authoritative score update with smooth count-up animation
		var my_score = GameManager.match_controller.score_manager.get_player_score(local_id)
		_animate_score_to(my_score)
		
		if is_multiplayer:
				var opp_id = -1
				for pid in GameManager.match_controller.player_ids:
						if pid != local_id:
								opp_id = pid
								break
				var opp_score = GameManager.match_controller.score_manager.get_player_score(opp_id) if opp_id != -1 else 0
				lbl_score_p2.text = "OPPONENT: %d" % opp_score
				
				# --- PATCH H ---
				if fx != null:
						fx.pop(lbl_score_p2, 1.1)
				# ---------------

func _animate_score_to(target_score: int) -> void:
		if score_tween != null and score_tween.is_valid():
				score_tween.kill()
				
		var start_val = displayed_score
		score_tween = create_tween()
		score_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		score_tween.tween_method(
				func(val: float):
						displayed_score = val
						lbl_score_p1.text = str(int(round(val))),
				start_val,
				float(target_score),
				0.25
		)
		
		# --- PATCH G ---
		score_tween.tween_callback(func():
				displayed_score = float(target_score)
				lbl_score_p1.text = str(target_score)
				if fx != null:
						fx.pop(lbl_score_p1, 1.16)
		)
		# ---------------

func _kill_tweens() -> void:
		if countdown_tween != null and countdown_tween.is_valid():
				countdown_tween.kill()
		if feedback_tween != null and feedback_tween.is_valid():
				feedback_tween.kill()
		if _countdown_press_tween != null and _countdown_press_tween.is_valid():
				_countdown_press_tween.kill()
		if _entrance_tween != null and _entrance_tween.is_valid():
				_entrance_tween.kill()

func _on_round_ended(_round_num: int, _scores: Dictionary) -> void:
		challenge_view.lock_input()

func _on_scene_transition_started() -> void:
		# Clear every transient layer before the first visible wipe frame.
		_kill_tweens()
		countdown_overlay.visible = false
		countdown_overlay.offset_top = _countdown_base_ot
		countdown_overlay.offset_bottom = _countdown_base_ob
		countdown_overlay.modulate.a = 1.0
		countdown_overlay.scale = Vector2.ONE
		countdown_scrim.visible = false
		countdown_scrim.modulate.a = 1.0
		feedback_panel.visible = false

func _on_match_ended(_results: Dictionary) -> void:
		_kill_tweens()
		if score_tween != null and score_tween.is_valid():
				score_tween.kill()
		SceneRouter.goto_results()

# --- HARDWARE BACK (v19) ------------------------------------------------------------

func _exit_tree() -> void:
		BackNav.unregister(self)

## Android back / desktop Escape. Leaving a live run costs its points (and a
## live duel), so the question is asked before anything is thrown away.
func handle_back() -> bool:
		var mc := GameManager.match_controller
		if mc.current_state == MatchController.MatchState.IDLE:
				# Match not dealt yet (or already over): nothing to protect.
				_leave_match()
				return true
		var progress := "ROUND %d OF %d" % [mc.current_round_index + 1, mc.total_rounds]
		if is_multiplayer:
				NeuDialog.ask("LEAVE THE DUEL?",
								"%s - the duel ends on your phone; your rival keeps the score." % progress,
								"LEAVE", "STAY", _leave_match)
		else:
				NeuDialog.ask("QUIT THIS RUN?",
								"%s - the points from this run won't be saved." % progress,
								"QUIT", "KEEP PLAYING", _leave_match)
		return true

## One door out of a live match: freeze the run, drop any duel connection,
## back to the menu. Records only ever see finished runs.
func _leave_match() -> void:
		if SceneRouter.is_transitioning:
				return
		GameManager.abandon_match()
		SceneRouter.goto_main_menu()
