extends SceneTree

const TEST_PORT = 7025

class ClientNode extends Node:
	var peer: ENetMultiplayerPeer
	var ticks_start: int = 0
	var received_challenge: ChallengeDefinition = null
	var match_end_verified: bool = false
	
	func _ready() -> void:
		name = "NetTest"
		print("[CLIENT PROCESS] Connecting to ENet host at 127.0.0.1:%d..." % TEST_PORT)
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_client("127.0.0.1", TEST_PORT)
		if err != OK:
			print("[CLIENT PROCESS] ERROR: Failed to create client: %d" % err)
			get_tree().quit(1)
			return
			
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connect_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		ticks_start = Time.get_ticks_msec()
		
	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() - ticks_start > 8000:
			print("[CLIENT PROCESS] ERROR: Test timed out after 8s!")
			get_tree().quit(1)

	func _on_connected() -> void:
		print("[CLIENT PROCESS] Connected to Host! Unique ID: %d" % multiplayer.get_unique_id())

	func _on_connect_failed() -> void:
		print("[CLIENT PROCESS] ERROR: Connection failed!")
		get_tree().quit(1)

	func _on_server_disconnected() -> void:
		print("[CLIENT PROCESS] Server disconnected")

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_client_receive(packet: Dictionary) -> void:
		var msg_type = packet.get("type", "")
		var data = packet.get("data", {})
		print("[CLIENT PROCESS] Received message: '%s'" % msg_type)
		
		match msg_type:
			NetworkProtocol.MSG_MATCH_START:
				print("[CLIENT PROCESS] Match start received! Total rounds: %d" % data.get("total_rounds", 0))
				
			NetworkProtocol.MSG_ROUND_START:
				var ch_dict = data.get("challenge", {})
				received_challenge = ChallengeDefinition.from_dict(ch_dict)
				if not received_challenge.is_valid():
					print("[CLIENT PROCESS] ERROR: Received invalid challenge payload!")
					get_tree().quit(1)
					return
					
				print("[CLIENT PROCESS] Valid challenge received: '%s'. Submitting correct answer: %s..." % [received_challenge.instruction, str(received_challenge.correct_answer)])
				
				# Submit answer to host node at /root/NetTest
				var p_ans = NetworkProtocol.create_packet(NetworkProtocol.MSG_SUBMIT_ANSWER, {
					"round_index": 0,
					"answer": received_challenge.correct_answer
				})
				_rpc_host_receive.rpc_id(1, p_ans)
				
			NetworkProtocol.MSG_ANSWER_RESULT:
				var is_corr = data.get("is_correct", false)
				var sc_delta = data.get("score_delta", 0)
				print("[CLIENT PROCESS] Answer result: correct=%s, score_delta=+%d" % [str(is_corr), sc_delta])
				if not is_corr or sc_delta <= 0:
					print("[CLIENT PROCESS] ERROR: Unexpected answer result from host!")
					get_tree().quit(1)
					
			NetworkProtocol.MSG_ROUND_END:
				print("[CLIENT PROCESS] Round end received! Authoritative scores: %s" % str(data.get("scores", {})))
				
			NetworkProtocol.MSG_MATCH_END:
				print("[CLIENT PROCESS] Match end received with authoritative results!")
				match_end_verified = true
				print("[CLIENT PROCESS] >> REAL TWO-PROCESS TEST PASSED ON CLIENT! <<")
				get_tree().quit(0)

	@rpc("any_peer", "call_remote", "reliable")
	func _rpc_host_receive(_packet: Dictionary) -> void:
		pass

func _init() -> void:
	var client_node = ClientNode.new()
	root.add_child(client_node)
