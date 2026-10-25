class_name TestScoring
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	var sm = ScoreManager.new()
	sm.register_player(1, "Player 1")
	sm.register_player(2, "Player 2")
	
	# Test 1: Fast correct vs slow correct score
	var fast_score = sm.calculate_round_score(true, false, 1.0, 8.0, false)
	var slow_score = sm.calculate_round_score(true, false, 7.0, 8.0, false)
	if fast_score > slow_score:
		passed += 1
	else:
		failed += 1
		errors.append("Fast score (%d) was not higher than slow score (%d)" % [fast_score, slow_score])
		
	# Test 2: Wrong answer penalty
	var wrong_score = sm.calculate_round_score(false, false, 2.0, 8.0, false)
	if wrong_score < 0:
		passed += 1
	else:
		failed += 1
		errors.append("Wrong answer penalty was not negative!")
		
	# Test 3: Timeout gives 0
	var timeout_score = sm.calculate_round_score(false, true, 8.0, 8.0, false)
	if timeout_score == 0:
		passed += 1
	else:
		failed += 1
		errors.append("Timeout score was not 0!")
		
	# Test 4: Withhold success gives full reward
	var withhold_score = sm.calculate_round_score(true, true, 4.0, 4.0, true)
	if withhold_score == GameConfig.WITHHOLD_SUCCESS_SCORE:
		passed += 1
	else:
		failed += 1
		errors.append("Withhold success did not award WITHHOLD_SUCCESS_SCORE!")
		
	# Test 5: Recording submissions and cumulative stats
	sm.reset()
	sm.register_player(1, "P1")
	sm.record_submission(1, 0, true, false, 2.0, 8.0, false)
	sm.record_submission(1, 1, false, false, 3.0, 8.0, false)
	
	var stats = sm.get_player_stats(1)
	if stats["correct_count"] == 1 and stats["incorrect_count"] == 1 and stats["accuracy"] == 50.0:
		passed += 1
	else:
		failed += 1
		errors.append("Stats calculation incorrect: %s" % str(stats))
		
	# Test 6: Tie determination
	sm.reset()
	sm.register_player(1, "P1")
	sm.register_player(2, "P2")
	sm.player_stats[1]["total_score"] = 2500
	sm.player_stats[2]["total_score"] = 2500
	var res_tie = sm.determine_match_result()
	if res_tie["is_tie"] == true:
		passed += 1
	else:
		failed += 1
		errors.append("Equal scores failed to report tie!")
		
	# Test 7: Decisive winner determination
	sm.player_stats[1]["total_score"] = 3000
	var res_win = sm.determine_match_result()
	if res_win["is_tie"] == false and res_win["winner_id"] == 1:
		passed += 1
	else:
		failed += 1
		errors.append("Winner determination failed!")
		
	return {
		"name": "ScoringTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
