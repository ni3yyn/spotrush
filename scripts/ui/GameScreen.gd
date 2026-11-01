extends Control

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const Records = preload("res://scripts/core/Records.gd")
const ChallengeFactoryScript = preload("res://scripts/challenges/ChallengeFactory.gd")
const RuleBookScript = preload("res://scripts/challenges/RuleBook.gd")
const AnswerValidatorScript = preload("res://scripts/game/AnswerValidator.gd")
const TutorialProgressScript = preload("res://scripts/tutorial/TutorialProgress.gd")
const PracticeCoachScript = preload("res://scripts/ui/PracticeCoach.gd")

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
@onready var safe_area: Control = get_node_or_null("SafeArea") as Control

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
# Invalidates any countdown coroutine that resumes after a newer round has started.
var _countdown_presentation_token: int = 0

# --- PATCH B ---
var fx: NeuFocusFX
# ---------------

var _prev_combo_mult: int = 1
# Difficulty band of the previous round, so adaptive band changes between
# rounds can be announced (the engine's moves made audible + visible).
var _prev_round_difficulty: int = -1
var _countdown_sub_base_color: Color = Color.WHITE
var _feedback_correct_depth: float = 1.0
var _feedback_wrong_depth: float = 1.0
var _practice_coach: PracticeCoach
var _inter_round_layer: CenterContainer
var _inter_round_label: NeuText
var _inter_round_tween: Tween = null
var _tutorial_practice_active: bool = false
var _tutorial_has_result: bool = false
var _tutorial_result: Dictionary = {}
var _tutorial_attempt_id: int = 0
var _tutorial_challenge: ChallengeDefinition = null
var _tutorial_skipped_families: Dictionary = {}
var _tutorial_interrupted: bool = false
const INTER_ROUND_INSTRUCTION_SECONDS: float = 1.5
const INTER_ROUND_INSTRUCTION_IN_SECONDS: float = 0.18
const INTER_ROUND_INSTRUCTION_OUT_SECONDS: float = 0.14

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

		_practice_coach = PracticeCoachScript.new()
		_practice_coach.name = "PracticeCoach"
		add_child(_practice_coach)
		_create_inter_round_instruction_layer()

		# Allocate result surfaces once rather than on every answer.
		_feedback_correct_style = _make_feedback_card(_feedback_color(true))
		_feedback_wrong_style = _make_feedback_card(_feedback_color(false))
		_feedback_correct_depth = (_feedback_correct_style as NeuStyle).depth
		_feedback_wrong_depth = (_feedback_wrong_style as NeuStyle).depth
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
		_countdown_presentation_token += 1
		var presentation_token: int = _countdown_presentation_token
		var live_challenge: ChallengeDefinition = GameManager.match_controller.current_challenge
		var needs_practice: bool = _should_show_first_time_practice(live_challenge)
		# Multiplayer instructions remain visible on the challenge itself. A
		# separate preview would cause countdown drift between the two devices.
		var needs_instruction_preview: bool = round_num > 1 \
						and GameManager.current_game_mode == GameConfig.GameMode.SINGLE_PLAYER
		if needs_practice or needs_instruction_preview:
				GameManager.pause_round_countdown()

		# Network/host flows can also arrive during a scene reveal. Hold their first
		# popup too, rather than letting the wipe rim cut through the card.
		await SceneRouter.wait_until_idle()
		if not is_inside_tree() or presentation_token != _countdown_presentation_token:
				return

		# Feedback leaves with the reverse of its entrance before the next screen state.
		await _animate_feedback_exit()
		if not is_inside_tree() or presentation_token != _countdown_presentation_token \
						or SceneRouter.is_transitioning:
				return
		if needs_practice and live_challenge != null:
				await _run_first_time_practice(live_challenge)
		if not is_inside_tree() or presentation_token != _countdown_presentation_token \
						or _tutorial_interrupted or SceneRouter.is_transitioning:
				return

		if needs_instruction_preview:
				var preview_line: String = GameManager.next_round_instruction
				if preview_line.is_empty() and live_challenge != null:
						preview_line = live_challenge.instruction
				await _show_inter_round_instruction(preview_line)
				if not is_inside_tree() or presentation_token != _countdown_presentation_token \
						or _tutorial_interrupted or SceneRouter.is_transitioning:
						return

		GameManager.resume_round_countdown()
		_kill_tweens()
		lbl_round.text = "%d / %d" % [round_num, total_rounds]
		round_pips.set_current(round_num - 1, total_rounds)
		countdown_overlay.visible = true
		countdown_scrim.visible = true
		countdown_scrim.modulate.a = 0.0
		feedback_panel.visible = false
		challenge_view.visible = true

		# Solo/host challenges are prepared before countdown. Render the first level
		# behind GET READY instead of showing an empty playfield; keep it locked and
		# suppress its entrance until the countdown ends.
		if GameManager.current_game_mode in [GameConfig.GameMode.SINGLE_PLAYER, GameConfig.GameMode.MULTIPLAYER_HOST] \
				and GameManager.match_controller.current_challenge != null:
				if _prepared_round_index != GameManager.match_controller.current_round_index:
						challenge_view.load_challenge(GameManager.match_controller.current_challenge, false)
				challenge_view.lock_input()

		if lbl_timer != null:
				lbl_timer.text = "--"
				lbl_timer.modulate = Color.WHITE
		timer_dial.set_time(1.0, 1.0)
		_set_timer_visual("calm")

		Feel.sfx("whoosh")
		var upcoming_difficulty: int = -1
		if GameManager.match_controller.current_challenge != null:
				upcoming_difficulty = clampi(GameManager.match_controller.current_challenge.difficulty, 1, 4)
		lbl_countdown_sub.visible = true
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
		lbl_countdown.autowrap = false
		lbl_countdown.custom_minimum_size = Vector2(0.0, 92.0)
		lbl_countdown.color = Color.WHITE
		_countdown_style.depth = 1.0
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

		if fx != null and _prepared_round_index < 0:
				var halo_rect := countdown_overlay.get_global_rect()
				halo_rect.position.y -= 28.0
				fx.halo(halo_rect, GameConfig.COUNTDOWN_DURATION * 0.5)

