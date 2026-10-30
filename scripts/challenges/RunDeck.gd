class_name RunDeck
extends RefCounted

## v16 RUN FORGE - one run, forged whole.
##
## A RunDeck is a complete, reproducible run: a seed, a difficulty curve, a
## type schedule with variety guarantees, a fairness ledger and one
## independent RNG stream per round. Because every round's content is
## addressed by (seed, round index) rather than by a shared cursor, round 7
## never re-rolls because round 3 played out differently, and any seed
## replays the exact same series. Solo runs layer a performance momentum on
## top of the fixed curve (correct+fast climbs, misses ease off); daily and
## duel runs are pure curves, so the seed fully determines the series.
## Every generated round passes a quality gate (validity, bounds, overlap,
## option sanity, timing window) before it is ever handed to the match.

const MOMENTUM_DECAY: float = 0.82
const MOMENTUM_PUSH_FAST: float = 0.36
const MOMENTUM_PUSH_SLOW: float = 0.20
const MOMENTUM_PUSH_MISS: float = -0.34

var total_rounds: int = 10
var run_seed: int = 0
var adaptive: bool = false
var curve: DifficultyCurve = null
var schedule: Array = []
var book: RuleBook = null

var _memo := {}
var _momentum: float = 0.0

## Forge a fresh deck. p_seed <= 0 draws OS entropy, so every Play click
## deals a series nobody has ever seen before.
static func forge(p_rounds: int, p_seed: int, p_start_band: int, p_adaptive: bool,
		p_span: float = GameConfig.FORGE_RUN_SPAN) -> RunDeck:
	var deck := RunDeck.new()
	deck.total_rounds = maxi(1, p_rounds)
	deck.run_seed = p_seed if p_seed > 0 else fresh_seed()
	deck.adaptive = p_adaptive
	deck.curve = DifficultyCurve.new(p_start_band, deck.total_rounds, p_span)
	var director := VarietyDirector.new(_mix(deck.run_seed, 0, 0xD1CE), deck.total_rounds)
	deck.schedule = director.build_schedule()
	deck.book = RuleBook.new(_mix(deck.run_seed, 0, 0xB00C))
	return deck

## Fresh entropy: wall clock, monotonic ticks and the engine RNG stirred
## together, masked to a positive 31-bit seed.
static func fresh_seed() -> int:
	var h := int(Time.get_unix_time_from_system() * 1000.0) \
		^ (Time.get_ticks_usec() << 13) \
		^ randi()
	return int(h & 0x7FFFFFFF)

## Deal (or recall) one round. Memoized, quality-gated, stream-isolated.
func begin_round(index: int) -> ChallengeDefinition:
	var idx := clampi(index, 0, maxi(0, total_rounds - 1))
	if _memo.has(idx):
		return _memo[idx]
	var perf_started_usec: int = Time.get_ticks_usec() if OS.is_debug_build() else 0
	var attempts_used := 0
	var type := str(schedule[idx]) if idx < schedule.size() else GameConfig.TYPE_COMPARISON_SIDES
	var intensity := intensity_at(idx)
	var challenge: ChallengeDefinition = null
	for attempt in GameConfig.FORGE_QUALITY_ATTEMPTS:
		attempts_used = attempt + 1
		var rng := RandomNumberGenerator.new()
		rng.seed = _mix(run_seed, idx, 0xA0F1 + attempt * 7919)
		challenge = ChallengeFactory.build(rng, type, idx, intensity, book, run_seed)
		if _quality_ok(challenge):
			break
		challenge = null
	if challenge == null:
		# Safety net: a calm comparison round from the same machinery.
		var rng := RandomNumberGenerator.new()
		rng.seed = _mix(run_seed, idx, 0xFA11)
		challenge = ChallengeFactory.build(rng, GameConfig.TYPE_COMPARISON_SIDES,
			idx, minf(intensity, 1.0), book, run_seed)
	_memo[idx] = challenge
	if OS.is_debug_build():
		var elapsed_usec := Time.get_ticks_usec() - perf_started_usec
		if elapsed_usec >= 8000:
			print("[PERF] Challenge generation %s round %d: %.2f ms (%d quality attempt(s))" % [type, idx + 1, float(elapsed_usec) / 1000.0, attempts_used])
	return challenge

