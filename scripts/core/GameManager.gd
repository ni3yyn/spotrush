extends Node

var match_controller: MatchController = MatchController.new()
var current_game_mode: GameConfig.GameMode = GameConfig.GameMode.SINGLE_PLAYER
var last_match_results: Dictionary = {}

# Signals for UI views
signal ui_countdown_started(round_num: int, total_rounds: int)
signal ui_round_started(round_num: int, challenge: ChallengeDefinition, duration: float)
signal ui_time_tick(remaining: float, total: float)
signal ui_answer_feedback(player_id: int, is_correct: bool, score_delta: int, details: String)
signal ui_round_ended(round_num: int, scores: Dictionary)
signal ui_match_ended(results: Dictionary)

func _ready() -> void:
	match_controller.round_countdown_started.connect(_on_controller_countdown_started)
	match_controller.round_started.connect(_on_controller_round_started)
	match_controller.time_tick.connect(_on_controller_time_tick)
	match_controller.answer_feedback_received.connect(_on_controller_answer_feedback)
	match_controller.round_ended.connect(_on_controller_round_ended)
	match_controller.match_ended.connect(_on_controller_match_ended)
	
	NetworkSession.packet_received.connect(_on_network_packet_received)
	NetworkSession.peer_disconnected.connect(_on_peer_disconnected)
	NetworkSession.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if current_game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
		match_controller.update_process(delta)
	else:
		if match_controller.current_state == MatchController.MatchState.ACTIVE_ROUND:
			match_controller.round_timer += delta
			var rem = maxf(0.0, match_controller.round_duration - match_controller.round_timer)
			ui_time_tick.emit(rem, match_controller.round_duration)

func start_single_player_match(rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS) -> void:
	current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
	match_controller.initialize_match(current_game_mode, rounds, [1])
	match_controller.start_match()

func start_multiplayer_host_match(rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS) -> void:
	current_game_mode = GameConfig.GameMode.MULTIPLAYER_HOST
	var peers: Array[int] = [1]
	for p in NetworkSession.connected_peers:
		peers.append(p)
	match_controller.initialize_match(current_game_mode, rounds, peers)
	
	NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_START, {
		"total_rounds": rounds,
		"player_ids": peers
	})
	
	match_controller.start_match()

func submit_answer(answer: Variant) -> void:
	if current_game_mode == GameConfig.GameMode.SINGLE_PLAYER or current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		match_controller.submit_player_answer(1, answer)
	elif current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
		NetworkSession.send_to_server(NetworkProtocol.MSG_SUBMIT_ANSWER, {
			"round_index": match_controller.current_round_index,
			"answer": answer
		})

func _on_controller_countdown_started(round_num: int, total_rounds: int) -> void:
	ui_countdown_started.emit(round_num, total_rounds)
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		NetworkSession.send_to_all("countdown_start", {
			"round_num": round_num,
			"total_rounds": total_rounds
		})

func _on_controller_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
	ui_round_started.emit(round_num, challenge, duration)
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		NetworkSession.send_to_all(NetworkProtocol.MSG_ROUND_START, {
			"round_num": round_num,
			"duration": duration,
			"challenge": challenge.to_dict()
		})

func _on_controller_time_tick(remaining: float, total: float) -> void:
	ui_time_tick.emit(remaining, total)

func _on_controller_answer_feedback(player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
	ui_answer_feedback.emit(player_id, is_correct, score_delta, details)
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		NetworkSession.send_to_all(NetworkProtocol.MSG_ANSWER_RESULT, {
			"player_id": player_id,
			"is_correct": is_correct,
			"score_delta": score_delta,
			"details": details
		})

func _on_controller_round_ended(round_num: int, scores: Dictionary) -> void:
	ui_round_ended.emit(round_num, scores)
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		NetworkSession.send_to_all(NetworkProtocol.MSG_ROUND_END, {
			"round_num": round_num,
			"scores": scores
		})

func _on_controller_match_ended(results: Dictionary) -> void:
	last_match_results = results
	ui_match_ended.emit(results)
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_END, {
			"results": results
		})

func _on_network_packet_received(sender_id: int, msg_type: String, data: Dictionary) -> void:
	match msg_type:
		NetworkProtocol.MSG_SUBMIT_ANSWER:
			if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				var round_idx = data.get("round_index", -1)
				if round_idx == match_controller.current_round_index:
					var ans = data.get("answer", null)
					match_controller.submit_player_answer(sender_id, ans)
				else:
					push_warning("Rejected stale answer from peer %d for round %d (current %d)" % [sender_id, round_idx, match_controller.current_round_index])

		NetworkProtocol.MSG_MATCH_START:
			current_game_mode = GameConfig.GameMode.MULTIPLAYER_CLIENT
			var total_r = data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS)
			var pids_array = data.get("player_ids", [1, NetworkSession.get_local_id()])
			var pids: Array[int] = []
			for p in pids_array:
				pids.append(int(p))
			match_controller.initialize_match(current_game_mode, total_r, pids)
			SceneRouter.goto_game()

		"countdown_start":
			var rnum = data.get("round_num", 1)
			var tot = data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS)
			ui_countdown_started.emit(rnum, tot)

		NetworkProtocol.MSG_ROUND_START:
			var rnum = data.get("round_num", 1)
			var dur = float(data.get("duration", 8.0))
			var ch_dict = data.get("challenge", {})
			match_controller.set_client_round(rnum - 1, ch_dict, dur)
			ui_round_started.emit(rnum, match_controller.current_challenge, dur)

		NetworkProtocol.MSG_ANSWER_RESULT:
			var pid = data.get("player_id", 0)
			var is_corr = data.get("is_correct", false)
			var delta_sc = data.get("score_delta", 0)
			var det = data.get("details", "")
			ui_answer_feedback.emit(pid, is_corr, delta_sc, det)

		NetworkProtocol.MSG_ROUND_END:
			var rnum = data.get("round_num", 1)
			var scores = data.get("scores", {})
			ui_round_ended.emit(rnum, scores)

		NetworkProtocol.MSG_MATCH_END:
			last_match_results = data.get("results", {})
			ui_match_ended.emit(last_match_results)
			SceneRouter.goto_results()

func _on_peer_disconnected(peer_id: int) -> void:
	if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		push_warning("Client peer %d disconnected during match!" % peer_id)

func _on_server_disconnected() -> void:
	push_warning("Disconnected from host!")
	SceneRouter.goto_main_menu()
