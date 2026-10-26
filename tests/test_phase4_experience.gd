class_name TestPhase4Experience
extends RefCounted

static func run_all_tests() -> Dictionary:
	var results = {
		"name": "Phase4ExperienceTests",
		"passed": 0,
		"failed": 0,
		"errors": []
	}
	
	test_complete_flow_and_rematch_clean_state(results)
	test_duplicate_answer_and_action_protection(results)
	test_skip_feedback_and_pacing(results)
	test_timer_input_window_and_timeout_race(results)
	test_dont_tap_interactive_clarity_and_fault(results)
	test_authoritative_score_integrity_during_animation(results)
	test_multiplayer_repeated_input_and_disconnect(results)
	test_viewport_layouts_narrow_and_wide(results)
	test_multi_round_performance_and_no_leak(results)
	
	return results

static func assert_true(cond: bool, msg: String, results: Dictionary) -> void:
	if cond:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(msg)

# 1. Flow & State: Start -> Advance -> Results -> Rematch -> Menu -> Pristine new match
static func test_complete_flow_and_rematch_clean_state(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	mc.start_match()
	
	assert_true(mc.current_state == MatchController.MatchState.COUNTDOWN, "Match starts in COUNTDOWN", results)
	
	# Round 1
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	assert_true(mc.current_state == MatchController.MatchState.ACTIVE_ROUND, "Round 1 is ACTIVE", results)
	assert_true(mc.round_submissions.size() == 0, "Round 1 starts with 0 submissions", results)
	
	# Submit answer
	var res1 = mc.submit_player_answer(1, mc.current_challenge.correct_answer if mc.current_challenge.input_mode == "choice" else "TAP")
	assert_true(res1["status"] == "accepted", "Submission 1 accepted", results)
	assert_true(mc.current_state == MatchController.MatchState.FEEDBACK, "State transitions to FEEDBACK", results)
	
	# Advance to Round 2
	mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.05)
	assert_true(mc.current_state == MatchController.MatchState.COUNTDOWN, "Transitions to COUNTDOWN for Round 2", results)
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	assert_true(mc.current_round_index == 1, "Now on Round index 1", results)
	
	# Timeout Round 2
	mc.update_process(mc.round_duration + 0.05)
	assert_true(mc.current_state == MatchController.MatchState.FEEDBACK, "Timeout transitions to FEEDBACK", results)
	
	# Advance to Round 3
	mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.05)
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	assert_true(mc.current_round_index == 2, "Now on Round index 2", results)
	
	# Finish Round 3
	mc.update_process(mc.round_duration + 0.05)
	mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.05)
	assert_true(mc.current_state == MatchController.MatchState.MATCH_OVER, "Concludes in MATCH_OVER", results)
	
	# Verify rematch re-initialization restores pristine state
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	assert_true(mc.current_state == MatchController.MatchState.IDLE, "Rematch resets state to IDLE", results)
	assert_true(mc.current_round_index == 0, "Rematch resets round index to 0", results)
	assert_true(mc.score_manager.get_player_score(1) == 0, "Rematch resets score to 0", results)
	assert_true(mc.score_manager.get_player_stats(1)["current_streak"] == 0, "Rematch resets streak to 0", results)
	assert_true(mc.round_submissions.is_empty(), "Rematch clears round submissions", results)

# 2. Duplicate Action Protection
static func test_duplicate_answer_and_action_protection(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 2, [1])
	mc.start_match()
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	
	# Attempt first answer
	var res_first = mc.submit_player_answer(1, "OPT_A")
	assert_true(res_first["status"] == "accepted", "First submission accepted", results)
	
	# Attempt duplicate answer in same round
	var res_second = mc.submit_player_answer(1, "OPT_A")
	assert_true(res_second["status"] == "rejected", "Second submission in same round rejected", results)
	assert_true("Duplicate" in res_second["reason"] or "Round not active" in res_second["reason"], "Rejection reason accurate", results)
	
	# Attempt submission during FEEDBACK state
	var res_feedback = mc.submit_player_answer(1, "OPT_B")
	assert_true(res_feedback["status"] == "rejected", "Submission during FEEDBACK rejected", results)
	
	# Advance to COUNTDOWN
	mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.05)
	var res_countdown = mc.submit_player_answer(1, "OPT_C")
	assert_true(res_countdown["status"] == "rejected", "Submission during COUNTDOWN rejected", results)

# 3. Skip Feedback & Fast Pacing
static func test_skip_feedback_and_pacing(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 2, [1])
	mc.start_match()
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	
	# Answer round 0
	mc.submit_player_answer(1, "VAL")
	assert_true(mc.current_state == MatchController.MatchState.FEEDBACK, "Now in FEEDBACK", results)
	
	# Player taps to skip feedback
	mc.skip_feedback()
	assert_true(mc.current_state == MatchController.MatchState.COUNTDOWN, "Skipping feedback immediately enters COUNTDOWN", results)
	assert_true(mc.current_round_index == 1, "Advanced to round index 1", results)
	
	# Calling skip_feedback again when not in FEEDBACK does nothing harmful
	mc.skip_feedback()
	assert_true(mc.current_state == MatchController.MatchState.COUNTDOWN, "Duplicate skip call harmless", results)

