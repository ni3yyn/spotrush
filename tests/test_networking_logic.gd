class_name TestNetworkingLogic
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	# Test 1: Valid packet creation & verification
	var packet = NetworkProtocol.create_packet(NetworkProtocol.MSG_MATCH_START, {"total_rounds": 10})
	if NetworkProtocol.is_valid_packet(packet):
		passed += 1
	else:
		failed += 1
		errors.append("Valid packet was rejected by validator")
		
	# Test 2: Incompatible version rejection
	var bad_ver_packet = packet.duplicate(true)
	bad_ver_packet["ver"] = 999
	if not NetworkProtocol.is_valid_packet(bad_ver_packet):
		passed += 1
	else:
		failed += 1
		errors.append("Incompatible protocol version was not rejected")
		
	# Test 3: Missing fields rejection
	var corrupt_packet = {"ver": NetworkProtocol.PROTOCOL_VERSION}
	if not NetworkProtocol.is_valid_packet(corrupt_packet):
		passed += 1
	else:
		failed += 1
		errors.append("Corrupt packet was not rejected")
		
	# Test 4: Stale round answer detection via MatchController logic
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 5, [1])
	mc.start_match()
	# Advance round state to ACTIVE
	mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1)
	
	# Submit answer for current round
	var sub1 = mc.submit_player_answer(1, mc.current_challenge.options[0] if mc.current_challenge.options.size() > 0 else 0)
	if sub1["status"] == "accepted":
		passed += 1
	else:
		failed += 1
		errors.append("Valid round answer submission was rejected")
		
	# Duplicate submission for the same round must be rejected
	var sub_dup = mc.submit_player_answer(1, "SECOND_TRY")
	if sub_dup["status"] == "rejected":
		passed += 1
	else:
		failed += 1
		errors.append("Duplicate round answer was NOT rejected!")

	# Test 5: Host handles peer disconnect during match
	var host_mc = MatchController.new()
	host_mc.initialize_match(GameConfig.GameMode.MULTIPLAYER_HOST, 5, [1, 2])
	host_mc.start_match()
	host_mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1)
	host_mc.handle_peer_disconnected(2)
	if host_mc.current_state == MatchController.MatchState.MATCH_OVER:
		passed += 1
	else:
		failed += 1
		errors.append("Host failed to conclude match cleanly upon peer disconnect")

	# Test 6: Authoritative score synchronization
	var client_sm = ScoreManager.new()
	client_sm.register_player(1)
	client_sm.register_player(2)
	client_sm.apply_authoritative_scores({"1": 1500, "2": 2200})
	if client_sm.get_player_score(1) == 1500 and client_sm.get_player_score(2) == 2200:
		passed += 1
	else:
		failed += 1
		errors.append("Score synchronization failed to apply authoritative scores")

	# Test 7: Submission rejected when round is not active (e.g. during COUNTDOWN)
	var idle_mc = MatchController.new()
	idle_mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	idle_mc.start_match() # starts in COUNTDOWN
	var sub_countdown = idle_mc.submit_player_answer(1, "PREMATURE")
	if sub_countdown["status"] == "rejected":
		passed += 1
	else:
		failed += 1
		errors.append("Answer during COUNTDOWN was not rejected")

	return {
		"name": "NetworkingLogicTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
