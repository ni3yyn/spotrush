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
		NetworkSession.peer_connected.connect(_on_peer_connected_for_resync)
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
		_stamp_duel_deck()

		NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_START, {
				"total_rounds": rounds,
				"player_ids": peers,
				"deck_seed": match_controller.deck_seed(),
				"deck_band": match_controller.deck_start_band()
		})
		if OS.is_debug_build():
				CrashLogger.breadcrumb("[DUEL][NET] TX match_start rounds=%d players=%s deck_seed=%d deck_band=%d" % [
						rounds, str(peers), match_controller.deck_seed(), match_controller.deck_start_band()])

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
		_stamp_duel_deck()

		NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_START, {
				"total_rounds": rounds,
				"player_ids": peers,
				"deck_seed": match_controller.deck_seed(),
				"deck_band": match_controller.deck_start_band()
		})
		if OS.is_debug_build():
				CrashLogger.breadcrumb("[DUEL][NET] TX match_start rounds=%d players=%s deck_seed=%d deck_band=%d" % [
						rounds, str(peers), match_controller.deck_seed(), match_controller.deck_start_band()])

		match_controller.prepare_first_challenge()

## Stamp + forge the duel deck BEFORE match_start goes out, so deck_seed()/
## deck_start_band() below read back the real values that just got baked in
## (not -1/"not forged yet"). A duel deck is a pure curve (adaptive stays
## false - see MatchController._forge_deck()), so the seed + this one anchor
## band fully determine every round: the joining phone reforges the exact
## same deck from these two integers instead of receiving each round's full
## token layout, which is what was blowing past the P2P transport's
## per-packet size limit.
func _stamp_duel_deck() -> void:
		match_controller.challenge_seed = RunDeck.fresh_seed()
		match_controller.challenge_band = clampi(Records.skill_rating(), GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		match_controller.fixed_difficulty_ramp = false
		match_controller.ensure_deck_forged()

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

func _on_controller_countdown_started(round_num: int, total_rounds: int) -> void:
		has_submitted_current_round = false
		next_round_instruction = match_controller.current_challenge.instruction if match_controller.current_challenge != null else ""
		ui_countdown_started.emit(round_num, total_rounds)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				NetworkSession.send_to_all(NetworkProtocol.MSG_COUNTDOWN_START, {
						"round_num": round_num,
						"total_rounds": total_rounds,
						"instruction": next_round_instruction
				})
				if OS.is_debug_build():
						CrashLogger.breadcrumb("[DUEL][NET] TX countdown_start round=%d/%d instruction_chars=%d" % [
								round_num, total_rounds, next_round_instruction.length()])

func _on_controller_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
		has_submitted_current_round = false
		ui_round_started.emit(round_num, challenge, duration)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				# Only the round number + duration travel over the wire - the client
				# already has the same deck_seed/deck_band from match_start and
				# reforges this exact challenge locally (see MatchController.
				# set_client_round()), so no token layout needs to be sent here.
				NetworkSession.send_to_all(NetworkProtocol.MSG_ROUND_START, {
						"round_num": round_num,
						"duration": duration
				})
				if OS.is_debug_build():
						CrashLogger.breadcrumb("[DUEL][NET] TX round_start round=%d duration=%.2f challenge_id=%s" % [
								round_num, duration, challenge.id if challenge != null else "?"])

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
				if OS.is_debug_build():
						CrashLogger.breadcrumb("[DUEL][NET] TX answer_result player=%d correct=%s delta=%d" % [player_id, str(is_correct), score_delta])

func _on_controller_round_ended(round_num: int, scores: Dictionary) -> void:
		ui_round_ended.emit(round_num, scores)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				NetworkSession.send_to_all(NetworkProtocol.MSG_ROUND_END, {
						"round_num": round_num,
						"scores": scores
				})
				if OS.is_debug_build():
						CrashLogger.breadcrumb("[DUEL][NET] TX round_end round=%d scores=%s" % [round_num, str(scores)])

func _on_controller_match_ended(results: Dictionary) -> void:
		last_match_results = results
		ui_match_ended.emit(results)
		if current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
				NetworkSession.send_to_all(NetworkProtocol.MSG_MATCH_END, {
						"results": results
				})
				if OS.is_debug_build():
						CrashLogger.breadcrumb("[DUEL][NET] TX match_end")

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
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX match_start sender=%d bytes_deck_seed=%s bytes_deck_band=%s" % [
										sender_id, str(data.get("deck_seed", "?")), str(data.get("deck_band", "?"))])
						current_game_mode = GameConfig.GameMode.MULTIPLAYER_CLIENT
						var total_r = data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS)
						var pids_array = data.get("player_ids", [1, NetworkSession.get_local_id()])
						var pids: Array[int] = []
						for p in pids_array:
								pids.append(int(p))
						match_controller.initialize_match(current_game_mode, total_r, pids)
						# Mirror the host's duel deck from these two small integers instead of
						# the full per-round token layout - see MatchController._forge_deck()
						# and set_client_round().
						match_controller.challenge_seed = int(data.get("deck_seed", -1))
						match_controller.challenge_band = int(data.get("deck_band", -1))
						SceneRouter.goto_game()

				NetworkProtocol.MSG_COUNTDOWN_START:
						var rnum = int(data.get("round_num", 1))
						var tot = int(data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS))
						next_round_instruction = str(data.get("instruction", ""))
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX countdown_start sender=%d round=%d/%d instruction_chars=%d" % [
										sender_id, rnum, tot, next_round_instruction.length()])
						ui_countdown_started.emit(rnum, tot)

				NetworkProtocol.MSG_ROUND_START:
						var rnum = data.get("round_num", 1)
						var dur = float(data.get("duration", 8.0))
						_client_ui_tick_accumulator = 0.0
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX round_start sender=%d round=%s duration=%.2f" % [sender_id, str(rnum), dur])
						# set_client_round() reforges this round locally from the deck_seed/
						# deck_band stamped at match_start (or match_resync) and emits
						# MatchController's own round_started signal, which
						# _on_controller_round_started() (connected in _ready) already turns
						# into ui_round_started for the UI - do not also emit it here, that
						# used to fire GameScreen._on_round_started() TWICE per round on the
						# joining player's device and is what originally left the joiner's
						# playfield looking empty behind the countdown overlay.
						match_controller.set_client_round(int(rnum) - 1, dur)

				NetworkProtocol.MSG_REQUEST_RESYNC:
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX request_resync sender=%d" % sender_id)
						if NetworkSession.is_host():
								_send_match_resync(sender_id)

				NetworkProtocol.MSG_MATCH_RESYNC:
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX match_resync sender=%d round=%s state=%s" % [
										sender_id, str(data.get("round_num", "?")), str(data.get("state", "?"))])
						_apply_match_resync(data)

				NetworkProtocol.MSG_ANSWER_RESULT:
						var pid = data.get("player_id", 0)
						var is_corr = data.get("is_correct", false)
						var delta_sc = data.get("score_delta", 0)
						var det = data.get("details", "")
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX answer_result sender=%d player=%s correct=%s delta=%s" % [
										sender_id, str(pid), str(is_corr), str(delta_sc)])
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
						var scores = data.get("scores", {})
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX round_end sender=%d round=%s scores=%s" % [sender_id, str(rnum), str(scores)])
						if current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
								match_controller.apply_authoritative_scores(scores)
						ui_round_ended.emit(rnum, scores)

				NetworkProtocol.MSG_MATCH_END:
						if OS.is_debug_build():
								CrashLogger.breadcrumb("[DUEL][NET] RX match_end sender=%d" % sender_id)
						last_match_results = data.get("results", {})
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

