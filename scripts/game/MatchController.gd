class_name MatchController
extends RefCounted

const Records = preload("res://scripts/core/Records.gd")

signal round_countdown_started(round_index: int, total_rounds: int)
signal round_started(round_index: int, challenge: ChallengeDefinition, duration: float)
signal answer_feedback_received(player_id: int, is_correct: bool, score_delta: int, details: String)
signal round_ended(round_index: int, scores: Dictionary)
signal match_ended(results: Dictionary)
signal time_tick(remaining: float, total: float)

enum MatchState {
		IDLE,
		COUNTDOWN,
		ACTIVE_ROUND,
		FEEDBACK,
		MATCH_OVER
}

var current_state: MatchState = MatchState.IDLE
var game_mode: GameConfig.GameMode = GameConfig.GameMode.SINGLE_PLAYER

var total_rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS
var current_round_index: int = 0
var current_challenge: ChallengeDefinition = null

var round_timer: float = 0.0
var round_duration: float = 0.0
var countdown_timer: float = 0.0
var feedback_timer: float = 0.0
var _ui_tick_accumulator: float = 0.0
const UI_TICK_INTERVAL: float = 0.05 # 20 Hz is ample for a tenth-second display.

var score_manager: ScoreManager = ScoreManager.new()

# Live skill rating (1..4): adapts each round's difficulty to recent performance
# (correct+fast climbs 2 bands, correct+slow 1, a miss eases off 1) and persists
# across sessions so returning players start near their level.
var skill_rating: int = 1

# Daily Spot: when challenge_seed >= 0, the whole run is forged from the fixed
# per-day seed (identical series for every player), and fixed_difficulty_ramp
# switches the deck to the full 1..4 fixed ramp so the curve is identical worldwide.
var challenge_seed: int = -1
var fixed_difficulty_ramp: bool = false

# Rival Codes (v17): when challenge_band >= 0 the deck anchors the curve at the
# code's band and keeps it pure (no adaptive momentum), so the seed alone
# determines the series and a friend's phone deals the identical run.
var challenge_band: int = -1

# v16 RUN FORGE: the deck owning this match's schedule, curve, fairness ledger
# and per-round challenge generation. Forged lazily on the first dealt round so
# daily seeds / mode flags stamped after initialize_match() are respected.
var run_deck: RunDeck = null

# Track submissions per round to prevent duplicates
var round_submissions: Dictionary = {} # player_id -> bool
var player_ids: Array[int] = [1] # 1 is host/local player, 2 is remote peer

func initialize_match(mode: GameConfig.GameMode, rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS, p_player_ids: Array[int] = [1]) -> void:
		game_mode = mode
		total_rounds = rounds
		current_round_index = 0
		player_ids = p_player_ids
		
		score_manager.reset()
		skill_rating = Records.skill_rating()
		challenge_seed = -1
		fixed_difficulty_ramp = false
		challenge_band = -1
		run_deck = null
		round_submissions.clear()
		current_challenge = null
		round_timer = 0.0
		countdown_timer = 0.0
		feedback_timer = 0.0
		_ui_tick_accumulator = 0.0
		
		for pid in player_ids:
				var pname = "Player 1 (You)" if pid == 1 else "Player 2"
				if game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT and pid == 1:
						pname = "Host"
				score_manager.register_player(pid, pname)
				
		current_state = MatchState.IDLE

func start_match() -> void:
		current_round_index = 0
		_begin_round_countdown()

func _begin_round_countdown() -> void:
		# Prepare the next challenge before the countdown so the playfield is never
		# empty during the opening GET READY sequence. Input remains locked until
		# _start_active_round transitions the match to ACTIVE_ROUND.
		if game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT and current_challenge == null:
				_generate_current_challenge()
		current_state = MatchState.COUNTDOWN
		countdown_timer = GameConfig.COUNTDOWN_DURATION
		round_countdown_started.emit(current_round_index + 1, total_rounds)

## Roll the current round's challenge (host / single-player only).
func _generate_current_challenge() -> void:
		if run_deck == null:
				_forge_deck()
		current_challenge = run_deck.begin_round(current_round_index)
		round_duration = current_challenge.time_limit

