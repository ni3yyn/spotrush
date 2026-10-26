class_name ChallengeGenerator
extends RefCounted

# Generate a random or seeded challenge for a given round and difficulty
static func generate_challenge(round_index: int, difficulty: int = 1, seed_val: int = -1) -> ChallengeDefinition:
	var rng = RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
		
	var types = [
		GameConfig.TYPE_ESTIMATION_COUNT,
		GameConfig.TYPE_COMPARISON_SIDES,
		GameConfig.TYPE_COLOR_TARGET,
		GameConfig.TYPE_SHAPE_TARGET,
		GameConfig.TYPE_DONT_TAP,
		GameConfig.TYPE_COMBINED_CONDITIONAL
	]
	
	# Balanced rotation: introduce mini-games gradually, then cycle with controlled variety
	var selected_type: String
	if round_index == 0:
		selected_type = GameConfig.TYPE_COMPARISON_SIDES
	elif round_index == 1:
		selected_type = GameConfig.TYPE_ESTIMATION_COUNT
	elif round_index == 2:
		selected_type = GameConfig.TYPE_COLOR_TARGET
	elif round_index == 3:
		selected_type = GameConfig.TYPE_SHAPE_TARGET
	elif round_index == 4:
		selected_type = GameConfig.TYPE_DONT_TAP
	elif round_index == 5:
		selected_type = GameConfig.TYPE_COMBINED_CONDITIONAL
	else:
		# Use deterministic cycle offset from seed / round to prevent repeating the same type consecutively
		var offset = (round_index + (seed_val if seed_val >= 0 else 0)) % types.size()
		selected_type = types[offset]
		
	var challenge: ChallengeDefinition = null
	match selected_type:
		GameConfig.TYPE_ESTIMATION_COUNT:
			challenge = generate_estimation_count(rng, round_index, difficulty)
		GameConfig.TYPE_COMPARISON_SIDES:
			challenge = generate_side_comparison(rng, round_index, difficulty)
		GameConfig.TYPE_COLOR_TARGET:
			challenge = generate_color_target(rng, round_index, difficulty)
		GameConfig.TYPE_SHAPE_TARGET:
			challenge = generate_shape_target(rng, round_index, difficulty)
		GameConfig.TYPE_DONT_TAP:
			challenge = generate_dont_tap_rule(rng, round_index, difficulty)
		GameConfig.TYPE_COMBINED_CONDITIONAL:
			challenge = generate_combined_conditional(rng, round_index, difficulty)
		_:
			challenge = generate_side_comparison(rng, round_index, difficulty)
			
	# Sanity check
	if not challenge.is_valid():
		push_error("Generated invalid challenge for round %d! Falling back to safe comparison." % round_index)
		return generate_side_comparison(rng, round_index, 1)
		
	return challenge

