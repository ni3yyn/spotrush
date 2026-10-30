class_name RuleBook
extends RefCounted

## v16 RUN FORGE - phrasing + fairness ledger.
##
## Two jobs. First: every instruction line is assembled from template pools
## so a run never reads like a looped recording. Second: every binary
## outcome stream (LEFT/RIGHT, YES/NO, MORE/FEWER, Go/No-Go state) is drawn
## through a balanced ledger - never three of a kind in a row, and the
## split never drifts past two - so the answer distribution cannot be gamed
## and no option is systematically favoured. Pools rotate least-used-first
## so every colour and shape gets its moment across a run.

const ESTIMATION_PHRASES := [
	"Quick! Estimate the mint dots:",
	"How many dots landed on the tray?",
	"Trust your eyes - roughly how many dots?",
	"The swarm is in. About how many?",
	"No counting one by one - estimate!",
]

const COMPARISON_MORE := [
	"Which side has MORE dots?",
	"More dots on the LEFT or on the RIGHT?",
	"Pick the tray with MORE dots:",
]

const COMPARISON_FEWER := [
	"Which side has FEWER dots?",
	"Fewer dots on the LEFT or on the RIGHT?",
	"Pick the tray with FEWER dots:",
]

const COLOR_TAP_TEMPLATES := [
	"Tap ALL %s circles! Ignore the rest.",
	"Only the %s ones count - tap them all!",
	"%s hunt: tap every %s circle!",
	"Find and tap every %s circle!",
]

const SHAPE_TAP_TEMPLATES := [
	"Tap ALL %s shapes!",
	"Shape hunt: tap every %s!",
	"Only %s count - tap them all!",
	"Sweep the tray and tap each %s!",
]

## Go/No-Go instructions must NEVER reveal whether RED is actually present;
## scanning the field is the whole challenge.
const GONOGO_PHRASES := [
	"Any RED out there? TAP only if all clear!",
	"Scan fast: spot RED and hold back. No red? TAP!",
	"RED means STOP. No red? TAP NOW!",
	"Go / No-Go: tap unless you see RED!",
]

## The confirm key label for Go/No-Go rounds - state-agnostic on purpose.
const GONOGO_KEY_LABEL := "SPOT RED? HOLD BACK! ELSE TAP NOW"

const MAJORITY_TEMPLATE := "Are there MORE %s than %s? YES or NO."

const THRESHOLD_TEMPLATE := "Are there %s %d %s dots? YES or NO."

const MULTI_ATTR_TEMPLATE := "Tap every %s %s! Ignore %s %s and %s %s."

var _rng := RandomNumberGenerator.new()
var _ledger := {}    # tag -> {bal, streak, last}
var _pool_use := {}  # pool name -> {value: times used}

func _init(p_seed: int) -> void:
	_rng.seed = p_seed

## Balanced binary stream. Guarantees: no three of a kind in a row, and
## once the running split drifts to two the minority is forced back.
func take_flip(tag: String) -> bool:
	var bal := 0
	var streak := 0
	var last := false
	if _ledger.has(tag):
		var st: Dictionary = _ledger[tag]
		bal = int(st["bal"])
		streak = int(st["streak"])
		last = bool(st["last"])
	var value: bool
	if streak >= 2:
		value = not last
	elif absi(bal) >= 2:
		value = bal < 0
	else:
		value = _rng.randf() < 0.5
	var next_streak := (streak + 1) if value == last else 1
	_ledger[tag] = {
		"bal": bal + (1 if value else -1),
		"streak": next_streak,
		"last": value,
	}
	return value

## Least-used pick from a pool (ties broken by the run's RNG) so colours
## and shapes spread evenly across the whole run.
func next_from_pool(pool_name: String, options: Array) -> Variant:
	var counts: Dictionary = _pool_use.get(pool_name, {})
	var min_c := 1 << 30
	var best: Array = []
	for opt in options:
		var c := int(counts.get(opt, 0))
		if c < min_c:
			min_c = c
			best = [opt]
		elif c == min_c:
			best.append(opt)
	var pick = best[_rng.randi_range(0, best.size() - 1)]
	counts[pick] = min_c + 1
	_pool_use[pool_name] = counts
	return pick

static func pick_phrase(rng: RandomNumberGenerator, pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)])

static func comparison_phrase(rng: RandomNumberGenerator, asking_more: bool) -> String:
	return pick_phrase(rng, COMPARISON_MORE if asking_more else COMPARISON_FEWER)

static func color_tap_phrase(rng: RandomNumberGenerator, color: String) -> String:
	var template := pick_phrase(rng, COLOR_TAP_TEMPLATES)
	if template.count("%s") >= 2:
		return template % [color, color]
	return template % color

static func shape_tap_phrase(rng: RandomNumberGenerator, shape: String) -> String:
	var template := pick_phrase(rng, SHAPE_TAP_TEMPLATES)
	return template % shape_plural(shape)

static func shape_plural(shape: String) -> String:
	match shape:
		"triangle":
			return "TRIANGLES"
		"square":
			return "SQUARES"
		"diamond":
			return "DIAMONDS"
		"circle":
			return "CIRCLES"
		_:
			return shape.to_upper() + "S"