## A device just connected to us. If we are already mid-duel (this device is
## reconnecting after a drop, or somehow connected_peers fired after the
## match had already started), push it the full state immediately instead of
## waiting for it to notice nothing is happening and ask - this is the push
## half of the fix for a joiner being stuck on the lobby's "Connected" screen
## while we're already playing. See MSG_REQUEST_RESYNC for the pull half.
func _on_peer_connected_for_resync(peer_id: int) -> void:
		if not NetworkSession.is_host() or current_game_mode != GameConfig.GameMode.MULTIPLAYER_HOST:
				return
		if match_controller.current_state == MatchController.MatchState.IDLE \
						or match_controller.current_state == MatchController.MatchState.MATCH_OVER:
				return
		if OS.is_debug_build():
				CrashLogger.breadcrumb("[DUEL][NET] peer %d connected mid-duel (state=%d) - pushing resync" % [peer_id, match_controller.current_state])
		_send_match_resync(peer_id)

## Host-side: answer a join/reconnect/request_resync with everything the
## client needs to catch up - players, scores, the duel's deck_seed/band
## (so it can reforge the current round locally) and where we are in it.
## Kept to a handful of ints/floats + one small score dictionary, nowhere
## near the P2P transport's per-packet ceiling that the old full-challenge
## broadcasts used to blow past.
func _send_match_resync(peer_id: int) -> void:
		if match_controller.current_state == MatchController.MatchState.IDLE \
						or match_controller.current_state == MatchController.MatchState.MATCH_OVER:
				return
		var scores: Dictionary = {}
		for pid in match_controller.player_ids:
				scores[pid] = match_controller.score_manager.get_player_score(pid)
		var remaining: float = 0.0
		if match_controller.current_state == MatchController.MatchState.ACTIVE_ROUND:
				remaining = maxf(0.0, match_controller.round_duration - match_controller.round_timer)
		NetworkSession.send_packet(peer_id, NetworkProtocol.MSG_MATCH_RESYNC, {
				"total_rounds": match_controller.total_rounds,
				"player_ids": match_controller.player_ids,
				"deck_seed": match_controller.deck_seed(),
				"deck_band": match_controller.deck_start_band(),
				"round_num": match_controller.current_round_index + 1,
				"round_index": match_controller.current_round_index,
				"duration": match_controller.round_duration,
				"remaining": remaining,
				"state": match_controller.current_state,
				"scores": scores
		})
		if OS.is_debug_build():
				CrashLogger.breadcrumb("[DUEL][NET] TX match_resync -> peer=%d round=%d/%d state=%d remaining=%.2f" % [
						peer_id, match_controller.current_round_index + 1, match_controller.total_rounds,
						match_controller.current_state, remaining])

