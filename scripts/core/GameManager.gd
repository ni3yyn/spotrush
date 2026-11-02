extends Node

const Records = preload("res://scripts/core/Records.gd")

var match_controller: MatchController = MatchController.new()
var current_game_mode: GameConfig.GameMode = GameConfig.GameMode.SINGLE_PLAYER
var last_match_results: Dictionary = {}
var next_round_instruction: String = ""
var _client_ui_tick_accumulator: float = 0.0
const CLIENT_UI_TICK_INTERVAL: float = 0.05
var _last_perf_frame_log_usec: int = 0

# Daily Spot state: a solo match, but seeded from the date so everyone plays the
# same 10 rounds, recorded once per day by the results screen.
var is_daily_match: bool = false
var daily_seed_value: int = -1

# Rival Codes state (v17): a solo match forged from a friend's (or your own)
# challenge code. Pure fixed curve anchored at the code's band, so the sender
# and the receiver deal byte-identical rounds and compare scores afterwards.
var is_challenge_match: bool = false
var challenge_seed_value: int = -1
var challenge_band_value: int = -1
var challenge_code_value: String = ""

# Solo matches are queued by the menu and started only after GameScreen has connected
# its UI signals. This prevents the opening countdown signal from being emitted while
# the menu is still active and lets the first challenge animate into view normally.
var _pending_single_player_rounds: int = -1

# Multiplayer host matches use the same queue: LocalLobby queues the duel and
# navigates, GameScreen prepares it (and tells the friend's phone to load the
# arena) once its UI is connected, then starts the countdown on its own beat.
var _pending_multiplayer_host_rounds: int = -1

func queue_single_player_start(rounds: int) -> void:
		# Update the mode now so GameScreen builds the correct solo HUD before the
		# queued match is initialized on the next scene.
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		_pending_single_player_rounds = maxi(1, rounds)
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()

func consume_pending_single_player_start() -> int:
		var rounds: int = _pending_single_player_rounds
		_pending_single_player_rounds = -1
		return rounds

## Queue today's Daily Spot: a solo sprint whose challenge series is seeded from
## the calendar date, so every player faces the same rounds. Reuses the solo queue
## so GameScreen presents it exactly like any other solo match.
func queue_daily_start() -> void:
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		_pending_single_player_rounds = GameConfig.DAILY_ROUNDS
		is_daily_match = true
		daily_seed_value = Records.daily_seed()
		_clear_challenge_state()

## Queue a run from a typed or pasted challenge code. The code is parsed once
## here; from this point on the match is an ordinary fixed-curve solo run whose
## seed happens to come from a friend. Returns true when the code was valid.
func queue_challenge_start(code: String) -> bool:
		var parsed := ChallengeCodes.parse(code)
		if parsed.is_empty():
				return false
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		_pending_single_player_rounds = int(parsed["rounds"])
		is_daily_match = false
		daily_seed_value = -1
		is_challenge_match = true
		challenge_seed_value = int(parsed["seed"])
		challenge_band_value = int(parsed["band"])
		challenge_code_value = str(parsed["display"])
		return true

func _clear_challenge_state() -> void:
		is_challenge_match = false
		challenge_seed_value = -1
		challenge_band_value = -1
		challenge_code_value = ""

func queue_multiplayer_host_start(rounds: int) -> void:
		current_game_mode = GameConfig.GameMode.MULTIPLAYER_HOST
		_pending_multiplayer_host_rounds = maxi(1, rounds)

func consume_pending_multiplayer_host_start() -> int:
		var rounds: int = _pending_multiplayer_host_rounds
		_pending_multiplayer_host_rounds = -1
		return rounds

## Build the solo match state and pre-generate the opening challenge WITHOUT
## starting the countdown. Lets GameScreen deal the first round behind the
## closed transition curtain and present it in one clean reveal (no placeholder
## flash, no mid-reveal reload).
func prepare_single_player_match(rounds: int) -> void:
		has_submitted_current_round = false
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		match_controller.initialize_match(current_game_mode, rounds, [1])
		# Daily Spot: stamp the fixed seed + fixed ramp AFTER initialize_match
		# resets them, but BEFORE the first challenge is dealt.
		match_controller.challenge_seed = daily_seed_value if is_daily_match else -1
		match_controller.fixed_difficulty_ramp = is_daily_match
		# Rival Codes: stamp the code's seed + anchor band the same way - after
		# the reset, before the first round is forged.
		if not is_daily_match:
				match_controller.challenge_seed = challenge_seed_value if is_challenge_match else -1
				match_controller.challenge_band = challenge_band_value if is_challenge_match else -1
		match_controller.prepare_first_challenge()