# --- 1. QUANTITY ESTIMATION ---
static func generate_estimation_count(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var base_min: int
	var base_max: int
	var distractor_step: int
	var duration: float
	
	match difficulty:
		1: # Easy
			base_min = 12
			base_max = 18
			distractor_step = rng.randi_range(4, 6)
			duration = 7.5
		2: # Medium
			base_min = 18
			base_max = 28
			distractor_step = rng.randi_range(3, 5)
			duration = 6.5
		3: # Hard
			base_min = 26
			base_max = 38
			distractor_step = rng.randi_range(3, 4)
			duration = 5.5
		_: # Expert
			base_min = 34
			base_max = 48
			distractor_step = rng.randi_range(2, 3)
			duration = 5.0
			
	var actual_count = rng.randi_range(base_min, base_max)
	
	var challenge = ChallengeDefinition.new(
		"est_count_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_ESTIMATION_COUNT,
		"Quick! Estimate the number of mint dots:",
		duration
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.correct_answer = actual_count
	
	# Generate 3 distinct, plausible distractors close to actual count
	var opts = [actual_count]
	var offsets = [-distractor_step, distractor_step, -(distractor_step * 2), (distractor_step * 2), -(distractor_step * 3), (distractor_step * 3)]
	offsets.shuffle()
	
	for off in offsets:
		var candidate = maxi(5, actual_count + off)
		if not candidate in opts:
			opts.append(candidate)
		if opts.size() == 4:
			break
			
	opts.sort()
	challenge.options = opts
	
	# Procedural generation: mix uniform scatter with clustering based on difficulty
	var items: Array = []
	var cluster_count = 0 if difficulty == 1 else (1 if difficulty == 2 else 2)
	var cluster_centers = []
	for c in range(cluster_count):
		cluster_centers.append(Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75)))
		
	for i in range(actual_count):
		var pos: Vector2 = Vector2.ZERO
		var attempts = 0
		var found_pos = false
		while attempts < 35 and not found_pos:
			attempts += 1
			if not cluster_centers.is_empty() and rng.randf() < 0.45:
				var center_pt = cluster_centers[rng.randi_range(0, cluster_centers.size() - 1)]
				var angle = rng.randf_range(0.0, TAU)
				var rad = rng.randf_range(0.04, 0.14)
				pos = Vector2(
					clampf(center_pt.x + (cos(angle) * rad), 0.1, 0.9),
					clampf(center_pt.y + (sin(angle) * rad), 0.12, 0.88)
				)
			else:
				pos = Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.12, 0.88))
				
			var too_close = false
			for prev in items:
				if pos.distance_to(Vector2(prev["x"], prev["y"])) < 0.048:
					too_close = true
					break
			if not too_close:
				found_pos = true
			
		var size_min = 16.0 if difficulty <= 2 else 13.0
		var size_max = 24.0 if difficulty <= 2 else 26.0
		items.append({
			"x": pos.x,
			"y": pos.y,
			"size": rng.randf_range(size_min, size_max),
			"color": "MINT",
			"shape": "circle"
		})
		
	challenge.visual_data = {
		"items": items,
		"count": actual_count,
		"cluster_count": cluster_count
	}
	return challenge