## Forge the run's deck from the current mode flags.
##   * Daily Spot: fixed seed, fixed full ramp, identical worldwide.
##   * Solo: fresh seed, curve anchored at the player's persisted rating,
##     with live momentum bending it as results come in.
##   * Duel: fresh seed shared with the joining phone (challenges travel in
##     the round packets), curve anchored at the host's rating, pure curve so
##     both duelists face the exact same rounds.
func _forge_deck() -> void:
		var start_band := clampi(skill_rating, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		var adaptive := false
		var span := GameConfig.FORGE_RUN_SPAN
		if fixed_difficulty_ramp:
				start_band = 1
				span = 3.0
		elif challenge_band >= 0:
				# Rival Codes: anchor at the code's band, curve stays pure - no live
				# momentum, so both players face byte-identical rounds.
				start_band = clampi(challenge_band, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		elif game_mode == GameConfig.GameMode.SINGLE_PLAYER:
				adaptive = true
		var deck_seed := challenge_seed if challenge_seed >= 0 else RunDeck.fresh_seed()
		run_deck = RunDeck.forge(total_rounds, deck_seed, start_band, adaptive, span)

## Generate the opening challenge WITHOUT starting the countdown, so a screen
## can deal the round behind a closed transition curtain and present it in one
## clean reveal. A later start_match() reuses this challenge instead of rerolling.
func prepare_first_challenge() -> void:
		if game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT and current_challenge == null:
				_generate_current_challenge()
		current_state = MatchState.IDLE

func update_process(delta: float) -> void:
		match current_state:
				MatchState.COUNTDOWN:
						countdown_timer -= delta
						if countdown_timer <= 0.0:
								_start_active_round()
						
				MatchState.ACTIVE_ROUND:
						round_timer += delta
						var remaining := maxf(0.0, round_duration - round_timer)
						_ui_tick_accumulator += delta
						if _ui_tick_accumulator >= UI_TICK_INTERVAL or remaining <= 0.0:
								_ui_tick_accumulator = fmod(_ui_tick_accumulator, UI_TICK_INTERVAL)
								time_tick.emit(remaining, round_duration)
						if round_timer >= round_duration:
								_handle_round_timeout()
						
				MatchState.FEEDBACK:
						feedback_timer -= delta
						if feedback_timer <= 0.0:
								_advance_after_feedback()

func _start_active_round() -> void:
		current_state = MatchState.ACTIVE_ROUND
		round_timer = 0.0
		_ui_tick_accumulator = 0.0
		round_submissions.clear()
		
		# The host/single-player challenge was prepared before the countdown so the
		# UI can render it behind GET READY. Generate here only as a defensive fallback.
		if game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT and current_challenge == null:
				_generate_current_challenge()
		
		round_started.emit(current_round_index + 1, current_challenge, round_duration)

func set_client_round(round_idx: int, challenge_data: Dictionary, duration: float) -> void:
		current_round_index = round_idx
		current_challenge = ChallengeDefinition.from_dict(challenge_data)
		round_duration = duration
		round_timer = 0.0
		round_submissions.clear()
		current_state = MatchState.ACTIVE_ROUND
		round_started.emit(current_round_index + 1, current_challenge, round_duration)

func submit_player_answer(player_id: int, answer: Variant) -> Dictionary:
		if current_state != MatchState.ACTIVE_ROUND:
				return {"status": "rejected", "reason": "Round not active"}
				
		if round_submissions.get(player_id, false):
				return {"status": "rejected", "reason": "Duplicate submission"}
				
		round_submissions[player_id] = true
		var response_time = round_timer
		
		var validation = AnswerValidator.validate_submission(current_challenge, answer, response_time, false)
		var is_correct = validation["is_correct"]
		var is_withhold = (current_challenge.input_mode == "withhold_response")
		
		# Scoring 2.0: harder bands pay a bigger base, so the band rides along.
		var round_difficulty: int = 2
		if current_challenge != null:
				round_difficulty = clampi(current_challenge.difficulty, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		var score_delta = score_manager.record_submission(
				player_id,
				current_round_index,
				is_correct,
				false,
				response_time,
				round_duration,
				is_withhold,
				round_difficulty
		)
		
		answer_feedback_received.emit(player_id, is_correct, score_delta, validation["details"])
		if player_id == 1 and game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
				_update_skill_rating(is_correct, false, response_time)
		
		# In single-player, or if all players submitted, end the round immediately
		var all_submitted = true
		for pid in player_ids:
				if not round_submissions.get(pid, false):
						all_submitted = false
						break
						
		if all_submitted:
				_end_round_with_feedback()
				
		return {
				"status": "accepted",
				"is_correct": is_correct,
				"score_delta": score_delta,
				"details": validation["details"]
		}

func _handle_round_timeout() -> void:
		# Check players who did not submit
		var is_withhold = (current_challenge != null and current_challenge.input_mode == "withhold_response")
		# Scoring 2.0: harder bands pay a bigger base, so the band rides along.
		var round_difficulty: int = 2
		if current_challenge != null:
				round_difficulty = clampi(current_challenge.difficulty, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		
		for pid in player_ids:
				if not round_submissions.get(pid, false):
						round_submissions[pid] = true
						var validation = AnswerValidator.validate_submission(current_challenge, null, round_duration, true)
						var is_correct = validation["is_correct"]
						var score_delta = score_manager.record_submission(
								pid,
								current_round_index,
								is_correct,
								true,
								round_duration,
								round_duration,
								is_withhold,
								round_difficulty
						)
						answer_feedback_received.emit(pid, is_correct, score_delta, validation["details"])
						if pid == 1 and game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
								_update_skill_rating(is_correct, true, round_duration)
						
		_end_round_with_feedback()

func _end_round_with_feedback() -> void:
		current_state = MatchState.FEEDBACK
		feedback_timer = GameConfig.ROUND_FEEDBACK_DURATION
		
		var scores: Dictionary = {}
		for pid in player_ids:
				scores[pid] = score_manager.get_player_score(pid)
				
		round_ended.emit(current_round_index + 1, scores)
		# Generate the next challenge while the result card is on screen. The next
		# countdown then consumes the memoized result instead of forging it on the
		# first frame of the new round.
		if game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT and current_round_index + 1 < total_rounds:
				call_deferred("_prewarm_next_round")

func _prewarm_next_round() -> void:
		if current_state != MatchState.FEEDBACK:
				return
		if game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT or run_deck == null:
				return
		var next_index := current_round_index + 1
		if next_index >= total_rounds:
				return
		var started_usec: int = Time.get_ticks_usec() if OS.is_debug_build() else 0
		run_deck.begin_round(next_index)
		if OS.is_debug_build():
				var elapsed_usec := Time.get_ticks_usec() - started_usec
				if elapsed_usec >= 8000:
						print("[PERF] Next round prewarm: %.2f ms" % (float(elapsed_usec) / 1000.0))

func skip_feedback() -> void:
		if current_state == MatchState.FEEDBACK:
				_advance_after_feedback()

func _advance_after_feedback() -> void:
		current_round_index += 1
		if current_round_index >= total_rounds:
				_conclude_match()
		else:
				current_challenge = null
				round_duration = 0.0
				_begin_round_countdown()

func _conclude_match() -> void:
		current_state = MatchState.MATCH_OVER
		var results = score_manager.determine_match_result()
		results["total_rounds"] = total_rounds
		
		var detailed_stats: Dictionary = {}
		for pid in player_ids:
				detailed_stats[pid] = score_manager.get_player_stats(pid)
		results["player_stats"] = detailed_stats
		match_ended.emit(results)
		
## Adaptive difficulty step: adjust the live rating from the local player's
## result, then persist it so the next session starts near their level.
## The deck's momentum is fed in parallel (solo runs re-bend the curve live).
func _update_skill_rating(is_correct: bool, is_timeout: bool, response_time: float) -> void:
		var step: int
		if is_correct:
				var fast: bool = not is_timeout and response_time <= round_duration * GameConfig.ADAPT_FAST_RATIO
				step = GameConfig.ADAPT_STEP_FAST if fast else GameConfig.ADAPT_STEP_SLOW
		else:
				step = GameConfig.ADAPT_STEP_MISS
		skill_rating = clampi(skill_rating + step, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		Records.set_skill_rating(skill_rating)
		if run_deck != null:
				var was_fast: bool = not is_timeout and response_time <= round_duration * GameConfig.ADAPT_FAST_RATIO
				run_deck.record_result(is_correct, was_fast)

func apply_authoritative_scores(scores: Dictionary) -> void:
		score_manager.apply_authoritative_scores(scores)

## Hard-stop an in-flight run (the player quit it, v19 back flow): back to IDLE
## with no results, no rating side effects and no timers left ticking. Safe on
## an already-idle or finished controller - the next initialize_match() starts
## from a clean slate either way.
func abort_match() -> void:
		current_state = MatchState.IDLE
		current_challenge = null
		round_timer = 0.0
		countdown_timer = 0.0
		feedback_timer = 0.0
		round_submissions.clear()

func handle_peer_disconnected(peer_id: int) -> void:
		if not peer_id in player_ids:
				return
		player_ids.erase(peer_id)
		
		# If in active match and no other human peer remains
		if current_state != MatchState.MATCH_OVER and current_state != MatchState.IDLE:
				_conclude_match()
