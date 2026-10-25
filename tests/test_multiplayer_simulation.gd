class_name TestMultiplayerSimulation
extends RefCounted

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	var test_port = 7015
	
	# Test 1: Server and Client ENet Peer creation
	var server_peer = ENetMultiplayerPeer.new()
	var s_err = server_peer.create_server(test_port, 2)
	if s_err == OK:
		passed += 1
	else:
		failed += 1
		errors.append("Failed to create ENet server peer: %d" % s_err)
		
	var client_peer = ENetMultiplayerPeer.new()
	var c_err = client_peer.create_client("127.0.0.1", test_port)
	if c_err == OK:
		passed += 1
	else:
		failed += 1
		errors.append("Failed to create ENet client peer: %d" % c_err)
		
	# Test 2: Poll peers for connection handshake
	var connected = false
	for i in range(150):
		server_peer.poll()
		client_peer.poll()
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
		OS.delay_msec(10)
		
	if connected:
		passed += 1
	else:
		failed += 1
		errors.append("ENet client and server failed to complete handshake within 1.5s")
		
	# Test 3: Authoritative multi-player scoring state machine
	var host_mc = MatchController.new()
	host_mc.initialize_match(GameConfig.GameMode.MULTIPLAYER_HOST, 3, [1, 2])
	host_mc.start_match()
	host_mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1)
	
	# Host answers
	var ch = host_mc.current_challenge
	var sub_host = host_mc.submit_player_answer(1, ch.correct_answer if ch.options.size() > 0 else 0)
	# Client answers
	var sub_client = host_mc.submit_player_answer(2, ch.correct_answer if ch.options.size() > 0 else 0)
	
	if sub_host["status"] == "accepted" and sub_client["status"] == "accepted":
		passed += 1
	else:
		failed += 1
		errors.append("Host authoritative state machine failed to accept dual player submissions")
		
	# Both players should now have positive scores
	var s1 = host_mc.score_manager.get_player_score(1)
	var s2 = host_mc.score_manager.get_player_score(2)
	if s1 > 0 and s2 > 0:
		passed += 1
	else:
		failed += 1
		errors.append("Scores not calculated for both players: P1=%d, P2=%d" % [s1, s2])
		
	# Clean up network peers
	client_peer.close()
	server_peer.close()
	passed += 1
	
	return {
		"name": "MultiplayerSimulationTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