## Start the countdown for a match prepared with prepare_single_player_match().
func start_prepared_match() -> void:
		if match_controller.current_state == MatchController.MatchState.IDLE:
				match_controller.start_match()

## UI-only holds used by the first-time practice and instruction preview.
func pause_round_countdown() -> void:
		match_controller.pause_countdown()

func resume_round_countdown() -> void:
		match_controller.resume_countdown()

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
		# Debug-only frame-gap probe. It does not alter timing; it gives device logs
		# a scene label whenever the main loop exceeds the 60 FPS frame budget (with a small tolerance).
		if OS.is_debug_build() and delta >= 0.018:
				var now_usec := Time.get_ticks_usec()
				if now_usec - _last_perf_frame_log_usec >= 300000:
						_last_perf_frame_log_usec = now_usec
						var scene_name := "none"
						var active_scene := get_tree().current_scene
						if active_scene != null:
								scene_name = active_scene.name
						print("[PERF] Frame gap %.1f ms | scene: %s" % [delta * 1000.0, scene_name])
		# While a confirmation sheet is up (v19), or the app sits in the
		# background (v20: Home button, phone call), a solo run's clock holds
		# its breath - interruptions should never cost you the round. Duels
		# stay live: both phones must keep the same beat, and the rival on the
		# other screen is not waiting on this dialog.
		if (NeuDialog.is_open() or AppLifecycle.is_background) \
						and current_game_mode == GameConfig.GameMode.SINGLE_PLAYER:
				return
		if current_game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
				match_controller.update_process(delta)
		else:
				if match_controller.current_state == MatchController.MatchState.ACTIVE_ROUND:
						match_controller.round_timer += delta
						var rem := maxf(0.0, match_controller.round_duration - match_controller.round_timer)
						_client_ui_tick_accumulator += delta
						if _client_ui_tick_accumulator >= CLIENT_UI_TICK_INTERVAL or rem <= 0.0:
								_client_ui_tick_accumulator = fmod(_client_ui_tick_accumulator, CLIENT_UI_TICK_INTERVAL)
								ui_time_tick.emit(rem, match_controller.round_duration)

var has_submitted_current_round: bool = false

func start_single_player_match(rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS) -> void:
		has_submitted_current_round = false
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()
		match_controller.initialize_match(current_game_mode, rounds, [1])
		match_controller.start_match()

func start_multiplayer_host_match(rounds: int = GameConfig.DEFAULT_TOTAL_ROUNDS) -> void:
		has_submitted_current_round = false
		current_game_mode = GameConfig.GameMode.MULTIPLAYER_HOST
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()
		var peers: Array[int] = [1]
		for p in NetworkSession.connected_peers:
				peers.append(p)
		match_controller.initialize_match(current_game_mode, rounds, peers)

		NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_START, {
				"total_rounds": rounds,
				"player_ids": peers
		})

		match_controller.start_match()

## The queued (lobby -> game) variant: build the match state, tell the friend's
## phone to load the arena, and deal the opening challenge WITHOUT starting the
## countdown. start_prepared_match() fires once GameScreen is fully visible, so
## the GET READY card is never emitted behind the transition curtain.
func prepare_multiplayer_host_match(rounds: int) -> void:
		has_submitted_current_round = false
		current_game_mode = GameConfig.GameMode.MULTIPLAYER_HOST
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()
		var peers: Array[int] = [1]
		for p in NetworkSession.connected_peers:
				peers.append(p)
		match_controller.initialize_match(current_game_mode, rounds, peers)

		NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_START, {
				"total_rounds": rounds,
				"player_ids": peers
		})

		match_controller.prepare_first_challenge()

func submit_answer(answer: Variant) -> void:
		if has_submitted_current_round:
				return
		has_submitted_current_round = true

		if current_game_mode == GameConfig.GameMode.SINGLE_PLAYER or current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				match_controller.submit_player_answer(1, answer)
		elif current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
				NetworkSession.send_to_server(NetworkProtocol.MSG_SUBMIT_ANSWER, {
						"round_index": match_controller.current_round_index,
						"answer": answer
				})

func skip_feedback() -> void:
		if current_game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
				match_controller.skip_feedback()

func _duel_trace(message: String) -> void:
		var line := "[DUEL][GAME] " + message
		var logger := get_node_or_null("/root/CrashLogger")
		if logger != null and logger.has_method("breadcrumb"):
				logger.call("breadcrumb", line)
		else:
				print(line)