## First encounter of a family gets one unscored, low-pressure practice round.
## Deliberately limited to solo modes: duel timing remains fully authoritative.
func _should_show_first_time_practice(challenge: ChallengeDefinition) -> bool:
		if challenge == null or GameManager.current_game_mode != GameConfig.GameMode.SINGLE_PLAYER:
				return false
		if _tutorial_skipped_families.has(challenge.type):
				return false
		return not TutorialProgressScript.has_completed(challenge.type)

func _make_practice_challenge(family_type: String) -> ChallengeDefinition:
		var rng := RandomNumberGenerator.new()
		var run_seed: int = int(Time.get_ticks_usec() & 0x7FFFFFFF)
		rng.seed = run_seed
		var book: RuleBook = RuleBookScript.new(run_seed ^ 0x5A5A)
		var practice: ChallengeDefinition = null
		var attempts: int = 1
		if family_type == GameConfig.TYPE_DONT_TAP:
				attempts = 8 # Prefer a red-present example so restraint is physically practised.
		for _attempt in range(attempts):
				practice = ChallengeFactoryScript.build(rng, family_type, -1, 0.0, book, run_seed)
				if practice != null and (family_type != GameConfig.TYPE_DONT_TAP or bool(practice.correct_answer)):
						break
		if practice != null and practice.is_valid():
				if practice.input_mode == "withhold_response":
						practice.time_limit = 2.6
				return practice
		push_warning("Could not generate a valid practice challenge for %s" % family_type)
		return null

func _tutorial_explanation(challenge: ChallengeDefinition) -> String:
		match challenge.type:
				GameConfig.TYPE_ESTIMATION_COUNT:
						return "Look at the whole group, estimate its size, then choose the closest number. You do not need to count every dot."
				GameConfig.TYPE_COMPARISON_SIDES:
						return "Compare both trays and choose the side that matches the instruction: more or fewer dots."
				GameConfig.TYPE_COLOR_TARGET:
						return "Tap every circle in the requested colour, then press CONFIRM SELECTIONS. Leave every other colour untouched."
				GameConfig.TYPE_SHAPE_TARGET:
						return "Tap every requested shape, wherever it appears, then press CONFIRM SELECTIONS. Ignore all the other shapes."
				GameConfig.TYPE_DONT_TAP:
						return "Scan the whole field. If you see a red circle, do not tap. Only tap when the field has no red circle."
				GameConfig.TYPE_SIZE_ORDER:
						return "Tap every shape in the exact size order shown. The order of your taps is the answer."
				GameConfig.TYPE_COMBINED_CONDITIONAL:
						match challenge.rule:
								"conjunction_search":
										return "Tap only items matching BOTH attributes (colour AND shape), then press CONFIRM SELECTIONS. Ignore near-misses matching just one."
								"majority":
										return "Compare the quantities of the two named shapes, then choose YES or NO."
								"threshold":
										return "Estimate the number of dots in the named colour. Decide whether it meets the AT LEAST or AT MOST limit."
								_:
										return "Read the condition carefully, inspect the field, then choose the answer that satisfies it."
		return "Read the instruction, inspect the field, and make the required selection."

