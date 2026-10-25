class_name TestGameplayDepth
extends RefCounted

static func run_all_tests() -> Dictionary:
	var results = {
		"name": "GameplayDepthTests",
		"passed": 0,
		"failed": 0,
		"errors": []
	}
	
	test_streak_bonus_progression(results)
	test_streak_reset_on_failure(results)
	test_dont_tap_withhold_scoring(results)
	test_dont_tap_impulse_penalty(results)
	test_dont_tap_go_round_success(results)
	test_side_comparison_difficulty_margins(results)
	test_side_comparison_visual_fairness(results)
	test_estimation_distractor_plausibility(results)
	test_shape_target_uniform_color(results)
	test_multi_attribute_tap_validation(results)
	test_shape_comparison_validation(results)
	test_color_threshold_validation(results)
	test_rematch_state_reset(results)
	
	return results

static func assert_true(cond: bool, msg: String, results: Dictionary) -> void:
	if cond:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(msg)

static func test_streak_bonus_progression(results: Dictionary) -> void:
	var sm = ScoreManager.new()
	sm.register_player(1)
	
	# Round 1: streak 1 (0 streak bonus) -> base (1000) + speed (500) + streak (0) = 1500 pts
	var s1 = sm.record_submission(1, 0, true, false, 0.0, 10.0, false)
	assert_true(s1 == 1500, "Round 1 correct should equal 1500 with 0 streak bonus (got %d)" % s1, results)
	
	# Round 2: streak 2 (+50 bonus) -> 1550 pts
	var s2 = sm.record_submission(1, 1, true, false, 0.0, 10.0, false)
	assert_true(s2 == 1550, "Round 2 correct should equal 1550 with streak 2 bonus (got %d)" % s2, results)
	
	# Round 3: streak 3 (+100 bonus) -> 1600 pts
	var s3 = sm.record_submission(1, 2, true, false, 0.0, 10.0, false)
	assert_true(s3 == 1600, "Round 3 correct should equal 1600 with streak 3 bonus (got %d)" % s3, results)
	
	# Round 4: streak 4 (+150 bonus) -> 1650 pts
	var s4 = sm.record_submission(1, 3, true, false, 0.0, 10.0, false)
	assert_true(s4 == 1650, "Round 4 correct should equal 1650 with streak 4 bonus (got %d)" % s4, results)
	
	# Round 5: streak 5 (+200 bonus) -> 1700 pts
	var s5 = sm.record_submission(1, 4, true, false, 0.0, 10.0, false)
	assert_true(s5 == 1700, "Round 5 correct should equal 1700 with streak 5 bonus (got %d)" % s5, results)
	
	# Round 6: streak 6 (+250 bonus, capped at 250) -> 1750 pts
	var s6 = sm.record_submission(1, 5, true, false, 0.0, 10.0, false)
	assert_true(s6 == 1750, "Round 6 correct should equal 1750 with capped streak bonus (got %d)" % s6, results)
	
	# Round 7: streak 7 (+250 bonus, remains capped) -> 1750 pts
	var s7 = sm.record_submission(1, 6, true, false, 0.0, 10.0, false)
	assert_true(s7 == 1750, "Round 7 correct should remain capped at 1750 (got %d)" % s7, results)
	
	var stats = sm.get_player_stats(1)
	assert_true(stats["current_streak"] == 7, "Current streak should be 7", results)
	assert_true(stats["max_streak"] == 7, "Max streak should be 7", results)

static func test_streak_reset_on_failure(results: Dictionary) -> void:
	var sm = ScoreManager.new()
	sm.register_player(1)
	
	sm.record_submission(1, 0, true, false, 0.0, 10.0, false)
	sm.record_submission(1, 1, true, false, 0.0, 10.0, false)
	assert_true(sm.get_player_stats(1)["current_streak"] == 2, "Streak should be 2", results)
	
	# Incorrect answer (-150 penalty)
	var penalty = sm.record_submission(1, 2, false, false, 1.0, 10.0, false)
	assert_true(penalty == -GameConfig.WRONG_ANSWER_PENALTY, "Penalty should be -%d" % GameConfig.WRONG_ANSWER_PENALTY, results)
	assert_true(sm.get_player_stats(1)["current_streak"] == 0, "Streak should reset to 0 after failure", results)
	assert_true(sm.get_player_stats(1)["max_streak"] == 2, "Max streak should retain record high 2", results)
	
	# Next correct answer restarts streak at 1 (0 streak bonus)
	var s_next = sm.record_submission(1, 3, true, false, 0.0, 10.0, false)
	assert_true(s_next == 1500, "Next correct should have 0 streak bonus (1500 pts, got %d)" % s_next, results)
	assert_true(sm.get_player_stats(1)["current_streak"] == 1, "Current streak should now be 1", results)

