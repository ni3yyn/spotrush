class_name TestFullGameLoop
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	var mc = MatchController.new()
	var rounds_to_play = 5
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, rounds_to_play, [1])
	mc.start_match()
	
	# Test 1: Match starts in COUNTDOWN
	if mc.current_state == MatchController.MatchState.COUNTDOWN:
		passed += 1
	else:
		failed += 1
		errors.append("Match did not start in COUNTDOWN state")
		
	# Advance through all 5 rounds
	for r in range(rounds_to_play):
		# Advance past countdown
		mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1)
		if mc.current_state != MatchController.MatchState.ACTIVE_ROUND:
			failed += 1
			errors.append("Round %d did not enter ACTIVE_ROUND" % r)
			break
			
		var ch = mc.current_challenge
		if ch == null or not ch.is_valid():
			failed += 1
			errors.append("Round %d has invalid challenge" % r)
			break
			
		# Submit answer
		var answer_val = ch.correct_answer
		if ch.input_mode == "tap_targets":
			# Find target indices
			var indices = []
			var items = ch.visual_data.get("items", [])
			for i in range(items.size()):
				if items[i].get("is_target", false):
					indices.append(i)
			answer_val = indices
		elif ch.input_mode == "withhold_response":
			answer_val = "TAP" if not bool(ch.correct_answer) else null
			
		if answer_val != null:
			var res = mc.submit_player_answer(1, answer_val)
			if res["status"] != "accepted":
				failed += 1
				errors.append("Round %d answer was not accepted" % r)
		else:
			# Withhold until timeout
			mc.update_process(mc.round_duration + 0.1)
			
		# Advance past feedback
		mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.1)
		passed += 1
		
	# Test 2: Match finishes in MATCH_OVER state
	if mc.current_state == MatchController.MatchState.MATCH_OVER:
		passed += 1
	else:
		failed += 1
		errors.append("Match did not conclude in MATCH_OVER state")
		
	# Test 3: Check score results
	var final_results = mc.score_manager.determine_match_result()
	if final_results.has("highest_score") and final_results["highest_score"] > 0:
		passed += 1
	else:
		failed += 1
		errors.append("Final match score was not recorded properly")
		
	# Test 4: Rematch resets properly
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, rounds_to_play, [1])
	if mc.current_round_index == 0 and mc.score_manager.get_player_score(1) == 0:
		passed += 1
	else:
		failed += 1
		errors.append("Rematch reset failed to restore pristine state")
		
	return {
		"name": "FullGameLoopTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
