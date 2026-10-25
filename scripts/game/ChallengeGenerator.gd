class_name ChallengeGenerator
extends RefCounted

# Generate a random or seeded challenge for a given round and difficulty
static func generate_challenge(round_index: int, difficulty: int = 1, seed_val: int = -1) -> ChallengeDefinition:
	var rng = RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
		
	# Select challenge family based on round index or random distribution
	var types = [
		GameConfig.TYPE_ESTIMATION_COUNT,
		GameConfig.TYPE_COMPARISON_SIDES,
		GameConfig.TYPE_COLOR_TARGET,
		GameConfig.TYPE_SHAPE_TARGET,
		GameConfig.TYPE_DONT_TAP,
		GameConfig.TYPE_COMBINED_CONDITIONAL
	]
	
	# For early rounds, use simpler types
	var selected_type: String
	if round_index == 0:
		selected_type = GameConfig.TYPE_COMPARISON_SIDES
	elif round_index == 1:
		selected_type = GameConfig.TYPE_ESTIMATION_COUNT
	elif round_index == 2:
		selected_type = GameConfig.TYPE_COLOR_TARGET
	else:
		selected_type = types[rng.randi_range(0, types.size() - 1)]
		
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
	var base_min = 12 + (difficulty * 4)
	var base_max = 24 + (difficulty * 8)
	var actual_count = rng.randi_range(base_min, base_max)
	
	var challenge = ChallengeDefinition.new(
		"est_count_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_ESTIMATION_COUNT,
		"Quick! Estimate the number of mint dots:",
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - (float(difficulty) * 0.5), 5.0, 9.0)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.correct_answer = actual_count
	
	# Generate 3 distinct incorrect options close to actual count
	var distractor_offset = maxi(3, 8 - difficulty)
	var opts = [actual_count]
	var offsets = [-distractor_offset, distractor_offset, -(distractor_offset * 2), (distractor_offset * 2)]
	offsets.shuffle()
	
	for off in offsets:
		var opt_val = maxi(5, actual_count + off)
		if not opt_val in opts:
			opts.append(opt_val)
		if opts.size() == 4:
			break
			
	opts.sort()
	challenge.options = opts
	
	# Visual coordinates in normalized 0.0 - 1.0 field
	var items: Array = []
	for i in range(actual_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(14.0, 22.0),
			"color": "MINT",
			"shape": "circle"
		})
	challenge.visual_data = {
		"items": items,
		"count": actual_count
	}
	return challenge