func _challenge_to_wire(challenge: ChallengeDefinition) -> Dictionary:
		if challenge == null:
				return {}
		return challenge.to_dict()

func _decode_network_challenge(data: Dictionary, message_name: String, round_num: int) -> Dictionary:
		var raw_json: String = str(data.get("challenge_json", ""))
		if not raw_json.is_empty():
				var parsed: Variant = JSON.parse_string(raw_json)
				if parsed is Dictionary:
					var json_challenge: Dictionary = parsed
					if not json_challenge.is_empty():
						_duel_trace("RX %s decoded JSON challenge round=%d bytes=%d id=%s type=%s keys=%s" % [
							message_name, round_num, raw_json.to_utf8_buffer().size(),
							str(json_challenge.get("id", "")), str(json_challenge.get("type", "")), str(json_challenge.keys())
						])
						return json_challenge
				_duel_trace("WARN %s challenge_json parse failed or empty round=%d bytes=%d; trying Dictionary fallback" % [
				message_name, round_num, raw_json.to_utf8_buffer().size()
				])
		var raw_dictionary: Variant = data.get("challenge", {})
		if raw_dictionary is Dictionary:
				var fallback: Dictionary = raw_dictionary
				_duel_trace("RX %s using Dictionary fallback round=%d id=%s type=%s keys=%s" % [
					message_name, round_num, str(fallback.get("id", "")),
					str(fallback.get("type", "")), str(fallback.keys())
				])
				return fallback
		_duel_trace("ERROR %s has no usable challenge payload round=%d data_keys=%s" % [message_name, round_num, str(data.keys())])
		return {}

func _ensure_client_match_state(total_rounds_hint: int = -1) -> void:
		if NetworkSession.is_host():
				return
		current_game_mode = GameConfig.GameMode.MULTIPLAYER_CLIENT
		if match_controller.game_mode != GameConfig.GameMode.MULTIPLAYER_CLIENT:
				var safe_rounds: int = maxi(1, total_rounds_hint if total_rounds_hint > 0 else GameConfig.DEFAULT_TOTAL_ROUNDS)
				var local_id: int = NetworkSession.get_local_id()
				if local_id <= 1:
					local_id = 2
				_duel_trace("RECOVERY reinitializing client controller mode=%s rounds=%d local_id=%d" % [str(match_controller.game_mode), safe_rounds, local_id])
				match_controller.initialize_match(GameConfig.GameMode.MULTIPLAYER_CLIENT, safe_rounds, [1, local_id])

func _on_controller_countdown_started(round_num: int, total_rounds: int) -> void:
		has_submitted_current_round = false
		next_round_instruction = match_controller.current_challenge.instruction if match_controller.current_challenge != null else ""
		ui_countdown_started.emit(round_num, total_rounds)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				var challenge_data: Dictionary = _challenge_to_wire(match_controller.current_challenge)
				var challenge_json: String = JSON.stringify(challenge_data)
				_duel_trace("HOST countdown TX round=%d/%d state=%s challenge_id=%s type=%s valid=%s instruction_chars=%d duration=%.2f json_bytes=%d peers=%s" % [
						round_num, total_rounds, str(match_controller.current_state),
						str(challenge_data.get("id", "")), str(challenge_data.get("type", "")),
						str(match_controller.current_challenge != null and match_controller.current_challenge.is_valid()),
						next_round_instruction.length(), match_controller.round_duration,
						challenge_json.to_utf8_buffer().size(), str(NetworkSession.connected_peers)
				])
				NetworkSession.send_to_all(NetworkProtocol.MSG_COUNTDOWN_START, {
						"round_num": round_num,
						"total_rounds": total_rounds,
						"instruction": next_round_instruction,
						"duration": match_controller.round_duration,
						"challenge": challenge_data,
						"challenge_json": challenge_json
				})

func _on_controller_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
		has_submitted_current_round = false
		_duel_trace("CONTROLLER round_started round=%d mode=%s state=%s challenge_id=%s type=%s valid=%s duration=%.2f" % [
			round_num, str(current_game_mode), str(match_controller.current_state),
			challenge.id if challenge != null else "<null>", challenge.type if challenge != null else "<null>",
			str(challenge != null and challenge.is_valid()), duration
		])
		ui_round_started.emit(round_num, challenge, duration)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				var challenge_data: Dictionary = _challenge_to_wire(challenge)
				var challenge_json: String = JSON.stringify(challenge_data)
				_duel_trace("HOST ROUND_START TX round=%d id=%s type=%s valid=%s duration=%.2f json_bytes=%d peers=%s" % [
						round_num, str(challenge_data.get("id", "")), str(challenge_data.get("type", "")),
						str(challenge != null and challenge.is_valid()), duration,
						challenge_json.to_utf8_buffer().size(), str(NetworkSession.connected_peers)
				])
				NetworkSession.send_to_all(NetworkProtocol.MSG_ROUND_START, {
						"round_num": round_num,
						"duration": duration,
						"challenge": challenge_data,
						"challenge_json": challenge_json
				})

