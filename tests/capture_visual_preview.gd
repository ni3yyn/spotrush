extends Node

const SCENE_GAME = "res://scenes/game/GameScreen.tscn"

func _ready() -> void:
	print("--- CAPTURING VISUAL GAMEPLAY SCREENSHOTS ---")
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("docs/screenshots"):
		dir.make_dir_recursive("docs/screenshots")
		
	var game_scene = load(SCENE_GAME)
	var game_scr = game_scene.instantiate()
	add_child(game_scr)
	
	var cv = game_scr.get_node("%ChallengeView")
	var rng = RandomNumberGenerator.new()
	rng.seed = 2026
	
	var challenges = [
		{"name": "challenge_estimation", "ch": ChallengeGenerator.generate_estimation_count(rng, 1, 2)},
		{"name": "challenge_comparison", "ch": ChallengeGenerator.generate_side_comparison(rng, 2, 2)},
		{"name": "challenge_color_target", "ch": ChallengeGenerator.generate_color_target(rng, 3, 2)},
		{"name": "challenge_shape_target", "ch": ChallengeGenerator.generate_shape_target(rng, 4, 2)},
		{"name": "challenge_dont_tap", "ch": ChallengeGenerator.generate_dont_tap_rule(rng, 5, 2)},
		{"name": "challenge_combined", "ch": ChallengeGenerator.generate_combined_conditional(rng, 6, 2)}
	]
	
	for item in challenges:
		cv.load_challenge(item["ch"])
		# Wait for layout & rendering frames
		for f in range(6):
			await get_tree().process_frame
			
		var viewport = get_viewport()
		if viewport != null:
			var tex = viewport.get_texture()
			if tex != null:
				var img = tex.get_image()
				if img != null:
					var file_path = "docs/screenshots/%s.png" % item["name"]
					var err = img.save_png(file_path)
					if err == OK:
						print("SUCCESS: Saved %s (%dx%d)" % [file_path, img.get_width(), img.get_height()])
					else:
						print("WARN: Failed to save %s (code %d)" % [file_path, err])
						
	# 7. Capture visual tapped feedback state
	var ch_tap_test = ChallengeGenerator.generate_color_target(rng, 7, 2)
	cv.load_challenge(ch_tap_test)
	for f in range(4):
		await get_tree().process_frame
		
	var canvas = cv.get_node("%ChallengeCanvas")
	if canvas != null:
		canvas.set_item_tapped(0)
		canvas.set_item_tapped(1)
		for f in range(4):
			await get_tree().process_frame
			
		var vp = get_viewport()
		if vp != null:
			var img_tap = vp.get_texture().get_image()
			if img_tap != null:
				img_tap.save_png("docs/screenshots/challenge_tapped_feedback.png")
				print("SUCCESS: Saved docs/screenshots/challenge_tapped_feedback.png")

	print(">> CAPTURE PROCESS FINISHED <<")
	get_tree().quit(0)
