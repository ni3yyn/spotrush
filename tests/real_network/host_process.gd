extends SceneTree

const TEST_PORT = 7025

class HostNode extends Node:
	var peer: ENetMultiplayerPeer
	var client_id: int = -1
	var test_challenge: ChallengeDefinition
	var ticks_start: int = 0
	
	func _ready() -> void:
		name = "NetTest"
		print("[HOST PROCESS] Starting real ENet server on port %d..." % TEST_PORT)
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(TEST_PORT, 2)
		if err != OK:
			print("[HOST PROCESS] ERROR: Failed to create server: %d" % err)
			get_tree().quit(1)
			return
			
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_client_connected)
		multiplayer.peer_disconnected.connect(_on_client_disconnected)
		ticks_start = Time.get_ticks_msec()
		
	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() - ticks_start > 8000:
			print("[HOST PROCESS] ERROR: Test timed out after 8s!")
			get_tree().quit(1)

	func _on_client_connected(id: int) -> void:
		print("[HOST PROCESS] Client connected with Peer ID: %d" % id)
		client_id = id
		
		# Generate test challenge
		test_challenge = ChallengeGenerator.generate_estimation_count(RandomNumberGenerator.new(), 0, 1)
		
		# 1. Send match start
		var p_match = NetworkProtocol.create_packet(NetworkProtocol.MSG_MATCH_START, {
			"total_rounds": 1,
			"player_ids": [1, client_id]
		})
		_rpc_client_receive.rpc_id(client_id, p_match)
		
		# 2. Send round start
		var p_round = NetworkProtocol.create_packet(NetworkProtocol.MSG_ROUND_START, {
			"round_num": 1,
			"duration": test_challenge.time_limit,
			"challenge": test_challenge.to_dict()
		})
		_rpc_client_receive.rpc_id(client_id, p_round)
		print("[HOST PROCESS] Sent challenge to client (ID: %s, Answer: %s)" % [test_challenge.id, str(test_challenge.correct_answer)])

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_host_receive(packet: Dictionary) -> void:
		var sender = multiplayer.get_remote_sender_id()
		print("[HOST PROCESS] Received packet '%s' from sender %d" % [packet.get("type", ""), sender])
		
		if packet.get("type", "") == NetworkProtocol.MSG_SUBMIT_ANSWER:
			var data = packet.get("data", {})
			var answer = data.get("answer", null)
			print("[HOST PROCESS] Authoritatively validating client answer: %s (Expected: %s)" % [str(answer), str(test_challenge.correct_answer)])
			
			var validation = AnswerValidator.validate_submission(test_challenge, answer, 1.2, false)
			if not validation["is_correct"]:
				print("[HOST PROCESS] ERROR: Validation reported incorrect answer!")
				get_tree().quit(1)
				return
				
			var score_delta = 1400
			print("[HOST PROCESS] Validation SUCCESS: +%d pts awarded authoritatively!" % score_delta)
			
			# Send Answer Result & Round End
			var p_res = NetworkProtocol.create_packet(NetworkProtocol.MSG_ANSWER_RESULT, {
				"player_id": sender,
				"is_correct": true,
				"score_delta": score_delta,
				"details": "Correct"
			})
			_rpc_client_receive.rpc_id(client_id, p_res)
			
			var p_end = NetworkProtocol.create_packet(NetworkProtocol.MSG_ROUND_END, {
				"round_num": 1,
				"scores": { 1: 0, client_id: score_delta }
			})
			_rpc_client_receive.rpc_id(client_id, p_end)
			
			var p_match_end = NetworkProtocol.create_packet(NetworkProtocol.MSG_MATCH_END, {
				"results": {
					"winner_id": client_id,
					"is_tie": false,
					"player_stats": {
						1: { "total_score": 0 },
						client_id: { "total_score": score_delta }
					}
				}
			})
			_rpc_client_receive.rpc_id(client_id, p_match_end)
			print("[HOST PROCESS] Successfully completed authoritative round and dispatched match end!")
			
			# Wait 600ms for packet delivery then finish with code 0
			var tw = create_tween()
			tw.tween_interval(0.6)
			tw.tween_callback(func():
				print("[HOST PROCESS] >> REAL TWO-PROCESS TEST PASSED ON HOST! <<")
				get_tree().quit(0)
			)

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_client_receive(_packet: Dictionary) -> void:
		pass

	func _on_client_disconnected(id: int) -> void:
		print("[HOST PROCESS] Client %d disconnected" % id)

func _init() -> void:
	var host_node = HostNode.new()
	root.add_child(host_node)