# --- 2. SIDE COMPARISON ---
static func generate_side_comparison(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var base_count = rng.randi_range(16, 24 + (difficulty * 5))
	
	# Difficulty margin: easy rounds have a clear visual difference, expert is a close call
	var margin: int
	var duration: float
	match difficulty:
		1: # Easy
			margin = rng.randi_range(8, 12)
			duration = 6.5
		2: # Medium
			margin = rng.randi_range(5, 7)
			duration = 5.5
		3: # Hard
			margin = rng.randi_range(3, 4)
			duration = 5.0
		_: # Expert
			margin = rng.randi_range(1, 2)
			duration = 4.5
			
	var left_has_more: bool = (rng.randf() < 0.5)
	var count_a: int
	var count_b: int
	
	if left_has_more:
		count_a = base_count + margin
		count_b = base_count
	else:
		count_a = base_count
		count_b = base_count + margin
		
	var challenge = ChallengeDefinition.new(
		"side_comp_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMPARISON_SIDES,
		"Which side has MORE dots?",
		duration
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.options = ["LEFT", "RIGHT"]
	challenge.correct_answer = "LEFT" if count_a > count_b else "RIGHT"
	
	# Generate left and right dots with identical size and equal bounding area to prevent area bias
	var dot_size: float = 15.0 if difficulty <= 2 else 13.5
	
	var left_items: Array = []
	for i in range(count_a):
		var pos = Vector2.ZERO
		var attempts = 0
		var found = false
		while attempts < 30 and not found:
			attempts += 1
			pos = Vector2(rng.randf_range(0.08, 0.42), rng.randf_range(0.16, 0.84))
			var too_close = false
			for prev in left_items:
				if pos.distance_to(Vector2(prev["x"], prev["y"])) < 0.042:
					too_close = true
					break
			if not too_close:
				found = true
		left_items.append({
			"x": pos.x,
			"y": pos.y,
			"size": dot_size,
			"color": "MINT",
			"shape": "circle"
		})
		
	var right_items: Array = []
	for i in range(count_b):
		var pos = Vector2.ZERO
		var attempts = 0
		var found = false
		while attempts < 30 and not found:
			attempts += 1
			pos = Vector2(rng.randf_range(0.58, 0.92), rng.randf_range(0.16, 0.84))
			var too_close = false
			for prev in right_items:
				if pos.distance_to(Vector2(prev["x"], prev["y"])) < 0.042:
					too_close = true
					break
			if not too_close:
				found = true
		right_items.append({
			"x": pos.x,
			"y": pos.y,
			"size": dot_size,
			"color": "MINT",
			"shape": "circle"
		})
		
	challenge.visual_data = {
		"split_view": true,
		"left_items": left_items,
		"right_items": right_items,
		"left_count": count_a,
		"right_count": count_b,
		"difference": absi(count_a - count_b)
	}
	return challenge

# --- 3. COLOR TARGET SELECTION (TAP TARGETS) ---
static func generate_color_target(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var target_count: int
	var distractor_count: int
	var distractor_palette: Array
	var duration: float
	
	match difficulty:
		1: # Easy
			target_count = rng.randi_range(2, 3)
			distractor_count = rng.randi_range(6, 8)
			distractor_palette = ["WHITE"]
			duration = 8.0
		2: # Medium
			target_count = rng.randi_range(3, 4)
			distractor_count = rng.randi_range(9, 12)
			distractor_palette = ["WHITE", "BLUE"]
			duration = 7.5
		3: # Hard
			target_count = rng.randi_range(4, 5)
			distractor_count = rng.randi_range(12, 16)
			distractor_palette = ["WHITE", "BLUE", "RED"]
			duration = 7.0
		_: # Expert
			target_count = rng.randi_range(5, 6)
			distractor_count = rng.randi_range(16, 20)
			distractor_palette = ["WHITE", "BLUE", "RED", "YELLOW"]
			duration = 6.5
			
	var possible_targets = ["YELLOW", "RED", "BLUE", "MINT"]
	var target_color = possible_targets[rng.randi_range(0, possible_targets.size() - 1)]
	
	# Ensure target color is not also a distractor
	distractor_palette.erase(target_color)
	if distractor_palette.is_empty():
		distractor_palette.append("WHITE")
		
	var challenge = ChallengeDefinition.new(
		"color_tgt_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COLOR_TARGET,
		"Tap ALL %s circles! (Ignore other colors)" % target_color,
		duration
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "tap_targets"
	challenge.correct_answer = target_count
	
	# Generate points with minimum distance separation
	var total_items = target_count + distractor_count
	var positions: Array[Vector2] = _generate_spaced_positions(rng, total_items, 0.08)
	
	var items: Array = []
	# Assign target items
	for i in range(target_count):
		var p = positions[i]
		items.append({
			"x": p.x,
			"y": p.y,
			"size": rng.randf_range(30.0, 36.0),
			"color": target_color,
			"shape": "circle",
			"is_target": true
		})
		
	# Assign distractor items
	for i in range(target_count, total_items):
		var p = positions[i]
		var dist_color = distractor_palette[rng.randi_range(0, distractor_palette.size() - 1)]
		items.append({
			"x": p.x,
			"y": p.y,
			"size": rng.randf_range(26.0, 32.0),
			"color": dist_color,
			"shape": "circle",
			"is_target": false
		})
		
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"target_color": target_color,
		"target_count": target_count
	}
	return challenge

# --- 4. SHAPE TARGET SELECTION ---
static func generate_shape_target(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var target_count: int
	var distractor_count: int
	var distractor_shapes: Array
	var duration: float
	
	match difficulty:
		1: # Easy
			target_count = rng.randi_range(2, 3)
			distractor_count = rng.randi_range(7, 9)
			distractor_shapes = ["circle"]
			duration = 8.0
		2: # Medium
			target_count = rng.randi_range(3, 4)
			distractor_count = rng.randi_range(10, 13)
			distractor_shapes = ["circle", "square"]
			duration = 7.5
		3: # Hard
			target_count = rng.randi_range(4, 5)
			distractor_count = rng.randi_range(13, 16)
			distractor_shapes = ["circle", "square", "diamond"]
			duration = 7.0
		_: # Expert
			target_count = rng.randi_range(5, 6)
			distractor_count = rng.randi_range(16, 20)
			distractor_shapes = ["circle", "square", "triangle", "diamond"]
			duration = 6.5
			
	var possible_targets = ["triangle", "square", "diamond"]
	var target_shape = possible_targets[rng.randi_range(0, possible_targets.size() - 1)]
	distractor_shapes.erase(target_shape)
	if distractor_shapes.is_empty():
		distractor_shapes.append("circle")
		
	# All shapes share the SAME uniform color so the player must distinguish shape contour
	var uniform_color = "MINT" if difficulty <= 2 else "AMBER"
	
	var challenge = ChallengeDefinition.new(
		"shape_tgt_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_SHAPE_TARGET,
		"Tap ALL %s shapes!" % target_shape.to_upper(),
		duration
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "tap_targets"
	challenge.correct_answer = target_count
	
	var total_items = target_count + distractor_count
	var positions: Array[Vector2] = _generate_spaced_positions(rng, total_items, 0.08)
	
	var items: Array = []
	for i in range(target_count):
		var p = positions[i]
		items.append({
			"x": p.x,
			"y": p.y,
			"size": rng.randf_range(32.0, 38.0),
			"color": uniform_color,
			"shape": target_shape,
			"is_target": true
		})
		
	for i in range(target_count, total_items):
		var p = positions[i]
		var dist_shape = distractor_shapes[rng.randi_range(0, distractor_shapes.size() - 1)]
		items.append({
			"x": p.x,
			"y": p.y,
			"size": rng.randf_range(28.0, 34.0),
			"color": uniform_color,
			"shape": dist_shape,
			"is_target": false
		})
		
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"target_shape": target_shape,
		"target_count": target_count
	}
	return challenge

# --- 5. DON'T TAP / INHIBITORY CONTROL (GO / NO-GO) ---
static func generate_dont_tap_rule(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var should_withhold: bool = (rng.randf() < 0.5)
	var count = rng.randi_range(8, 14 + (difficulty * 2))
	var duration: float = clampf(4.5 - (float(difficulty) * 0.25), 3.5, 4.5)
	
	var prompt: String
	if should_withhold:
		prompt = "DANGER! RED IS PRESENT — DO NOT TAP!"
	else:
		prompt = "ALL CLEAR! NO RED — TAP FAST!"
		
	var challenge = ChallengeDefinition.new(
		"dont_tap_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_DONT_TAP,
		prompt,
		duration
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "withhold_response"
	challenge.correct_answer = should_withhold # true = withhold, false = must tap
	
	var items: Array = []
	var trigger_color = "RED" if should_withhold else "MINT"
	
	for i in range(count):
		var col = trigger_color if i == 0 else ("WHITE" if rng.randf() < 0.7 else "MINT")
		# In withhold rounds, make sure no other red circles appear
		if not should_withhold and col == "RED":
			col = "MINT"
			
		items.append({
			"x": rng.randf_range(0.14, 0.86),
			"y": rng.randf_range(0.18, 0.82),
			"size": rng.randf_range(30.0, 42.0) if i == 0 else rng.randf_range(22.0, 30.0),
			"color": col,
			"shape": "circle"
		})
	items.shuffle()
	
	challenge.visual_data = {
		"items": items,
		"trigger_color": trigger_color,
		"should_withhold": should_withhold
	}
	return challenge

# --- 6. COMBINED CONDITIONAL ---
static func generate_combined_conditional(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	# Choose between 3 rich combined conditional variants
	var variant = rng.randi_range(1, 3)
	
	if variant == 1 and difficulty >= 2:
		# Variant 1: Multi-Attribute Target Tap (e.g. "Tap all RED TRIANGLES")
		return _generate_multi_attribute_tap(rng, round_idx, difficulty)
	elif variant == 2:
		# Variant 2: Comparative Shape Majority ("Are there MORE Triangles than Squares?")
		return _generate_shape_comparison(rng, round_idx, difficulty)
	else:
		# Variant 3: Color Count Threshold ("Are there at least X RED dots?")
		return _generate_color_threshold(rng, round_idx, difficulty)

static func _generate_multi_attribute_tap(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var target_count = rng.randi_range(3, 3 + difficulty)
	var challenge = ChallengeDefinition.new(
		"comb_tap_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMBINED_CONDITIONAL,
		"Tap all RED TRIANGLES! (Ignore Blue Triangles & Red Circles)",
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - (float(difficulty) * 0.4), 6.0, 9.0)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "tap_targets"
	challenge.correct_answer = target_count
	
	var items: Array = []
	# 1. Target items: Red Triangles
	for i in range(target_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.14, 0.86),
			"size": rng.randf_range(32.0, 38.0),
			"color": "RED",
			"shape": "triangle",
			"is_target": true
		})
	# 2. Shape match, color fail distractors: Blue Triangles
	for i in range(rng.randi_range(3, 5)):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.14, 0.86),
			"size": rng.randf_range(28.0, 34.0),
			"color": "BLUE",
			"shape": "triangle",
			"is_target": false
		})
	# 3. Color match, shape fail distractors: Red Circles
	for i in range(rng.randi_range(3, 5)):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.14, 0.86),
			"size": rng.randf_range(28.0, 34.0),
			"color": "RED",
			"shape": "circle",
			"is_target": false
		})
	# 4. Neutral distractors: White Squares
	for i in range(rng.randi_range(2, 4)):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.14, 0.86),
			"size": rng.randf_range(26.0, 30.0),
			"color": "WHITE",
			"shape": "square",
			"is_target": false
		})
		
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"target_count": target_count,
		"sub_type": "multi_attribute_tap"
	}
	return challenge