func _tutorial_family_title(challenge: ChallengeDefinition) -> String:
		match challenge.type:
				GameConfig.TYPE_ESTIMATION_COUNT: return "ALMOST RIGHT • ESTIMATION"
				GameConfig.TYPE_COMPARISON_SIDES: return "WHICH SIDE • COMPARISON"
				GameConfig.TYPE_COLOR_TARGET: return "TARGET RUSH • COLOR"
				GameConfig.TYPE_SHAPE_TARGET: return "SHAPE HUNTER • GEOMETRY"
				GameConfig.TYPE_DONT_TAP: return "DON'T TAP • INHIBITION"
				GameConfig.TYPE_COMBINED_CONDITIONAL: return "BRAIN TWIST • CONDITIONAL"
				GameConfig.TYPE_SIZE_ORDER: return "SIZE RUSH • ORDER"
				_: return challenge.type.to_upper()

func _run_first_time_practice(live_challenge: ChallengeDefinition) -> void:
		_tutorial_interrupted = false
		_tutorial_challenge = _make_practice_challenge(live_challenge.type)
		if _tutorial_challenge == null or _practice_coach == null:
				return
		var safe_was_visible: bool = safe_area.visible if safe_area != null else true
		if safe_area != null:
				safe_area.visible = false
		countdown_overlay.visible = false
		countdown_scrim.visible = false
		feedback_panel.visible = false
		var title: String = _tutorial_family_title(_tutorial_challenge)
		var message: String = "FIRST-TIME PRACTICE\n\n%s\n\n%s" % [
				_tutorial_challenge.instruction, _tutorial_explanation(_tutorial_challenge)]
		var begin_practice: bool = await _practice_coach.present(title, message, "PRACTICE NOW", "SKIP FOR NOW")
		if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
				return
		if begin_practice:
				if safe_area != null:
						safe_area.visible = safe_was_visible
				while is_inside_tree():
						_tutorial_result = {}
						_tutorial_has_result = false
						_tutorial_practice_active = true
						_tutorial_attempt_id += 1
						var attempt_id: int = _tutorial_attempt_id
						challenge_view.load_challenge(_tutorial_challenge)
						challenge_view.unlock_input()
						var result: Dictionary = await _run_tutorial_attempt(attempt_id)
						_tutorial_practice_active = false
						if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
								return
						challenge_view.lock_input()
						if bool(result.get("is_correct", false)):
								if safe_area != null:
										safe_area.visible = false
								var continue_to_round: bool = await _practice_coach.present(
										"YOU'VE GOT IT!",
										"That was a practice round, so no score or streak was changed. You're ready for the real challenge.",
										"CONTINUE",
										""
								)
								if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
										return
								if continue_to_round:
										TutorialProgressScript.mark_completed(live_challenge.type)
								else:
										_tutorial_skipped_families[live_challenge.type] = true
								break
						else:
								if safe_area != null:
										safe_area.visible = false
								var retry: bool = await _practice_coach.present(
										"NOT QUITE — TRY AGAIN",
										"%s\n\n%s" % [_tutorial_challenge.instruction, str(result.get("details", "Try the rule once more."))],
										"TRY AGAIN",
										"SKIP"
								)
								if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
										return
								if retry:
										if safe_area != null:
												safe_area.visible = safe_was_visible
										continue
								_tutorial_skipped_families[live_challenge.type] = true
								break
		else:
				_tutorial_skipped_families[live_challenge.type] = true
		_tutorial_practice_active = false
		_tutorial_has_result = false
		if safe_area != null:
				safe_area.visible = safe_was_visible
		if lbl_timer != null:
				lbl_timer.text = "--"
				lbl_timer.modulate = Color.WHITE
		timer_dial.set_time(1.0, 1.0)
		challenge_view.load_challenge(live_challenge, false)
		challenge_view.lock_input()
		_tutorial_challenge = null