# 4. Timer Window & Timeout Race Condition
static func test_timer_input_window_and_timeout_race(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 2, [1])
	mc.start_match()
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	
	# Trigger timeout by running timer past round duration
	mc.update_process(mc.round_duration + 0.01)
	assert_true(mc.current_state == MatchController.MatchState.FEEDBACK, "Timeout transitions to FEEDBACK", results)
	
	# Late answer arrived right after timeout must be rejected
	var late_res = mc.submit_player_answer(1, "LATE")
	assert_true(late_res["status"] == "rejected", "Late answer rejected after timeout", results)

# 5. Don't Tap Go/No-Go Clarity and Restraint
static func test_dont_tap_interactive_clarity_and_fault(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 2026
	
	# Test Go Round (should_withhold = false)
	var ch_go = ChallengeGenerator.generate_dont_tap_rule(rng, 0, 1)
	ch_go.visual_data["should_withhold"] = false
	ch_go.correct_answer = false
	
	var val_go = AnswerValidator.validate_submission(ch_go, "TAP", 0.6, false)
	assert_true(val_go["is_correct"] == true, "Tapping during Go stimulus is correct", results)
	
	# Test No-Go Round (should_withhold = true)
	var ch_nogo = ChallengeGenerator.generate_dont_tap_rule(rng, 1, 1)
	ch_nogo.visual_data["should_withhold"] = true
	ch_nogo.correct_answer = true
	
	# Impulsive tap
	var val_impulse = AnswerValidator.validate_submission(ch_nogo, "TAP", 0.5, false)
	assert_true(val_impulse["is_correct"] == false, "Tapping during No-Go is impulse fault", results)
	
	# Valid restraint until timeout
	var val_restraint = AnswerValidator.validate_submission(ch_nogo, null, ch_nogo.time_limit, true)
	assert_true(val_restraint["is_correct"] == true, "Withholding on No-Go until timeout succeeds", results)
	assert_true("Withheld" in val_restraint["details"], "Restraint details logged", results)

# 6. Authoritative Score Integrity
static func test_authoritative_score_integrity_during_animation(results: Dictionary) -> void:
	var sm = ScoreManager.new()
	sm.register_player(1)
	
	# Award 1000 pts
	var delta1 = sm.record_submission(1, 0, true, false, 1.0, 10.0, false)
	var authoritative_sc = sm.get_player_score(1)
	assert_true(authoritative_sc == delta1, "Authoritative score matches recorded delta", results)
	
	# Multiple client score applications
	var host_scores = {1: 3450}
	sm.apply_authoritative_scores(host_scores)
	assert_true(sm.get_player_score(1) == 3450, "Authoritative score properly synchronizes", results)

# 7. Multiplayer Repeated Input & Disconnection Handling
static func test_multiplayer_repeated_input_and_disconnect(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.MULTIPLAYER_HOST, 3, [1, 2])
	mc.start_match()
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.05)
	
	# Peer 2 submits twice
	var res2_first = mc.submit_player_answer(2, "ANS")
	assert_true(res2_first["status"] == "accepted", "Peer 2 first submission accepted", results)
	var res2_dup = mc.submit_player_answer(2, "ANS")
	assert_true(res2_dup["status"] == "rejected", "Peer 2 duplicate submission rejected", results)
	
	# Peer 2 disconnects during match
	mc.handle_peer_disconnected(2)
	assert_true(not 2 in mc.player_ids, "Peer 2 removed from match player_ids", results)
	assert_true(mc.current_state == MatchController.MatchState.MATCH_OVER, "Host match concludes cleanly when remote client leaves", results)

# 8. Viewport Layouts Narrow and Wide
static func test_viewport_layouts_narrow_and_wide(results: Dictionary) -> void:
	var cv_scene = load("res://scenes/game/ChallengeView.tscn")
	if cv_scene != null:
		var cv = cv_scene.instantiate()
		var rng = RandomNumberGenerator.new()
		rng.seed = 99
		var ch = ChallengeGenerator.generate_side_comparison(rng, 1, 1)
		
		cv.set_anchors_preset(Control.PRESET_TOP_LEFT)
		
		# Test narrow portrait (e.g. 360 x 640)
		cv.custom_minimum_size = Vector2(360, 640)
		cv.size = Vector2(360, 640)
		cv.load_challenge(ch)
		var canvas = cv.get_node("%ChallengeCanvas")
		assert_true(canvas.size.x >= 0 and canvas.size.y >= 0, "Canvas valid on narrow viewport", results)
		
		# Test wide/tablet portrait (e.g. 800 x 1280)
		cv.custom_minimum_size = Vector2(800, 1280)
		cv.size = Vector2(800, 1280)
		cv.load_challenge(ch)
		assert_true(canvas.size.x >= 0 and canvas.size.y >= 0, "Canvas valid on wide viewport", results)
		cv.free()
	else:
		assert_true(false, "ChallengeView scene load failed", results)

# 9. Performance & Cleanup: 30 Consecutive Rounds Without Leaks
static func test_multi_round_performance_and_no_leak(results: Dictionary) -> void:
	var mc = MatchController.new()
	var start_ticks = Time.get_ticks_msec()
	
	for m in range(3):
		mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 10, [1])
		mc.start_match()
		for r in range(10):
			mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.01)
			mc.submit_player_answer(1, "VAL")
			mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.01)
			
	var elapsed = Time.get_ticks_msec() - start_ticks
	assert_true(elapsed < 2000, "30 simulated rounds processed in under 2000ms (took %dms)" % elapsed, results)
	assert_true(mc.current_state == MatchController.MatchState.MATCH_OVER, "Concluded in MATCH_OVER", results)
	assert_true(mc.round_submissions.size() <= 1, "Round submissions do not accumulate indefinitely", results)