## Effective intensity of a round: the curve plus (adaptive runs only) live
## performance momentum, so the set list reacts to how the player is doing.
func intensity_at(index: int) -> float:
	var base := curve.intensity_at(index) if curve != null else 0.0
	if adaptive:
		base = clampf(base + _momentum * GameConfig.FORGE_ADAPT_GAIN, 0.0, 3.0)
	return base

## Feed one result back into the momentum (adaptive runs only).
func record_result(correct: bool, fast: bool) -> void:
	if not adaptive:
		return
	var push := MOMENTUM_PUSH_MISS
	if correct:
		push = MOMENTUM_PUSH_FAST if fast else MOMENTUM_PUSH_SLOW
	_momentum = clampf(_momentum * MOMENTUM_DECAY + push, -1.0, 1.0)

## Short human-readable fingerprint, handy for bug reports and replays.
func summary_line() -> String:
	return "RUN %06X - %d ROUNDS - %s" % [run_seed & 0xFFFFFF, total_rounds,
		"ADAPTIVE" if adaptive else "FIXED CURVE"]

## 32-bit avalanche stir so (seed, round, salt) gives independent streams.
static func _mix(a: int, b: int, salt: int) -> int:
	var h := (a ^ (b * 0x9E3779B1)) ^ (salt * 0x85EBCA6B)
	h ^= h >> 13
	h *= 0xC2B2AE35
	h ^= h >> 16
	return int(h & 0x7FFFFFFF)

# --- quality gate --------------------------------------------------------------------

func _quality_ok(challenge: ChallengeDefinition) -> bool:
	if challenge == null or not challenge.is_valid():
		return false
	if challenge.time_limit < GameConfig.MIN_CHALLENGE_DURATION - 0.01 \
			or challenge.time_limit > GameConfig.MAX_CHALLENGE_DURATION + 0.01:
		return false
	if challenge.visual_data.get("split_view", false):
		if not _items_ok(challenge, challenge.visual_data.get("left_items", [])):
			return false
		if not _items_ok(challenge, challenge.visual_data.get("right_items", [])):
			return false
	else:
		if not _items_ok(challenge, challenge.visual_data.get("items", [])):
			return false
	if challenge.input_mode == "choice":
		var found := false
		for opt in challenge.options:
			if str(opt) == str(challenge.correct_answer):
				found = true
				break
		if not found:
			return false
	return true

func _items_ok(challenge: ChallengeDefinition, items: Array) -> bool:
	if items.is_empty():
		return false
	if items.size() > GameConfig.FORGE_MAX_ITEMS_PER_FIELD:
		return false
	# Tokens are drawn ~1.28x their base size in tap rounds, ~1.22x in
	# counting rounds; the check runs against a conservative 300px field.
	var draw_scale := 1.28 if challenge.input_mode in ["tap_targets", "withhold_response"] else 1.22
	for i in range(items.size()):
		var a: Dictionary = items[i]
		if not _in_bounds(a):
			return false
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			var min_px := (float(a.get("size", 24.0)) + float(b.get("size", 24.0))) * 0.5 \
				* draw_scale * 0.88
			if Vector2(float(a["x"]), float(a["y"])).distance_to(
					Vector2(float(b["x"]), float(b["y"]))) * LayoutSampler.REF_WIDTH < min_px:
				return false
	return true

static func _in_bounds(item: Dictionary) -> bool:
	var x := float(item.get("x", -1.0))
	var y := float(item.get("y", -1.0))
	return x >= 0.04 and x <= 0.96 and y >= 0.06 and y <= 0.94
