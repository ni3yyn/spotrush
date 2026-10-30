class_name TestUiSceneFlow
extends RefCounted

const SCENE_MAIN_MENU: String = "res://scenes/main/MainMenu.tscn"
const SCENE_GAME: String = "res://scenes/game/GameScreen.tscn"
const SCENE_RESULTS: String = "res://scenes/game/MatchResults.tscn"
const SCENE_LOCAL_LOBBY: String = "res://scenes/multiplayer/LocalLobby.tscn"
const SCENE_SETTINGS: String = "res://scenes/settings/SettingsScreen.tscn"

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	# Test 1: MainMenu scene instantiation and controls
	var menu_scene = load(SCENE_MAIN_MENU)
	if menu_scene != null:
		var menu = menu_scene.instantiate()
		if menu.has_node("%BtnSolo") and menu.has_node("%BtnMultiplayer") \
				and menu.has_node("%BtnHowToPlay") and menu.has_node("%BtnSettings") \
				and not menu.has_node("%ModalSettings"):
			passed += 1
		else:
			failed += 1
			errors.append("MainMenu missing expected buttons or still contains the old settings modal")
		menu.free()
	else:
		failed += 1
		errors.append("Failed to load MainMenu.tscn")
		
	# Test 2: LocalLobby scene instantiation and controls
	var lobby_scene = load(SCENE_LOCAL_LOBBY)
	if lobby_scene != null:
		var lobby = lobby_scene.instantiate()
		if lobby.has_node("%BtnStartHost") and lobby.has_node("%BtnConnect") and lobby.has_node("%BtnLaunchMatch"):
			passed += 1
		else:
			failed += 1
			errors.append("LocalLobby missing host/connect controls")
		lobby.free()
	else:
		failed += 1
		errors.append("Failed to load LocalLobby.tscn")
		
	# Test 3: GameScreen & ChallengeView scene binding
	var game_scene = load(SCENE_GAME)
	if game_scene != null:
		var game_scr = game_scene.instantiate()
		if game_scr.has_node("%ChallengeView") and game_scr.has_node("%TimerBar") and game_scr.has_node("%LblRound"):
			passed += 1
		else:
			failed += 1
			errors.append("GameScreen missing ChallengeView, TimerBar, or LblRound")
		game_scr.free()
	else:
		failed += 1
		errors.append("Failed to load GameScreen.tscn")

	# Test 4: Settings is a separate full-screen scene, not a MainMenu modal.
	var settings_scene = load(SCENE_SETTINGS)
	if settings_scene != null:
		var settings_screen = settings_scene.instantiate()
		if settings_screen.get_script() != null and settings_screen.has_method("handle_back") \
				and settings_screen.anchor_right == 1.0 and settings_screen.anchor_bottom == 1.0 \
				and not settings_screen.has_node("ModalSettings"):
			passed += 1
		else:
			failed += 1
			errors.append("SettingsScreen missing its full-screen scene script or anchors")
		settings_screen.free()
	else:
		failed += 1
		errors.append("Failed to load SettingsScreen.tscn")

	# Test 5: MatchResults scene binding
	var results_scene = load(SCENE_RESULTS)
	if results_scene != null:
		var res_scr = results_scene.instantiate()
		if res_scr.has_node("%LblOutcome") and res_scr.has_node("%BtnRematch") and res_scr.has_node("%BtnMenu"):
			passed += 1
		else:
			failed += 1
			errors.append("MatchResults missing expected labels or buttons")
		res_scr.free()
	else:
		failed += 1
		errors.append("Failed to load MatchResults.tscn")
		
	# Test 6: MatchController progression with 3 rounds and verified results
	var mc = MatchController.new()
	mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 3, [1])
	mc.start_match()
	
	for r in range(3):
		mc.update_process(GameConfig.COUNTDOWN_DURATION + 0.1)
		var ch = mc.current_challenge
		if ch != null:
			var ans = ch.correct_answer
			if ch.input_mode == "tap_targets":
				var targets = []
				var itms = ch.visual_data.get("items", [])
				for i in range(itms.size()):
					if itms[i].get("is_target", false):
						targets.append(i)
				ans = targets
			elif ch.input_mode == "withhold_response":
				ans = "TAP" if not bool(ch.correct_answer) else null
				
			if ans != null:
				mc.submit_player_answer(1, ans)
			else:
				mc.update_process(ch.time_limit + 0.1)
				
		mc.update_process(GameConfig.ROUND_FEEDBACK_DURATION + 0.1)
		
	if mc.current_state == MatchController.MatchState.MATCH_OVER:
		passed += 1
	else:
		failed += 1
		errors.append("MatchController failed to reach MATCH_OVER state")
		
	var results = mc.score_manager.determine_match_result()
	if results.has("highest_score") and results["highest_score"] > 0:
		passed += 1
	else:
		failed += 1
		errors.append("Match results highest_score missing or invalid")
		
	return {
		"name": "UiSceneFlowTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