static func test_dont_tap_withhold_scoring(results: Dictionary) -> void:
	var challenge = ChallengeDefinition.new("dt_withhold", GameConfig.TYPE_DONT_TAP, "DO NOT TAP", 4.0)
	challenge.input_mode = "withhold_response"
	challenge.correct_answer = true # true = withhold required
	
	# Patient player withholds until timeout (is_timeout = true, elapsed = 4.0)
	var val = AnswerValidator.validate_submission(challenge, null, 4.0, true)
	assert_true(val["is_correct"] == true, "Withholding on No-Go until timeout must validate as correct", results)
	assert_true("Withheld" in val["details"], "Details must explain successful restraint", results)
	
	var sm = ScoreManager.new()
	sm.register_player(1)
	var score = sm.record_submission(1, 0, val["is_correct"], true, 4.0, 4.0, true)
	assert_true(score == GameConfig.WITHHOLD_SUCCESS_SCORE, "Correct restraint must award 1000 pts", results)
	assert_true(sm.get_player_stats(1)["correct_count"] == 1, "Stats correct_count must increment", results)
	assert_true(sm.get_player_stats(1)["missed_count"] == 0, "Stats missed_count must NOT increment on valid restraint", results)

static func test_dont_tap_impulse_penalty(results: Dictionary) -> void:
	var challenge = ChallengeDefinition.new("dt_withhold", GameConfig.TYPE_DONT_TAP, "DO NOT TAP", 4.0)
	challenge.input_mode = "withhold_response"
	challenge.correct_answer = true # withhold required
	
	# Impulsive player taps at 0.5s before timeout
	var val = AnswerValidator.validate_submission(challenge, "TAP", 0.5, false)
	assert_true(val["is_correct"] == false, "Tapping during No-Go round must validate as incorrect", results)
	assert_true("Don't Tap challenge" in val["details"], "Details must explain impulse fault", results)
	
	var sm = ScoreManager.new()
	sm.register_player(1)
	sm.set_player_score(1, 1000)
	var score = sm.record_submission(1, 0, val["is_correct"], false, 0.5, 4.0, true)
	assert_true(score == -GameConfig.WRONG_ANSWER_PENALTY, "Impulse fault must deduct %d pts" % GameConfig.WRONG_ANSWER_PENALTY, results)
	assert_true(sm.get_player_score(1) == (1000 - GameConfig.WRONG_ANSWER_PENALTY), "Total score should reflect deduction", results)

static func test_dont_tap_go_round_success(results: Dictionary) -> void:
	var challenge = ChallengeDefinition.new("dt_go", GameConfig.TYPE_DONT_TAP, "ALL CLEAR — TAP FAST!", 4.0)
	challenge.input_mode = "withhold_response"
	challenge.correct_answer = false # false = tap required (Go round)
	
	# Player taps quickly at 1.0s
	var val = AnswerValidator.validate_submission(challenge, "TAP", 1.0, false)
	assert_true(val["is_correct"] == true, "Tapping on Go stimulus must validate as correct", results)
	
	# If player fails to tap on Go round and times out
	var val_timeout = AnswerValidator.validate_submission(challenge, null, 4.0, true)
	assert_true(val_timeout["is_correct"] == false, "Timing out on Go stimulus must validate as incorrect", results)