func _run_tutorial_attempt(attempt_id: int) -> Dictionary:
		var total: float = _tutorial_challenge.time_limit
		var start_usec: int = Time.get_ticks_usec()
		while is_inside_tree() and _tutorial_practice_active and not _tutorial_has_result \
				and attempt_id == _tutorial_attempt_id:
				var elapsed: float = float(Time.get_ticks_usec() - start_usec) / 1000000.0
				var remaining: float = maxf(0.0, total - elapsed)
				timer_dial.set_time(remaining, total)
				if lbl_timer != null:
						lbl_timer.text = "%.1f" % remaining
				if remaining <= 0.0:
						_record_tutorial_submission(null, true)
						break
				await get_tree().process_frame
		return _tutorial_result

func _record_tutorial_submission(answer: Variant, is_timeout: bool) -> void:
		if not _tutorial_practice_active or _tutorial_has_result or _tutorial_challenge == null:
				return
		var elapsed: float = _tutorial_challenge.time_limit if is_timeout else 0.35
		_tutorial_result = AnswerValidatorScript.validate_submission(
				_tutorial_challenge, answer, elapsed, is_timeout
		)
		_tutorial_has_result = true
		_tutorial_practice_active = false
		challenge_view.lock_input()

func _create_inter_round_instruction_layer() -> void:
	_inter_round_layer = CenterContainer.new()
	_inter_round_layer.name = "InterRoundInstruction"
	_inter_round_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inter_round_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inter_round_layer.visible = false
	add_child(_inter_round_layer)

	_inter_round_label = NeuText.new()
	_inter_round_label.name = "InstructionText"
	_inter_round_label.font_size = 56
	_inter_round_label.bold = true
	_inter_round_label.color = NeuKit.INK
	_inter_round_label.look = NeuText.Look.EMBOSS
	_inter_round_label.align = HORIZONTAL_ALIGNMENT_CENTER
	_inter_round_label.autowrap = true
	_inter_round_label.line_spacing = 10.0
	_inter_round_label.custom_minimum_size = Vector2(260.0, 220.0)
	_inter_round_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_inter_round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_inter_round_layer.add_child(_inter_round_label)

func _show_inter_round_instruction(instruction: String) -> void:
	if instruction.strip_edges().is_empty():
		return

	var phase_started_usec: int = Time.get_ticks_usec()
	var safe_was_visible: bool = safe_area.visible if safe_area != null else true
	if safe_area != null:
		safe_area.visible = false

	countdown_overlay.visible = false
	countdown_scrim.visible = false
	feedback_panel.visible = false
	if _inter_round_tween != null and _inter_round_tween.is_valid():
		_inter_round_tween.kill()

	var viewport_width: float = get_viewport_rect().size.x
	_inter_round_label.custom_minimum_size = Vector2(maxf(250.0, viewport_width - 72.0), 220.0)
	_inter_round_label.text = instruction.strip_edges()
	_inter_round_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_inter_round_label.scale = Vector2(0.94, 0.94)
	_inter_round_layer.visible = true
	await get_tree().process_frame
	if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
		return
	_inter_round_label.pivot_offset = _inter_round_label.size * 0.5

	var exit_seconds: float = 0.0
	if Feel.reduced():
		_inter_round_label.modulate = Color.WHITE
		_inter_round_label.scale = Vector2.ONE
	else:
		_inter_round_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_inter_round_tween.tween_property(_inter_round_label, "modulate:a", 1.0, INTER_ROUND_INSTRUCTION_IN_SECONDS)
		_inter_round_tween.tween_property(_inter_round_label, "scale", Vector2.ONE, INTER_ROUND_INSTRUCTION_IN_SECONDS)
		exit_seconds = INTER_ROUND_INSTRUCTION_OUT_SECONDS
		await get_tree().create_timer(INTER_ROUND_INSTRUCTION_IN_SECONDS).timeout

	if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
		return

	# The full instruction phase, including reveal and fade, is capped at 1.5 seconds.
	var elapsed_seconds: float = float(Time.get_ticks_usec() - phase_started_usec) / 1000000.0
	var hold_seconds: float = maxf(0.0, INTER_ROUND_INSTRUCTION_SECONDS - elapsed_seconds - exit_seconds)
	if hold_seconds > 0.0:
		await get_tree().create_timer(hold_seconds).timeout
	if not is_inside_tree() or _tutorial_interrupted or SceneRouter.is_transitioning:
		return

	if not Feel.reduced():
		_inter_round_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_inter_round_tween.tween_property(_inter_round_label, "modulate:a", 0.0, INTER_ROUND_INSTRUCTION_OUT_SECONDS)
		_inter_round_tween.tween_property(_inter_round_label, "scale", Vector2(0.98, 0.98), INTER_ROUND_INSTRUCTION_OUT_SECONDS)
		await get_tree().create_timer(INTER_ROUND_INSTRUCTION_OUT_SECONDS).timeout

	_inter_round_layer.visible = false
	_inter_round_label.modulate = Color.WHITE
	_inter_round_label.scale = Vector2.ONE
	_inter_round_tween = null
	if safe_area != null:
		safe_area.visible = safe_was_visible

