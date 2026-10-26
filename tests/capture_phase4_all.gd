extends Node

const SCENE_MENU = "res://scenes/main/MainMenu.tscn"
const SCENE_GAME = "res://scenes/game/GameScreen.tscn"
const SCENE_RESULTS = "res://scenes/game/MatchResults.tscn"

func _ready() -> void:
	print("--- STARTING PHASE 4 COMPREHENSIVE VISUAL CAPTURE ---")
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("docs/screenshots"):
		dir.make_dir_recursive("docs/screenshots")
		
	var rng = RandomNumberGenerator.new()
	rng.seed = 2026
	
	# 1. Main Menu
	var menu_scene = load(SCENE_MENU)
	var menu = menu_scene.instantiate()
	add_child(menu)
	await _wait_frames(10)
	_save_screen("docs/screenshots/main_menu.png")
	menu.queue_free()
	await _wait_frames(4)
	
	# 2. Match Start & Challenge Families
	var game_scene = load(SCENE_GAME)
	var game_scr = game_scene.instantiate()
	add_child(game_scr)
	await _wait_frames(6)
	
	var cv = game_scr.get_node("%ChallengeView")
	
	# Match Start / First Challenge
	var ch_start = ChallengeGenerator.generate_side_comparison(rng, 0, 1)
	cv.load_challenge(ch_start)
	await _wait_frames(6)
	_save_screen("docs/screenshots/match_start.png")
	
	# Family A: Almost Right (Quantity Estimation)
	var ch_a = ChallengeGenerator.generate_estimation_count(rng, 1, 2)
	cv.load_challenge(ch_a)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_a_estimation.png")
	
	# Family B: Which Side (Side Comparison)
	var ch_b = ChallengeGenerator.generate_side_comparison(rng, 2, 2)
	cv.load_challenge(ch_b)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_b_which_side.png")
	
	# Family C: Target Rush (Color Target)
	var ch_c = ChallengeGenerator.generate_color_target(rng, 3, 2)
	cv.load_challenge(ch_c)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_c_target_rush.png")
	
	# Family D: Shape Hunter (Shape Target)
	var ch_d = ChallengeGenerator.generate_shape_target(rng, 4, 2)
	cv.load_challenge(ch_d)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_d_shape_hunter.png")
	
	# Family E: Don't Tap - GO stimulus
	var ch_e_go = ChallengeGenerator.generate_dont_tap_rule(rng, 5, 2)
	ch_e_go.visual_data["should_withhold"] = false
	ch_e_go.instruction = "ALL CLEAR! NO RED — TAP FAST!"
	cv.load_challenge(ch_e_go)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_e_dont_tap_go.png")
	
	# Family E: Don't Tap - NO-GO stimulus
	var ch_e_nogo = ChallengeGenerator.generate_dont_tap_rule(rng, 6, 2)
	ch_e_nogo.visual_data["should_withhold"] = true
	ch_e_nogo.instruction = "DANGER! RED IS PRESENT — DO NOT TAP!"
	cv.load_challenge(ch_e_nogo)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_e_dont_tap_nogo.png")
	
	# Family F: Brain Twist (Combined Conditional)
	var ch_f = ChallengeGenerator.generate_combined_conditional(rng, 7, 2)
	cv.load_challenge(ch_f)
	await _wait_frames(6)
	_save_screen("docs/screenshots/family_f_brain_twist.png")
	
	# Correct Answer Feedback
	game_scr._on_answer_feedback(1, true, 1350, "All targets discovered accurately!")
	await _wait_frames(6)
	_save_screen("docs/screenshots/feedback_correct.png")
	
	# Incorrect Answer Feedback
	game_scr._on_answer_feedback(1, false, -150, "Incorrect selection submitted")
	await _wait_frames(6)
	_save_screen("docs/screenshots/feedback_incorrect.png")
	
	# Don't Tap Success (Restraint)
	game_scr._on_answer_feedback(1, true, 1000, "Withheld until timeout (Correct)")
	await _wait_frames(6)
	_save_screen("docs/screenshots/dont_tap_success.png")
	
	# Don't Tap Failure (Impulse fault)
	game_scr._on_answer_feedback(1, false, -150, "Don't Tap challenge: Impulsive tap registered")
	await _wait_frames(6)
	_save_screen("docs/screenshots/dont_tap_failure.png")
	
	game_scr.queue_free()
	await _wait_frames(4)
	
	# 3. Match Results Screen
	GameManager.last_match_results = {
		"winner_id": 1,
		"is_tie": false,
		"highest_score": 9450,
		"total_rounds": 10,
		"player_stats": {
			1: {
				"total_score": 9450,
				"accuracy": 90.0,
				"avg_response_time": 1.34,
				"correct_count": 9,
				"incorrect_count": 1,
				"missed_count": 0,
				"max_streak": 5,
				"best_round_score": 1450,
				"best_round_index": 3
			}
		}
	}
	var res_scene = load(SCENE_RESULTS)
	var res_scr = res_scene.instantiate()
	add_child(res_scr)
	await _wait_frames(8)
	_save_screen("docs/screenshots/match_results.png")
	res_scr.queue_free()
	await _wait_frames(4)
	
	# 4. Rematch State
	GameManager.start_single_player_match(10)
	var rematch_game = game_scene.instantiate()
	add_child(rematch_game)
	await _wait_frames(6)
	_save_screen("docs/screenshots/rematch_fresh_game.png")
	rematch_game.queue_free()
	await _wait_frames(4)
	
	# 5. Narrow Viewport Layout (360 x 640)
	DisplayServer.window_set_size(Vector2i(360, 640))
	get_viewport().size = Vector2i(360, 640)
	var game_narrow = game_scene.instantiate()
	add_child(game_narrow)
	game_narrow.get_node("%ChallengeView").load_challenge(ch_b)
	await _wait_frames(10)
	_save_screen("docs/screenshots/layout_narrow.png")
	game_narrow.queue_free()
	await _wait_frames(4)
	
	# 6. Wide Viewport Layout (600 x 800)
	DisplayServer.window_set_size(Vector2i(600, 800))
	get_viewport().size = Vector2i(600, 800)
	var game_wide = game_scene.instantiate()
	add_child(game_wide)
	game_wide.get_node("%ChallengeView").load_challenge(ch_f)
	await _wait_frames(10)
	_save_screen("docs/screenshots/layout_wide.png")
	game_wide.queue_free()
	
	print(">> ALL PHASE 4 SCREENSHOTS CAPTURED SUCCESSFULLY <<")
	get_tree().quit(0)

func _wait_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func _save_screen(path: String) -> void:
	var vp = get_viewport()
	if vp != null:
		var tex = vp.get_texture()
		if tex != null:
			var img = tex.get_image()
			if img != null:
				var err = img.save_png(path)
				if err == OK:
					print("SUCCESS: Saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
				else:
					print("ERROR: Failed to save %s (code %d)" % [path, err])