static func test_side_comparison_difficulty_margins(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	
	for diff in [1, 2, 3, 4]:
		var ch = ChallengeGenerator.generate_side_comparison(rng, diff, diff)
		var diff_data = ch.visual_data.get("difference", 0)
		match diff:
			1:
				assert_true(diff_data >= 8 and diff_data <= 12, "Diff 1 margin in [8, 12] (got %d)" % diff_data, results)
			2:
				assert_true(diff_data >= 5 and diff_data <= 7, "Diff 2 margin in [5, 7] (got %d)" % diff_data, results)
			3:
				assert_true(diff_data >= 3 and diff_data <= 4, "Diff 3 margin in [3, 4] (got %d)" % diff_data, results)
			4:
				assert_true(diff_data >= 1 and diff_data <= 2, "Diff 4 margin in [1, 2] (got %d)" % diff_data, results)

static func test_side_comparison_visual_fairness(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 123
	var ch = ChallengeGenerator.generate_side_comparison(rng, 1, 1)
	
	var left_items: Array = ch.visual_data.get("left_items", [])
	var right_items: Array = ch.visual_data.get("right_items", [])
	
	assert_true(left_items.size() > 0 and right_items.size() > 0, "Both sides must have items", results)
	
	# Dot sizes must be identical across both sides
	var sz_left = left_items[0]["size"]
	var sz_right = right_items[0]["size"]
	assert_true(sz_left == sz_right, "Dot sizes must be equal on both sides to prevent density bias", results)
	
	# Left dots stay within left zone (0.08 to 0.42), right stay within right (0.58 to 0.92)
	var left_bounds_ok = true
	for it in left_items:
		if it["x"] < 0.08 or it["x"] > 0.42:
			left_bounds_ok = false
			break
	assert_true(left_bounds_ok, "Left dots must be strictly within left boundary", results)
	
	var right_bounds_ok = true
	for it in right_items:
		if it["x"] < 0.58 or it["x"] > 0.92:
			right_bounds_ok = false
			break
	assert_true(right_bounds_ok, "Right dots must be strictly within right boundary", results)

static func test_estimation_distractor_plausibility(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	var ch = ChallengeGenerator.generate_estimation_count(rng, 0, 2)
	
	var actual = ch.correct_answer
	var options = ch.options
	assert_true(options.size() == 4, "Estimation must offer 4 options", results)
	assert_true(actual in options, "Correct answer must be present in options", results)
	
	# Check options are sorted and distinct
	var unique = {}
	for opt in options:
		unique[opt] = true
	assert_true(unique.size() == 4, "All 4 options must be distinct numbers", results)
	
	# Ensure items array length exactly matches the correct answer
	var items: Array = ch.visual_data.get("items", [])
	assert_true(items.size() == actual, "Rendered visual dots must exactly equal correct answer count", results)

static func test_shape_target_uniform_color(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 999
	var ch = ChallengeGenerator.generate_shape_target(rng, 0, 1)
	
	var items: Array = ch.visual_data.get("items", [])
	var first_color = items[0]["color"]
	var all_same_color = true
	for it in items:
		if it["color"] != first_color:
			all_same_color = false
			break
	assert_true(all_same_color, "All shape targets and distractors must share uniform color to force contour recognition", results)

static func test_multi_attribute_tap_validation(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 555
	var ch = ChallengeGenerator._generate_multi_attribute_tap(rng, 0, 2)
	
	var items: Array = ch.visual_data.get("items", [])
	var target_indices: Array = []
	var non_target_indices: Array = []
	for i in range(items.size()):
		if items[i].get("is_target", false):
			target_indices.append(i)
		else:
			non_target_indices.append(i)
			
	assert_true(target_indices.size() > 0, "Multi-attribute challenge must have targets", results)
	assert_true(non_target_indices.size() > 0, "Multi-attribute challenge must have distractors", results)
	
	# Perfect tap submission
	var val_perfect = AnswerValidator.validate_submission(ch, target_indices, 2.0, false)
	assert_true(val_perfect["is_correct"] == true, "Tapping exactly the targets must be correct", results)
	assert_true(val_perfect["accuracy"] == 1.0, "Accuracy must be 1.0", results)
	
	# Impulsive tap including a distractor
	var flawed_tap = target_indices.duplicate()
	flawed_tap.append(non_target_indices[0])
	var val_flawed = AnswerValidator.validate_submission(ch, flawed_tap, 2.0, false)
	assert_true(val_flawed["is_correct"] == false, "Tapping any distractor must invalidate answer", results)
	
	# Partial tap
	var partial_tap = target_indices.slice(0, target_indices.size() - 1)
	var val_partial = AnswerValidator.validate_submission(ch, partial_tap, 2.0, false)
	assert_true(val_partial["is_correct"] == false, "Missing a target must invalidate answer", results)

static func test_shape_comparison_validation(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 333
	var ch = ChallengeGenerator._generate_shape_comparison(rng, 0, 1)
	
	var tri_cnt = ch.visual_data["count_triangles"]
	var sqr_cnt = ch.visual_data["count_squares"]
	var expected = "YES" if tri_cnt > sqr_cnt else "NO"
	assert_true(ch.correct_answer == expected, "Shape comparison correct answer must match triangle > square condition", results)
	
	var val_ok = AnswerValidator.validate_submission(ch, expected, 1.5, false)
	assert_true(val_ok["is_correct"] == true, "Submitting correct choice must pass", results)
	
	var wrong = "NO" if expected == "YES" else "YES"
	var val_bad = AnswerValidator.validate_submission(ch, wrong, 1.5, false)
	assert_true(val_bad["is_correct"] == false, "Submitting wrong choice must fail", results)

static func test_color_threshold_validation(results: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 111
	var ch = ChallengeGenerator._generate_color_threshold(rng, 0, 1)
	
	var red_cnt = ch.visual_data["red_count"]
	var thresh = ch.visual_data["threshold"]
	var expected = "YES" if red_cnt >= thresh else "NO"
	assert_true(ch.correct_answer == expected, "Threshold correct answer must match red >= threshold condition", results)
	
	var val = AnswerValidator.validate_submission(ch, expected, 1.5, false)
	assert_true(val["is_correct"] == true, "Submitting correct threshold choice must pass", results)

static func test_rematch_state_reset(results: Dictionary) -> void:
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	mc.start_match()
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1) # into active round
	
	# Submit round 1 answer
	mc.submit_player_answer(1, mc.current_challenge.correct_answer)
	assert_true(mc.score_manager.get_player_score(1) > 0, "Score should increase after round 1", results)
	assert_true(mc.score_manager.get_player_stats(1)["current_streak"] == 1, "Streak should be 1", results)
	
	# Simulate rematch by calling initialize_match again
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	assert_true(mc.current_round_index == 0, "Round index must reset to 0", results)
	assert_true(mc.score_manager.get_player_score(1) == 0, "Score must reset to 0", results)
	assert_true(mc.score_manager.get_player_stats(1)["current_streak"] == 0, "Streak must reset to 0", results)
	assert_true(mc.current_state == MatchController.MatchState.IDLE, "State must reset to IDLE", results)
