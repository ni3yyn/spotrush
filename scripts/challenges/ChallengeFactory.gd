class_name ChallengeFactory
extends RefCounted

## v16 RUN FORGE - parameterised mini-game builders.
##
## Every builder consumes one continuous intensity value (0..3) plus the
## run's RuleBook, and every number inside a challenge - item counts,
## comparison margins, distractor similarity, token sizes, time limits -
## is computed from that intensity instead of being picked from fixed tier
## tables. Quantity comparisons scale by Weber fraction (the margin is a
## fraction of the crowd, matching how eyes actually judge numerosity),
## estimation distractors close in as intensity rises, and search rounds
## grow confusable distractor sets. Nothing about positions or answers is
## ever hardcoded: options are derived, thresholds are constructed around
## their truth value, and phrasing comes from the RuleBook. All shuffling
## runs through the round's own RNG stream so a seed fully determines the
## series (Godot's built-in Array.shuffle() would use the global RNG).

const COLOR_TARGET_POOL := ["YELLOW", "RED", "BLUE", "MINT"]
const SHAPE_TARGET_POOL := ["triangle", "square", "diamond"]
const GONOGO_NOISE_POOL := ["BLUE", "YELLOW", "MINT"]
const MULTI_COLORS := ["RED", "BLUE", "YELLOW"]
const MULTI_SHAPES := ["triangle", "square", "diamond"]
const COMBINED_VARIANTS := ["multi_attribute", "majority", "threshold"]