func _press_countdown_card() -> void:
		if _countdown_press_tween != null and _countdown_press_tween.is_valid():
				_countdown_press_tween.kill()
		_countdown_press_tween = create_tween()
		_countdown_press_tween.tween_property(_countdown_style, "depth", -0.9, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_countdown_press_tween.tween_property(_countdown_style, "depth", 0.55, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
		# A host-authoritative round start supersedes any pending countdown coroutine.
		_countdown_presentation_token += 1
		# Playback is requested once the first round is actually live. On the normal
		# menu path the gameplay loop has already been synthesized during idle time.
		Music.play_game()
		_kill_tweens()
		_last_tick_second = -1

		countdown_overlay.visible = false
		if _inter_round_layer != null:
			_inter_round_layer.visible = false
		# Restore the overlay's resting offsets/alpha/scale so the next countdown
		# starts from a clean state even if the previous tween was interrupted.
		countdown_overlay.offset_top = _countdown_base_ot
		countdown_overlay.offset_bottom = _countdown_base_ob
		countdown_overlay.modulate.a = 1.0
		countdown_overlay.scale = Vector2.ONE
		countdown_scrim.visible = false
		countdown_scrim.modulate.a = 1.0
		feedback_panel.visible = false
		feedback_panel.scale = Vector2.ONE
		feedback_panel.modulate = Color.WHITE
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
		# Practice submissions are validated locally and never enter scoring, streak,
		# network, or match progression. The live challenge is restored afterwards.
		if _tutorial_practice_active:
				_record_tutorial_submission(choice, false)
				return
		if OS.is_debug_build() and GameManager.match_controller != null \
				and GameManager.match_controller.current_challenge != null \
				and GameManager.match_controller.current_challenge.type == GameConfig.TYPE_SIZE_ORDER:
				print("[SIZE ORDER] GameScreen forwarding selection=%s" % [choice])
		GameManager.submit_answer(choice)

func _on_answer_feedback(player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
		var local_id: int = NetworkSession.get_local_id() if is_multiplayer else 1
		if is_multiplayer and player_id != local_id:
				# Opponent results update the scoreboard only. Personal feedback,
				# sounds, haptics and input locks belong to the player who answered.
				var opponent_total: int = GameManager.match_controller.score_manager.get_player_score(player_id)
				lbl_score_p2.text = "OPPONENT: %d" % opponent_total
				return

		feedback_panel.visible = true
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

		# Soft neumorphic entrance: the card settles into its raised surface instead
		# of snapping or bouncing. Its exit uses the exact reverse motion.
		if feedback_tween != null and feedback_tween.is_valid():
				feedback_tween.kill()
		feedback_panel.pivot_offset = feedback_panel.size * 0.5
		feedback_panel.scale = Vector2(0.955, 0.955)
		feedback_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var active_feedback_style: NeuStyle = feedback_panel.get_theme_stylebox("panel") as NeuStyle
		if active_feedback_style != null:
				active_feedback_style.depth = -0.16
		if Feel.reduced():
				feedback_panel.scale = Vector2.ONE
				feedback_panel.modulate = Color.WHITE
				if active_feedback_style != null:
						active_feedback_style.depth = _feedback_correct_depth if is_correct else _feedback_wrong_depth
		else:
				feedback_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				feedback_tween.tween_property(feedback_panel, "scale", Vector2.ONE, 0.26)
				feedback_tween.tween_property(feedback_panel, "modulate:a", 1.0, 0.23)
				if active_feedback_style != null:
						feedback_tween.tween_property(active_feedback_style, "depth", _feedback_correct_depth if is_correct else _feedback_wrong_depth, 0.26)

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

func _animate_feedback_exit() -> void:
		if feedback_panel == null or not feedback_panel.visible:
				return
		if feedback_tween != null and feedback_tween.is_valid():
				feedback_tween.kill()
		var active_feedback_style: NeuStyle = feedback_panel.get_theme_stylebox("panel") as NeuStyle
		if Feel.reduced():
				feedback_panel.visible = false
				feedback_panel.scale = Vector2.ONE
				feedback_panel.modulate = Color.WHITE
				if active_feedback_style != null:
						active_feedback_style.depth = _feedback_correct_depth if active_feedback_style == _feedback_correct_style else _feedback_wrong_depth
				return
		feedback_panel.pivot_offset = feedback_panel.size * 0.5
		feedback_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		feedback_tween.tween_property(feedback_panel, "scale", Vector2(0.955, 0.955), 0.20)
		feedback_tween.tween_property(feedback_panel, "modulate:a", 0.0, 0.19)
		if active_feedback_style != null:
				feedback_tween.tween_property(active_feedback_style, "depth", -0.16, 0.20)
		await feedback_tween.finished
		if not is_inside_tree():
				return
		feedback_panel.visible = false
		feedback_panel.scale = Vector2.ONE
		feedback_panel.modulate = Color.WHITE
		if active_feedback_style != null:
				active_feedback_style.depth = _feedback_correct_depth if active_feedback_style == _feedback_correct_style else _feedback_wrong_depth

func _kill_tweens() -> void:
		if countdown_tween != null and countdown_tween.is_valid():
				countdown_tween.kill()
		if feedback_tween != null and feedback_tween.is_valid():
				feedback_tween.kill()
		if _countdown_press_tween != null and _countdown_press_tween.is_valid():
				_countdown_press_tween.kill()
		if _entrance_tween != null and _entrance_tween.is_valid():
				_entrance_tween.kill()
		if _inter_round_tween != null and _inter_round_tween.is_valid():
				_inter_round_tween.kill()

func _on_round_ended(_round_num: int, _scores: Dictionary) -> void:
		challenge_view.lock_input()

func _on_scene_transition_started() -> void:
		_countdown_presentation_token += 1
		_tutorial_interrupted = true
		# Resolve any open practice sheet so an awaited tutorial cannot hold a
		# countdown or keep the scene coroutine alive during navigation.
		if _practice_coach != null and _practice_coach.visible:
				_practice_coach.cancel()
		if _tutorial_practice_active:
				_tutorial_practice_active = false
				_tutorial_has_result = true
				_tutorial_result = {"is_correct": false, "details": "Practice was interrupted."}
		# Clear every transient layer before the first visible wipe frame.
		_kill_tweens()
		if _inter_round_layer != null:
			_inter_round_layer.visible = false
		countdown_overlay.visible = false
		countdown_overlay.offset_top = _countdown_base_ot
		countdown_overlay.offset_bottom = _countdown_base_ob
		countdown_overlay.modulate.a = 1.0
		countdown_overlay.scale = Vector2.ONE
		countdown_scrim.visible = false
		countdown_scrim.modulate.a = 1.0
		feedback_panel.visible = false

func _on_match_ended(_results: Dictionary) -> void:
		await _animate_feedback_exit()
		if not is_inside_tree():
				return
		_kill_tweens()
		if score_tween != null and score_tween.is_valid():
				score_tween.kill()
		SceneRouter.goto_results()

# --- HARDWARE BACK (v19) ------------------------------------------------------------

func _exit_tree() -> void:
		_tutorial_interrupted = true
		if _practice_coach != null and _practice_coach.visible:
				_practice_coach.cancel()
		GameManager.resume_round_countdown()
		BackNav.unregister(self)

## Android back / desktop Escape. Leaving a live run costs its points (and a
## live duel), so the question is asked before anything is thrown away.
func handle_back() -> bool:
		if _practice_coach != null and _practice_coach.visible:
				_practice_coach.cancel()
				return true
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