# --- 2. SIDE COMPARISON ---
static func generate_side_comparison(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var count_a = rng.randi_range(15, 30 + (difficulty * 6))
	# Difficulty controls difference margin: easy has big margin, hard has close margin
	var diff_margin = maxi(2, 10 - (difficulty * 2))
	if rng.randf() < 0.5:
		diff_margin = -diff_margin
	var count_b = maxi(8, count_a + diff_margin)
	
	var challenge = ChallengeDefinition.new(
		"side_comp_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMPARISON_SIDES,
		"Which side has MORE dots?",
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - (float(difficulty) * 0.4), 4.5, 8.0)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "choice"
	challenge.options = ["LEFT", "RIGHT"]
	challenge.correct_answer = "LEFT" if count_a > count_b else "RIGHT"
	
	var left_items: Array = []
	for i in range(count_a):
		left_items.append({
			"x": rng.randf_range(0.06, 0.44),
			"y": rng.randf_range(0.15, 0.85),
			"size": rng.randf_range(12.0, 18.0),
			"color": "MINT",
			"shape": "circle"
		})
		
	var right_items: Array = []
	for i in range(count_b):
		right_items.append({
			"x": rng.randf_range(0.56, 0.94),
			"y": rng.randf_range(0.15, 0.85),
			"size": rng.randf_range(12.0, 18.0),
			"color": "AMBER" if difficulty > 2 else "MINT",
			"shape": "circle"
		})
		
	challenge.visual_data = {
		"split_view": true,
		"left_items": left_items,
		"right_items": right_items,
		"left_count": count_a,
		"right_count": count_b
	}
	return challenge

# --- 3. COLOR TARGET SELECTION (TAP TARGETS) ---
static func generate_color_target(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var target_count = rng.randi_range(3, 5 + difficulty)
	var distractor_count = rng.randi_range(8, 16 + (difficulty * 4))
	
	var colors = ["RED", "BLUE", "YELLOW"]
	var target_color = colors[rng.randi_range(0, colors.size() - 1)]
	
	var challenge = ChallengeDefinition.new(
		"color_tgt_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COLOR_TARGET,
		"Tap ALL %s circles! Ignore other colors." % target_color,
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION + 1.0, 6.0, 10.0)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "tap_targets"
	challenge.correct_answer = target_count
	
	var items: Array = []
	for i in range(target_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(28.0, 36.0),
			"color": target_color,
			"shape": "circle",
			"is_target": true
		})
		
	for i in range(distractor_count):
		var dist_color = "MINT" if target_color != "MINT" else "BLUE"
		if rng.randf() < 0.5:
			dist_color = "WHITE"
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(24.0, 32.0),
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
	var target_count = rng.randi_range(3, 4 + difficulty)
	var distractor_count = rng.randi_range(8, 14 + (difficulty * 3))
	
	var target_shape = "square" if rng.randf() < 0.5 else "triangle"
	var distractor_shape = "circle"
	
	var challenge = ChallengeDefinition.new(
		"shape_tgt_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_SHAPE_TARGET,
		"Tap ALL %s shapes!" % target_shape.to_upper(),
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION + 1.0, 6.0, 10.0)
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "tap_targets"
	challenge.correct_answer = target_count
	
	var items: Array = []
	for i in range(target_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(30.0, 38.0),
			"color": "MINT",
			"shape": target_shape,
			"is_target": true
		})
		
	for i in range(distractor_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(26.0, 32.0),
			"color": "MINT",
			"shape": distractor_shape,
			"is_target": false
		})
		
	items.shuffle()
	challenge.visual_data = {
		"items": items,
		"target_shape": target_shape,
		"target_count": target_count
	}
	return challenge

# --- 5. DON'T TAP / WITHHOLD RESPONSE ---
static func generate_dont_tap_rule(rng: RandomNumberGenerator, round_idx: int, difficulty: int) -> ChallengeDefinition:
	var should_withhold: bool = rng.randf() < 0.5
	var count = rng.randi_range(6, 12)
	
	var challenge = ChallengeDefinition.new(
		"dont_tap_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_DONT_TAP,
		"DON'T TAP! Withhold if RED appears. Tap once if GREEN!" if should_withhold else "TAP NOW if GREEN is present!",
		4.5
	)
	challenge.difficulty = difficulty
	challenge.input_mode = "withhold_response"
	challenge.correct_answer = should_withhold # true = withhold, false = tap
	
	var items: Array = []
	var trigger_color = "RED" if should_withhold else "MINT"
	for i in range(count):
		items.append({
			"x": rng.randf_range(0.15, 0.85),
			"y": rng.randf_range(0.2, 0.8),
			"size": rng.randf_range(28.0, 40.0),
			"color": trigger_color if i == 0 else "WHITE",
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
	var red_count = rng.randi_range(8, 22)
	var threshold = 15
	var condition_met = (red_count >= threshold)
	
	var challenge = ChallengeDefinition.new(
		"comb_cond_%d_%d" % [round_idx, rng.randi()],
		GameConfig.TYPE_COMBINED_CONDITIONAL,
		"Are there at least %d RED dots? Choose YES or NO." % threshold,
		clampf(GameConfig.DEFAULT_CHALLENGE_DURATION - 1.0, 5.0, 8.0)
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
			"size": rng.randf_range(16.0, 24.0),
			"color": "RED",
			"shape": "circle"
		})
		
	var white_count = rng.randi_range(5, 12)
	for i in range(white_count):
		items.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.12, 0.88),
			"size": rng.randf_range(16.0, 24.0),
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
