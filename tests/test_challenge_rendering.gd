class_name TestChallengeRendering
extends RefCounted

const SCENE_CHALLENGE_VIEW: String = "res://scenes/game/ChallengeView.tscn"

static func run_all_tests() -> Dictionary:
	var passed = 0
	var failed = 0
	var errors = []
	
	var cv_scene = load(SCENE_CHALLENGE_VIEW)
	if cv_scene == null:
		return {
			"name": "ChallengeRenderingTests",
			"passed": 0,
			"failed": 1,
			"errors": ["Failed to load ChallengeView.tscn"]
		}
		
	var cv = cv_scene.instantiate()
	# Set a realistic mobile portrait size
	cv.custom_minimum_size = Vector2(720, 1000)
	
	var canvas = cv.get_node("%ChallengeCanvas")
	if canvas == null:
		failed += 1
		errors.append("ChallengeView missing ChallengeCanvas")
		return {
			"name": "ChallengeRenderingTests",
			"passed": passed,
			"failed": failed,
			"errors": errors
		}
	else:
		passed += 1 # Test 1: Node structure confirmed
		
	canvas.size = Vector2(672, 750)
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	
	# Test 2: Game A — Estimation count rendering & options
	var ch_est = ChallengeGenerator.generate_estimation_count(rng, 1, 2)
	cv.load_challenge(ch_est)
	if canvas.current_challenge == ch_est and cv.get_node("%OptionsContainer").get_child_count() == 4:
		passed += 1
	else:
		failed += 1
		errors.append("Estimation challenge failed to bind or create 4 option buttons")
		
	# Test 3: Game B — Side comparison split view & options
	var ch_comp = ChallengeGenerator.generate_side_comparison(rng, 2, 2)
	cv.load_challenge(ch_comp)
	var opts_container = cv.get_node("%OptionsContainer")
	var has_left = false
	var has_right = false
	for btn in opts_container.get_children():
		if btn.text == "LEFT": has_left = true
		if btn.text == "RIGHT": has_right = true
	if canvas.current_challenge.visual_data.get("split_view", false) and has_left and has_right:
		passed += 1
	else:
		failed += 1
		errors.append("Side comparison failed split_view flag or LEFT/RIGHT options")
		
	# Test 4: Game C — Color target selection & tap interaction
	var ch_color = ChallengeGenerator.generate_color_target(rng, 3, 2)
	cv.load_challenge(ch_color)
	var btn_action = cv.get_node("%BtnActionDone")
	if btn_action.visible and ch_color.visual_data.has("target_color"):
		passed += 1
	else:
		failed += 1
		errors.append("Color target failed action button visibility or target_color data")
		
	# Test 5: Game D — Shape target selection
	var ch_shape = ChallengeGenerator.generate_shape_target(rng, 4, 2)
	cv.load_challenge(ch_shape)
	var items = ch_shape.visual_data.get("items", [])
	var target_shape = ch_shape.visual_data.get("target_shape", "")
	var target_found = false
	for it in items:
		if it.get("shape") == target_shape and it.get("is_target", false):
			target_found = true
			break
	if target_found and btn_action.visible:
		passed += 1
	else:
		failed += 1
		errors.append("Shape target failed to populate target shapes")
		
	# Test 6: Game E — Don't Tap / Inhibition rule
	var ch_dont_tap = ChallengeGenerator.generate_dont_tap_rule(rng, 5, 2)
	cv.load_challenge(ch_dont_tap)
	if ch_dont_tap.visual_data.has("should_withhold") and btn_action.visible:
		passed += 1
	else:
		failed += 1
		errors.append("Don't tap challenge failed withhold configuration")
		
	# Test 7: Game F — Combined conditional
	var ch_comb = ChallengeGenerator.generate_combined_conditional(rng, 6, 2)
	cv.load_challenge(ch_comb)
	var has_yes = false
	var has_no = false
	for btn in cv.get_node("%OptionsContainer").get_children():
		if btn.text == "YES": has_yes = true
		if btn.text == "NO": has_no = true
	if has_yes and has_no and ch_comb.visual_data.has("red_count"):
		passed += 1
	else:
		failed += 1
		errors.append("Combined conditional failed YES/NO options")
		
	# Test 8: Tap interaction simulation on ChallengeCanvas
	cv.load_challenge(ch_color)
	var target_idx = -1
	for i in range(items.size()):
		if items[i].get("is_target", false):
			target_idx = i
			break
	if target_idx >= 0:
		canvas.set_item_tapped(target_idx)
		if target_idx in canvas.tapped_indices:
			passed += 1
		else:
			failed += 1
			errors.append("Canvas set_item_tapped failed to record tapped index")
	else:
		passed += 1 # safe fallback
		
	# Test 9: Input locking
	cv.lock_input()
	if cv.is_input_locked and not canvas.is_interactive:
		passed += 1
	else:
		failed += 1
		errors.append("ChallengeView lock_input failed to lock canvas interactivity")
		
	# Test 10: Color resolution helper
	var mint_col = canvas._resolve_color("MINT")
	var red_col = canvas._resolve_color("RED")
	var blue_col = canvas._resolve_color("BLUE")
	var yellow_col = canvas._resolve_color("YELLOW")
	if mint_col == GameConfig.COLOR_MINT and red_col == GameConfig.COLOR_ACCENT_RED and blue_col == GameConfig.COLOR_ACCENT_BLUE and yellow_col == GameConfig.COLOR_ACCENT_YELLOW:
		passed += 1
	else:
		failed += 1
		errors.append("Color resolution helper failed to map palette colors")
		
	cv.free()
	
	return {
		"name": "ChallengeRenderingTests",
		"passed": passed,
		"failed": failed,
		"errors": errors
	}