static func _generate_shape_comparison(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var count_triangles = rng.randi_range(8, 16)
	var diff_step = maxi(2, 6 - difficulty)
	if rng.randf() < 0.5:
		diff_step = -diff_step
	var count_squares = maxi(4, count_triangles + diff_step)
	
	var condition_met = (count_triangles > count_squares)
	var challenge = ChallengeDefinition.new(
		"comb_shape_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMBINED_CONDITIONAL,
		"Are there MORE Triangles than Squares? Choose YES or NO.",
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - 1.0, 5.0, 7.5)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.options = ["YES", "NO"]
	challenge.correct_answer = "YES" if condition_met else "NO"
	
	var items: Array = []
	for i in range(count_triangles):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(22.0, 28.0),
			"color": "MINT",
			"shape": "triangle"
		})
	for i in range(count_squares):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(22.0, 28.0),
			"color": "AMBER",
			"shape": "square"
		})
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"count_triangles": count_triangles,
		"count_squares": count_squares
	}
	return challenge

static func _generate_color_threshold(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var red_count = rng.randi_range(8, 22)
	var threshold = 14
	var condition_met = (red_count >= threshold)
	
	var challenge = ChallengeDefinition.new(
		"comb_cond_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMBINED_CONDITIONAL,
		"Are there at least %d RED dots? Choose YES or NO." % threshold,
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - 1.0, 5.0, 7.5)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.options = ["YES", "NO"]
	challenge.correct_answer = "YES" if condition_met else "NO"
	
	var items: Array = []
	for i in range(red_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(18.0, 26.0),
			"color": "RED",
			"shape": "circle"
		})
		
	var white_count = rng.randi_range(6, 12)
	for i in range(white_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(18.0, 24.0),
			"color": "WHITE",
			"shape": "square"
		})
		
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"red_count": red_count,
		"threshold": threshold
	}
	return challenge

# Helper to generate spaced 2D points with minimum distance
static func _generate_spaced_positions(rng: RandomNumberGenerator, count: int, min_dist: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var attempts = 0
	var max_attempts = count * 60
	
	while pts.size() < count and attempts < max_attempts:
		attempts += 1
		var candidate = Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.14, 0.86))
		var too_close = false
		for p in pts:
			if candidate.distance_to(p) < min_dist:
				too_close = true
				break
		if not too_close:
			pts.append(candidate)
			
	# If spacing was too strict, fill remaining with random points
	while pts.size() < count:
		pts.append(Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.14, 0.86)))
		
	return pts