## Client-side: land on the game screen already caught up, whatever state the
## host happens to be in. Scores and the current round are restored exactly;
## a resync that lands mid-COUNTDOWN or mid-FEEDBACK doesn't try to replay
## that transient UI state - it simply waits for the host's next
## countdown_start/round_start broadcast, which arrives moments later either
## way and is now the single source of truth for what the player sees next.
func _apply_match_resync(data: Dictionary) -> void:
		current_game_mode = GameConfig.GameMode.MULTIPLAYER_CLIENT
		is_daily_match = false
		daily_seed_value = -1
		_clear_challenge_state()
		has_submitted_current_round = false

		var total_r := int(data.get("total_rounds", GameConfig.DEFAULT_TOTAL_ROUNDS))
		var pids_array = data.get("player_ids", [1, NetworkSession.get_local_id()])
		var pids: Array[int] = []
		for p in pids_array:
				pids.append(int(p))
		match_controller.initialize_match(current_game_mode, total_r, pids)
		match_controller.challenge_seed = int(data.get("deck_seed", -1))
		match_controller.challenge_band = int(data.get("deck_band", -1))
		match_controller.apply_authoritative_scores(data.get("scores", {}))

		var active_scene := get_tree().current_scene
		var already_in_game := active_scene != null and active_scene.scene_file_path == SceneRouter.SCENE_GAME
		if not already_in_game and not SceneRouter.is_transitioning:
				SceneRouter.goto_game()

		var state := int(data.get("state", MatchController.MatchState.ACTIVE_ROUND))
		if state == MatchController.MatchState.ACTIVE_ROUND:
				var round_idx := int(data.get("round_index", 0))
				var duration := float(data.get("duration", 8.0))
				var remaining := float(data.get("remaining", duration))
				_client_ui_tick_accumulator = 0.0
				match_controller.set_client_round(round_idx, duration)
				# Fast-forward the local clock to match how much of the round the
				# host has already burned through, so the timer/HUD aren't ~remaining
				# seconds ahead of the host's authoritative deadline.
				match_controller.round_timer = clampf(duration - remaining, 0.0, duration)

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