static func build(rng: RandomNumberGenerator, type: String, round_idx: int,
				intensity: float, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var t := clampf(intensity / 3.0, 0.0, 1.0)
		var band := DifficultyCurve.band_for(intensity)
		match type:
				GameConfig.TYPE_ESTIMATION_COUNT:
						return _build_estimation(rng, round_idx, t, band, book, run_seed)
				GameConfig.TYPE_COMPARISON_SIDES:
						return _build_comparison(rng, round_idx, t, band, book, run_seed)
				GameConfig.TYPE_COLOR_TARGET:
						return _build_color_target(rng, round_idx, t, band, book, run_seed)
				GameConfig.TYPE_SHAPE_TARGET:
						return _build_shape_target(rng, round_idx, t, band, book, run_seed)
				GameConfig.TYPE_DONT_TAP:
						return _build_gonogo(rng, round_idx, t, band, book, run_seed)
				GameConfig.TYPE_COMBINED_CONDITIONAL:
						return _build_combined(rng, round_idx, t, band, book, run_seed)
				_:
						return _build_comparison(rng, round_idx, t, band, book, run_seed)

static func _stamp(challenge: ChallengeDefinition, type: String, rng: RandomNumberGenerator,
				round_idx: int, t: float, band: int, run_seed: int) -> void:
		challenge.id = "%s_r%02d_%08x" % [type, round_idx, rng.randi()]
		challenge.difficulty = band
		challenge.intensity = t * 3.0
		challenge.round_index = round_idx
		challenge.run_seed = run_seed
		challenge.version = 2

# --- 1. QUANTITY ESTIMATION ---------------------------------------------------------

static func _build_estimation(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, _book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var count := clampi(int(round(lerpf(11.0, 44.0, t) * rng.randf_range(0.86, 1.14))),
				8, GameConfig.FORGE_MAX_ITEMS_PER_FIELD)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_ESTIMATION_COUNT,
				RuleBook.pick_phrase(rng, RuleBook.ESTIMATION_PHRASES),
				clampf(3.0 + float(count) * lerpf(0.165, 0.105, t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_ESTIMATION_COUNT, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "choice"
		challenge.rule = "estimate"
		challenge.correct_answer = count
		challenge.options = _estimation_options(t, count)
		challenge.visual_data = {"items": _estimation_items(rng, t, count), "count": count}
		return challenge

## Distractors tighten around the true count as intensity rises (relative
## gap shrinks), then are widened if the crowd was too small to find three.
static func _estimation_options(t: float, count: int) -> Array:
		var gap := maxf(0.08, lerpf(0.32, 0.10, t))
		var step := maxi(1, int(round(float(count) * gap)))
		var offsets := [-2, -1, 1, 2, -3, 3, -4, 4]
		var opts := [count]
		for off in offsets:
				var candidate := count + int(off) * step
				if candidate >= 2 and not candidate in opts:
						opts.append(candidate)
				if opts.size() >= 4:
						break
		var extra := count + step + 1
		while opts.size() < 4:
				if extra >= 2 and not extra in opts:
						opts.append(extra)
				extra += 1
		opts.sort()
		return opts

## Arrangement style is difficulty-driven: readable row bands early,
## uniform scatter in the middle, swarming clusters under pressure.
static func _estimation_items(rng: RandomNumberGenerator, t: float, count: int) -> Array:
		var dot := lerpf(27.0, 17.0, t)
		var jitter := lerpf(0.10, 0.22, t)
		var style_roll := rng.randf()
		if (t < 0.45 and style_roll < 0.65) or (t >= 0.45 and style_roll < 0.18):
				var rows := _row_band_layout(rng, t, count, dot, jitter)
				if not rows.is_empty():
						return rows
		var cluster_centers: Array = []
		var clustered_count := 0
		if t > 0.5 and rng.randf() < 0.75:
				var center_count := rng.randi_range(2, 3)
				clustered_count = int(round(float(count) * rng.randf_range(0.35, 0.55)))
				for c in center_count:
						cluster_centers.append(Vector2(rng.randf_range(0.24, 0.76), rng.randf_range(0.28, 0.72)))
		var cluster_dot := dot * 0.9
		var cluster_sep := LayoutSampler.separation_for(cluster_dot * 1.08, 1.22)
		var cluster_pts: Array = []
		if not cluster_centers.is_empty():
				var per_cluster := maxi(1, int(ceil(float(clustered_count) / float(cluster_centers.size()))))
				var cluster_radius := clampf(sqrt(float(per_cluster) * cluster_sep * cluster_sep * 1.15), 0.07, 0.16)
				# One ring_cluster call per center (with its quota) so the sampler's
				# self-distancing actually engages across the whole cluster.
				var quotas := _split_quota(clustered_count, cluster_centers.size())
				for ci in range(cluster_centers.size()):
						var pts := LayoutSampler.ring_cluster(rng, cluster_centers[ci], quotas[ci],
								0.02, cluster_radius, cluster_sep)
						for p in pts:
								cluster_pts.append(p)
		var scatter_count := count - cluster_pts.size()
		var scatter_sep := LayoutSampler.separation_for(dot * (1.0 + jitter), 1.22)
		var scatter := LayoutSampler.sample_field_avoiding(rng, scatter_count, scatter_sep,
				cluster_pts, (cluster_sep + scatter_sep) * 0.5)
		var items: Array = []
		for p in cluster_pts:
				items.append(_estimation_dot(rng, p, cluster_dot, 0.08))
		for p in scatter:
				items.append(_estimation_dot(rng, p, dot, jitter))
		_shuffle_with(rng, items)
		return items

## Readable near-grid bands (rows of dots) for low-intensity crowds; empty
## when the density cannot honour the separation the token size demands.
static func _row_band_layout(rng: RandomNumberGenerator, t: float, count: int,
				dot: float, jitter: float) -> Array:
		var needed := LayoutSampler.separation_for(dot * (1.0 + jitter), 1.22)
		var cols := clampi(int(ceil(sqrt(float(count) * 1.3))), 3, 9)
		var rows := int(ceil(float(count) / float(cols)))
		var w := 0.78 / float(cols)
		var h := 0.72 / float(rows)
		if w < needed or h < needed:
				return []
		var slack_x := minf(lerpf(0.10, 0.30, t), (w - needed) / (2.0 * w))
		var slack_y := minf(lerpf(0.10, 0.30, t), (h - needed) / (2.0 * h))
		var items: Array = []
		for i in count:
				var col := i % cols
				var row := int(float(i) / float(cols))
				var x := clampf(0.11 + (float(col) + 0.5) * w + rng.randf_range(-slack_x, slack_x) * w, 0.08, 0.92)
				var y := clampf(0.14 + (float(row) + 0.5) * h + rng.randf_range(-slack_y, slack_y) * h, 0.12, 0.88)
				items.append(_estimation_dot(rng, Vector2(x, y), dot, jitter))
		_shuffle_with(rng, items)
		return items

static func _estimation_dot(rng: RandomNumberGenerator, pos: Vector2, base: float, jitter: float) -> Dictionary:
		return {
				"x": pos.x,
				"y": pos.y,
				"size": clampf(base * rng.randf_range(1.0 - jitter, 1.0 + jitter), 12.0, 34.0),
				"color": "MINT",
				"shape": "circle",
		}

# --- 2. SIDE COMPARISON -------------------------------------------------------------

static func _build_comparison(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var asking_more := book.take_flip("cmp_rule")
		# The CORRECT side comes from ONE ledger stream. Deriving it as
		# winner_left XOR asking_more (the v16 shape) XORs two independently
		# balanced streams, and two balanced streams can still produce a
		# three-in-a-row answer streak - the fairness ledger exists to make
		# the ANSWER stream ungameable, so the answer is what the ledger draws.
		var correct := "LEFT" if book.take_flip("cmp_side") else "RIGHT"
		var winner_left := (correct == "LEFT") if asking_more else (correct != "LEFT")
		var base := int(round(lerpf(14.0, 26.0, t) * rng.randf_range(0.9, 1.1)))
		var weber := lerpf(0.38, 0.07, t)
		var margin := maxi(1, int(round(float(base) * weber * rng.randf_range(0.85, 1.25))))
		var count_left := base + margin if winner_left else base
		var count_right := base if winner_left else base + margin
		var total_dots := count_left + count_right
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_COMPARISON_SIDES,
				RuleBook.comparison_phrase(rng, asking_more),
				clampf(lerpf(6.8, 4.4, t) + float(total_dots - 40) * 0.02,
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_COMPARISON_SIDES, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "choice"
		challenge.rule = "more" if asking_more else "fewer"
		challenge.options = ["LEFT", "RIGHT"]
		challenge.correct_answer = correct
		var dot := lerpf(18.0, 14.5, t)
		var sep := LayoutSampler.separation_for(dot, 1.22)
		var left_items := _uniform_side(LayoutSampler.sample_split(rng, count_left, sep, "L"), dot)
		var right_items := _uniform_side(LayoutSampler.sample_split(rng, count_right, sep, "R"), dot)
		challenge.visual_data = {
				"split_view": true,
				"left_items": left_items,
				"right_items": right_items,
				"left_count": count_left,
				"right_count": count_right,
				"difference": absi(count_left - count_right),
		}
		return challenge

## Identical size and one colour on both sides: numerosity only, no area cue.
static func _uniform_side(pts: Array, dot: float) -> Array:
		var items: Array = []
		for p in pts:
				items.append({"x": p.x, "y": p.y, "size": dot, "color": "MINT", "shape": "circle"})
		return items

# --- 3. COLOUR TARGET SEARCH --------------------------------------------------------

static func _build_color_target(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var target_color := str(book.next_from_pool("tgt_color", COLOR_TARGET_POOL))
		var target_count := clampi(int(round(lerpf(2.0, 6.0, t))) + rng.randi_range(0, 1), 2, 7)
		var distractor_pool: Array = COLOR_TARGET_POOL.duplicate()
		distractor_pool.erase(target_color)
		distractor_pool.append("WHITE")
		_shuffle_with(rng, distractor_pool)
		var palette_size := clampi(1 + int(round(t * 2.2)), 1, distractor_pool.size())
		var palette: Array = []
		for i in palette_size:
				palette.append(distractor_pool[i])
		var distractor_count := int(round(lerpf(7.0, 18.0, t) * rng.randf_range(0.9, 1.15)))
		var target_size := lerpf(37.0, 30.0, t)
		var distractor_size := lerpf(31.0, 22.0, t)
		var total := clampi(target_count + distractor_count, 2, GameConfig.FORGE_MAX_ITEMS_PER_FIELD)
		target_count = mini(target_count, total - 1)
		var sep := LayoutSampler.separation_for(target_size * 1.08, 1.28)
		var positions := LayoutSampler.sample_field(rng, total, sep)
		var items: Array = []
		for i in range(total):
				var is_target := i < target_count
				items.append({
						"x": positions[i].x,
						"y": positions[i].y,
						"size": _sized(rng, target_size, 0.08) if is_target else _sized(rng, distractor_size, 0.12),
						"color": target_color if is_target else str(palette[rng.randi_range(0, palette.size() - 1)]),
						"shape": "circle",
						"is_target": is_target,
				})
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_COLOR_TARGET,
				RuleBook.color_tap_phrase(rng, target_color),
				clampf(3.2 + 0.20 * float(total) * (1.0 - 0.32 * t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_COLOR_TARGET, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "tap_targets"
		challenge.rule = "color_search"
		challenge.correct_answer = target_count
		challenge.visual_data = {
				"items": items,
				"target_color": target_color,
				"target_count": target_count,
		}
		return challenge

# --- 4. SHAPE TARGET SEARCH ---------------------------------------------------------

static func _build_shape_target(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var target_shape := str(book.next_from_pool("tgt_shape", SHAPE_TARGET_POOL))
		var distractor_pool: Array = ["circle", "square", "triangle", "diamond"]
		distractor_pool.erase(target_shape)
		_shuffle_with(rng, distractor_pool)
		var palette_size := clampi(1 + int(round(t * 2.0)), 1, distractor_pool.size())
		var palette: Array = []
		for i in palette_size:
				palette.append(distractor_pool[i])
		if t < 0.4 and not "circle" in palette:
				palette[0] = "circle"
		var target_count := clampi(int(round(lerpf(2.0, 6.0, t))) + rng.randi_range(0, 1), 2, 7)
		var distractor_count := int(round(lerpf(8.0, 19.0, t) * rng.randf_range(0.9, 1.15)))
		var uniform_color := "MINT" if t < 0.55 else "AMBER"
		var target_size := lerpf(37.0, 30.0, t)
		var distractor_size := lerpf(32.0, 23.0, t)
		var total := clampi(target_count + distractor_count, 2, GameConfig.FORGE_MAX_ITEMS_PER_FIELD)
		target_count = mini(target_count, total - 1)
		var sep := LayoutSampler.separation_for(target_size * 1.08, 1.28)
		var positions := LayoutSampler.sample_field(rng, total, sep)
		var items: Array = []
		for i in range(total):
				var is_target := i < target_count
				items.append({
						"x": positions[i].x,
						"y": positions[i].y,
						"size": _sized(rng, target_size, 0.08) if is_target else _sized(rng, distractor_size, 0.12),
						"color": uniform_color,
						"shape": target_shape if is_target else str(palette[rng.randi_range(0, palette.size() - 1)]),
						"is_target": is_target,
				})
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_SHAPE_TARGET,
				RuleBook.shape_tap_phrase(rng, target_shape),
				clampf(3.2 + 0.20 * float(total) * (1.0 - 0.30 * t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_SHAPE_TARGET, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "tap_targets"
		challenge.rule = "shape_search"
		challenge.correct_answer = target_count
		challenge.visual_data = {
				"items": items,
				"target_shape": target_shape,
				"target_count": target_count,
		}
		return challenge

# --- 5. GO / NO-GO INHIBITION -------------------------------------------------------

static func _build_gonogo(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var withhold := book.take_flip("gonogo")
		var count := int(round(lerpf(9.0, 16.0, t))) + rng.randi_range(0, 2)
		var trigger_size := lerpf(44.0, 38.0, t)
		var noise_size := lerpf(27.0, 22.0, t)
		# Salience falls as intensity climbs: the trigger drifts from centre
		# stage toward the periphery, so the scan actually has to happen.
		var angle := rng.randf_range(0.0, TAU)
		var dist := lerpf(0.05, 0.30, t) * rng.randf_range(0.85, 1.15)
		var red_pos := Vector2(
				clampf(0.5 + cos(angle) * dist, 0.14, 0.86),
				clampf(0.5 + sin(angle) * dist * 0.9, 0.18, 0.82))
		var noise_count := count - 1 if withhold else count
		var sep := LayoutSampler.separation_for(trigger_size, 1.28)
		var noise := LayoutSampler.sample_field_avoiding(rng, noise_count, sep,
				[red_pos] if withhold else [], sep * 0.8)
		var items: Array = []
		if withhold:
				items.append({"x": red_pos.x, "y": red_pos.y, "size": trigger_size,
						"color": "RED", "shape": "circle"})
		for p in noise:
				var col := "WHITE"
				var roll := rng.randf()
				if roll < 0.62:
						col = "MINT"
				elif t > 0.55 and roll > 0.82:
						col = str(GONOGO_NOISE_POOL[rng.randi_range(0, GONOGO_NOISE_POOL.size() - 1)])
				items.append({"x": p.x, "y": p.y, "size": _sized(rng, noise_size, 0.14),
						"color": col, "shape": "circle"})
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_DONT_TAP,
				RuleBook.pick_phrase(rng, RuleBook.GONOGO_PHRASES),
				clampf(lerpf(4.6, 3.6, t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_DONT_TAP, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "withhold_response"
		challenge.rule = "gonogo"
		challenge.correct_answer = withhold
		challenge.visual_data = {
				"items": items,
				"trigger_color": "RED" if withhold else "MINT",
				"should_withhold": withhold,
		}
		return challenge

# --- 6. COMBINED CONDITIONAL (three rotating sub-rules) ----------------------------

static func _build_combined(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var variant := str(book.next_from_pool("comb_variant", COMBINED_VARIANTS))
		match variant:
				"multi_attribute":
						return _build_multi_attribute(rng, round_idx, t, band, book, run_seed)
				"majority":
						return _build_majority(rng, round_idx, t, band, book, run_seed)
				_:
						return _build_threshold(rng, round_idx, t, band, book, run_seed)

## Variant A: conjunction search - "Tap every RED TRIANGLE, ignore the
## near-misses". Distractor combos are generated, then phrased dynamically.
static func _build_multi_attribute(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var c1 := str(book.next_from_pool("ma_color", MULTI_COLORS))
		var s1 := str(book.next_from_pool("ma_shape", MULTI_SHAPES))
		var others_c: Array = MULTI_COLORS.duplicate()
		others_c.erase(c1)
		var others_s: Array = MULTI_SHAPES.duplicate()
		others_s.erase(s1)
		var c2 := str(others_c[rng.randi_range(0, others_c.size() - 1)])
		var s2 := str(others_s[rng.randi_range(0, others_s.size() - 1)])
		var target_count := clampi(int(round(lerpf(3.0, 6.0, t))) + rng.randi_range(0, 1), 3, 7)
		var shape_match := int(round(lerpf(2.0, 4.0, t))) + rng.randi_range(0, 1)
		var color_match := int(round(lerpf(2.0, 4.0, t))) + rng.randi_range(0, 1)
		var neutral := int(round(lerpf(1.0, 3.0, t))) + rng.randi_range(0, 1)
		var total := clampi(target_count + shape_match + color_match + neutral, 2,
				GameConfig.FORGE_MAX_ITEMS_PER_FIELD)
		target_count = mini(target_count, total - 3)
		var target_size := lerpf(36.0, 29.0, t)
		var distractor_size := lerpf(31.0, 24.0, t)
		var sep := LayoutSampler.separation_for(target_size * 1.06, 1.28)
		var positions := LayoutSampler.sample_field(rng, total, sep)
		var items: Array = []
		var cursor := 0
		for i in range(target_count):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, target_size, 0.06), "color": c1, "shape": s1,
						"is_target": true})
				cursor += 1
		for i in range(shape_match):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, distractor_size, 0.10), "color": c2, "shape": s1,
						"is_target": false})
				cursor += 1
		for i in range(color_match):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, distractor_size, 0.10), "color": c1, "shape": s2,
						"is_target": false})
				cursor += 1
		while cursor < total:
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, distractor_size, 0.10), "color": "WHITE", "shape": "square",
						"is_target": false})
				cursor += 1
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_COMBINED_CONDITIONAL,
				RuleBook.MULTI_ATTR_TEMPLATE % [c1, RuleBook.shape_plural(s1),
						c2, RuleBook.shape_plural(s1), c1, RuleBook.shape_plural(s2)],
				clampf(3.4 + 0.23 * float(total) * (1.0 - 0.30 * t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_COMBINED_CONDITIONAL, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "tap_targets"
		challenge.rule = "conjunction_search"
		challenge.correct_answer = target_count
		challenge.visual_data = {
				"items": items,
				"target_count": target_count,
				"sub_type": "multi_attribute_tap",
		}
		return challenge

## Variant B: shape majority - "MORE triangles than squares?", margin scaled
## by Weber fraction so the gap is always a fair fraction of the crowd.
static func _build_majority(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var s1 := str(book.next_from_pool("maj_shape", SHAPE_TARGET_POOL))
		var pool: Array = SHAPE_TARGET_POOL.duplicate()
		pool.erase(s1)
		var s2 := str(pool[rng.randi_range(0, pool.size() - 1)])
		var truth := book.take_flip("yn_truth")
		var base := int(round(lerpf(8.0, 14.0, t) * rng.randf_range(0.9, 1.15)))
		var margin := maxi(1, int(round(float(base) * lerpf(0.30, 0.10, t))))
		var count_a := base + margin if truth else base
		var count_b := base if truth else base + margin
		var size := lerpf(25.0, 21.0, t)
		var sep := LayoutSampler.separation_for(size * 1.08, 1.22)
		var positions := LayoutSampler.sample_field(rng, count_a + count_b, sep)
		var items: Array = []
		var cursor := 0
		for i in range(count_a):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, size, 0.08), "color": "MINT", "shape": s1})
				cursor += 1
		for i in range(count_b):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, size, 0.08), "color": "AMBER", "shape": s2})
				cursor += 1
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_COMBINED_CONDITIONAL,
				RuleBook.MAJORITY_TEMPLATE % [RuleBook.shape_plural(s1), RuleBook.shape_plural(s2)],
				clampf(lerpf(6.6, 4.8, t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_COMBINED_CONDITIONAL, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "choice"
		challenge.rule = "majority"
		challenge.options = ["YES", "NO"]
		challenge.correct_answer = "YES" if count_a > count_b else "NO"
		challenge.visual_data = {
				"items": items,
				"count_a": count_a,
				"count_b": count_b,
				"shape_a": s1,
				"shape_b": s2,
		}
		return challenge

## Variant C: colour threshold - "AT LEAST / AT MOST N RED dots?" The truth
## value is drawn from the fairness ledger first, then the count is
## constructed around the threshold at a difficulty-scaled distance.
static func _build_threshold(rng: RandomNumberGenerator, round_idx: int, t: float,
				band: int, book: RuleBook, run_seed: int) -> ChallengeDefinition:
		var color := str(book.next_from_pool("thr_color", ["RED", "BLUE", "YELLOW"]))
		var at_least := book.take_flip("thr_rule")
		var truth := book.take_flip("yn_truth")
		var distance := clampi(int(round(lerpf(6.0, 1.0, t))), 1, 6)
		var threshold := clampi(int(round(lerpf(9.0, 16.0, t))) + rng.randi_range(-2, 2), 5, 20)
		var actual: int
		if at_least:
				actual = threshold + distance if truth else maxi(2, threshold - distance)
		else:
				actual = maxi(2, threshold - distance) if truth else threshold + distance
		var is_yes := (actual >= threshold) if at_least else (actual <= threshold)
		var noise_count := int(round(lerpf(6.0, 12.0, t) * rng.randf_range(0.9, 1.15)))
		var size := lerpf(24.0, 19.0, t)
		var sep := LayoutSampler.separation_for(size * 1.10, 1.22)
		var positions := LayoutSampler.sample_field(rng, actual + noise_count, sep)
		var items: Array = []
		var cursor := 0
		for i in range(actual):
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, size, 0.10), "color": color, "shape": "circle"})
				cursor += 1
		while cursor < positions.size():
				items.append({"x": positions[cursor].x, "y": positions[cursor].y,
						"size": _sized(rng, size, 0.10), "color": "WHITE", "shape": "square"})
				cursor += 1
		_shuffle_with(rng, items)
		var challenge := ChallengeDefinition.new(
				"", GameConfig.TYPE_COMBINED_CONDITIONAL,
				RuleBook.THRESHOLD_TEMPLATE % ["AT LEAST" if at_least else "AT MOST", threshold, color],
				clampf(lerpf(6.6, 4.8, t),
						GameConfig.MIN_CHALLENGE_DURATION, GameConfig.MAX_CHALLENGE_DURATION))
		_stamp(challenge, GameConfig.TYPE_COMBINED_CONDITIONAL, rng, round_idx, t, band, run_seed)
		challenge.input_mode = "choice"
		challenge.rule = "threshold"
		challenge.options = ["YES", "NO"]
		challenge.correct_answer = "YES" if is_yes else "NO"
		challenge.visual_data = {
				"items": items,
				"count_target": actual,
				"threshold": threshold,
				"target_color": color,
		}
		return challenge

# --- shared helpers ------------------------------------------------------------------

static func _sized(rng: RandomNumberGenerator, base: float, jitter: float) -> float:
		return maxf(12.0, base * rng.randf_range(1.0 - jitter, 1.0 + jitter))

## Split a total across n parts as evenly as possible (front-loaded by one).
static func _split_quota(total: int, parts: int) -> Array:
		var out: Array = []
		var parts_safe := maxi(1, parts)
		var base := int(float(maxi(0, total)) / float(parts_safe))
		var remainder := maxi(0, total) % parts_safe
		for i in range(parts_safe):
				out.append(base + (1 if i < remainder else 0))
		return out

## Fisher-Yates bound to the round's RNG stream (Array.shuffle() would use
## the global RNG and break seed determinism).
static func _shuffle_with(rng: RandomNumberGenerator, arr: Array) -> void:
		for i in range(arr.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = arr[i]
				arr[i] = arr[j]
				arr[j] = tmp