func _on_controller_time_tick(remaining: float, total: float) -> void:
		ui_time_tick.emit(remaining, total)

func _on_controller_answer_feedback(player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
		ui_answer_feedback.emit(player_id, is_correct, score_delta, details)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				# Scoring 2.0: ship the round breakdown + live streak so the
				# joining phone's HUD shows the same math (combo tier, grade).
				NetworkSession.send_to_all(NetworkProtocol.MSG_ANSWER_RESULT, {
						"player_id": player_id,
						"is_correct": is_correct,
						"score_delta": score_delta,
						"details": details,
						"breakdown": match_controller.score_manager.get_last_breakdown(player_id),
						"streak": match_controller.score_manager.get_streak(player_id)
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
						_duel_trace("RX MATCH_START sender=%d mode_before=%s data_keys=%s total_rounds=%s player_ids=%s" % [
							sender_id, str(current_game_mode), str(data.keys()),
							str(data.get("total_rounds", "?")), str(data.get("player_ids", []))
						])
						if NetworkSession.is_host():
							push_warning("[DUEL][GAME] Host unexpectedly received MATCH_START from peer %d" % sender_id)
							return
						current_game_mode = GameConfig.GameMode.MULTIPLAYER_CLIENT
						has_submitted_current_round = false
						var total_r: int = maxi(1, int(data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS)))
						var pids_array = data.get("player_ids", [1, NetworkSession.get_local_id()])
						var pids: Array[int] = []
						for p in pids_array:
								pids.append(int(p))
						if not 1 in pids:
								pids.push_front(1)
						var local_peer_id: int = NetworkSession.get_local_id()
						if local_peer_id > 1 and not local_peer_id in pids:
								pids.append(local_peer_id)
						match_controller.initialize_match(current_game_mode, total_r, pids)
						_duel_trace("MATCH_START applied sender=%d mode=%s controller_mode=%s rounds=%d players=%s local=%d" % [
							sender_id, str(current_game_mode), str(match_controller.game_mode), total_r, str(pids), local_peer_id
						])
						SceneRouter.goto_game()

				NetworkProtocol.MSG_COUNTDOWN_START:
						if NetworkSession.is_host():
							push_warning("[DUEL][GAME] Host received unexpected COUNTDOWN_START from peer %d" % sender_id)
							return
						var rnum: int = maxi(1, int(data.get("round_num", 1)))
						var tot: int = maxi(1, int(data.get("total_rounds", match_controller.total_rounds)))
						_ensure_client_match_state(tot)
						var challenge_data: Dictionary = _decode_network_challenge(data, "COUNTDOWN_START", rnum)
						var challenge_duration: float = float(data.get("duration", 8.0))
						_duel_trace("CLIENT COUNTDOWN handling sender=%d current_mode=%s controller_mode=%s current_round=%d state=%s instruction_chars=%d challenge_keys=%s" % [
							sender_id, str(current_game_mode), str(match_controller.game_mode),
							match_controller.current_round_index + 1, str(match_controller.current_state),
							str(data.get("instruction", "")).length(), str(challenge_data.keys())
						])
						var countdown_applied: bool = match_controller.set_client_countdown(rnum - 1, challenge_data, challenge_duration)
						if countdown_applied:
							next_round_instruction = match_controller.current_challenge.instruction
							_duel_trace("CLIENT COUNTDOWN APPLIED round=%d state=%s id=%s type=%s" % [
								rnum, str(match_controller.current_state), match_controller.current_challenge.id,
								match_controller.current_challenge.type
							])
							ui_countdown_started.emit(rnum, tot)
						else:
							_duel_trace("CLIENT COUNTDOWN NOT APPLIED round=%d state=%s current_round=%d challenge_id=%s" % [
								rnum, str(match_controller.current_state), match_controller.current_round_index + 1,
								match_controller.current_challenge.id if match_controller.current_challenge != null else "<null>"
							])

				NetworkProtocol.MSG_ROUND_START:
						if NetworkSession.is_host():
							push_warning("[DUEL][GAME] Host received unexpected ROUND_START from peer %d" % sender_id)
							return
						var rnum: int = maxi(1, int(data.get("round_num", 1)))
						var dur: float = float(data.get("duration", 8.0))
						_ensure_client_match_state(match_controller.total_rounds)
						var challenge_data: Dictionary = _decode_network_challenge(data, "ROUND_START", rnum)
						_duel_trace("CLIENT ROUND_START handling sender=%d mode=%s controller_mode=%s state_before=%s round_before=%d duration=%.2f challenge_keys=%s" % [
							sender_id, str(current_game_mode), str(match_controller.game_mode),
							str(match_controller.current_state), match_controller.current_round_index + 1, dur,
							str(challenge_data.keys())
						])
						_client_ui_tick_accumulator = 0.0
						has_submitted_current_round = false
						var round_applied: bool = match_controller.set_client_round(rnum - 1, challenge_data, dur)
						if round_applied:
							_duel_trace("CLIENT ROUND_START APPLIED round=%d state=%s id=%s type=%s" % [
								rnum, str(match_controller.current_state), match_controller.current_challenge.id,
								match_controller.current_challenge.type
							])
						else:
							_duel_trace("CLIENT ROUND_START NOT APPLIED round=%d state=%s current_round=%d current_id=%s" % [
								rnum, str(match_controller.current_state), match_controller.current_round_index + 1,
								match_controller.current_challenge.id if match_controller.current_challenge != null else "<null>"
							])

				NetworkProtocol.MSG_ANSWER_RESULT:
						var pid = data.get("player_id", 0)
						var is_corr = data.get("is_correct", false)
						var delta_sc = data.get("score_delta", 0)
						var det = data.get("details", "")
						if current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
								var cur_sc = match_controller.score_manager.get_player_score(pid)
								match_controller.score_manager.set_player_score(pid, maxi(0, cur_sc + delta_sc))
								# Mirror the host's breakdown + streak so the client's combo
								# meter and score-math card stay live (keys absent on old hosts).
								match_controller.score_manager.apply_remote_round(
										pid,
										data.get("breakdown", {}),
										int(data.get("streak", 0))
								)
						ui_answer_feedback.emit(pid, is_corr, delta_sc, det)

				NetworkProtocol.MSG_ROUND_END:
						var rnum = data.get("round_num", 1)
						var scores: Dictionary = data.get("scores", {})
						if current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
								match_controller.set_client_round_end(scores)
						ui_round_ended.emit(rnum, scores)

				NetworkProtocol.MSG_MATCH_END:
						last_match_results = data.get("results", {})
						if current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
								match_controller.current_state = MatchController.MatchState.MATCH_OVER
						ui_match_ended.emit(last_match_results)
						SceneRouter.goto_results()

## The player quit a run in flight (v19 back flow): hard-stop the controller,
## drop any duel connection and clear one-shot match state. Records are
## untouched - a quit run simply never reaches the results screen.
func abandon_match() -> void:
		match_controller.abort_match()
		has_submitted_current_round = false
		_pending_single_player_rounds = -1
		_pending_multiplayer_host_rounds = -1
		if current_game_mode != GameConfig.GameMode.SINGLE_PLAYER:
				NetworkSession.disconnect_session()
		current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()
		last_match_results = {}

func _on_peer_disconnected(peer_id: int) -> void:
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				push_warning("Client peer %d disconnected during match!" % peer_id)
				match_controller.handle_peer_disconnected(peer_id)

func _on_server_disconnected() -> void:
		push_warning("Disconnected from host!")
		# Was a live duel just severed? Then the joining phone is about to be
		# dumped on the menu - say why, instead of teleporting in silence (v19).
		var duel_live := current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT \
						and match_controller.current_state != MatchController.MatchState.IDLE \
						and match_controller.current_state != MatchController.MatchState.MATCH_OVER
		if duel_live:
				match_controller.abort_match()
				current_game_mode = GameConfig.GameMode.SINGLE_PLAYER
		SceneRouter.goto_main_menu()
		if duel_live:
				_inform_after_arrival("DUEL ENDED",
								"The host left mid-duel. You can open your own room from the FRIENDS menu.",
								"GOT IT")

## Wait out the transition curtain, then put the explanation sheet up on the
## freshly arrived screen.
func _inform_after_arrival(title: String, message: String, ok_text: String) -> void:
		await SceneRouter.wait_until_idle()
		await get_tree().create_timer(0.05).timeout
		NeuDialog.inform(title, message, ok_text)
