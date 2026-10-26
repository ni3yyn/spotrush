class_name MatchController
extends RefCounted

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

var score_manager: ScoreManager = ScoreManager.new()

# Track submissions per round to prevent duplicates
var round_submissions: Dictionary = {} # player_id -> bool
var player_ids: Array[int] = [1] # 1 is host/local player, 2 is remote peer

func initialize_match(mode: GameConfig.GameMode, rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS, p_player_ids: Array[int] = [1]) -> void:
	game_mode = mode
	total_rounds = rounds
	current_round_index = 0
	player_ids = p_player_ids
	
	score_manager.reset()
	round_submissions.clear()
	current_challenge = null
	round_timer = 0.0
	countdown_timer = 0.0
	feedback_timer = 0.0
	
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
	current_state = MatchState.COUNTDOWN
	countdown_timer = GameConfig.COUNTDOWN_DURATION
	round_countdown_started.emit(current_round_index + 1, total_rounds)

func update_process(delta: float) -> void:
	match current_state:
		MatchState.COUNTDOWN:
			countdown_timer -= delta
			if countdown_timer <= 0.0:
				_start_active_round()
				
		MatchState.ACTIVE_ROUND:
			round_timer += delta
			var remaining = maxf(0.0, round_duration - round_timer)
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
	round_submissions.clear()
	
	# Only host or single-player generates challenge
	if game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
		var difficulty = 1 + int(float(current_round_index) / maxf(1.0, float(total_rounds) / 3.0))
		difficulty = clampi(difficulty, 1, 4)
		current_challenge = ChallengeGenerator.generate_challenge(current_round_index, difficulty)
		round_duration = current_challenge.time_limit
	
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
	
	var score_delta = score_manager.record_submission(
		player_id,
		current_round_index,
		is_correct,
		false,
		response_time,
		round_duration,
		is_withhold
	)
	
	answer_feedback_received.emit(player_id, is_correct, score_delta, validation["details"])
	
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
				is_withhold
			)
			answer_feedback_received.emit(pid, is_correct, score_delta, validation["details"])
			
	_end_round_with_feedback()

func _end_round_with_feedback() -> void:
	current_state = MatchState.FEEDBACK
	feedback_timer = GameConfig.ROUND_FEEDBACK_DURATION
	
	var scores: Dictionary = {}
	for pid in player_ids:
		scores[pid] = score_manager.get_player_score(pid)
		
	round_ended.emit(current_round_index + 1, scores)

func skip_feedback() -> void:
	if current_state == MatchState.FEEDBACK:
		_advance_after_feedback()

func _advance_after_feedback() -> void:
	current_round_index += 1
	if current_round_index >= total_rounds:
		_conclude_match()
	else:
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
	
func apply_authoritative_scores(scores: Dictionary) -> void:
	score_manager.apply_authoritative_scores(scores)

func handle_peer_disconnected(peer_id: int) -> void:
	if not peer_id in player_ids:
		return
	player_ids.erase(peer_id)
	
	# If in active match and no other human peer remains
	if current_state != MatchState.MATCH_OVER and current_state != MatchState.IDLE:
		_conclude_match()
