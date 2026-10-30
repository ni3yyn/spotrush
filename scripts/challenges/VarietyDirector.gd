class_name VarietyDirector
extends RefCounted

## v16 RUN FORGE - the sequencing brain.
##
## Builds a run's mini-game schedule with hard guarantees instead of a
## fixed rotation:
##   * no mini-game ever repeats back to back,
##   * every type gets its moment early (coverage permutation opens the run),
##   * the Go/No-Go inhibition beat never fires twice inside three rounds,
##   * the input rhythm (choice vs tap) never locks into three of a kind.
## After the coverage opening, a recency-penalised, deficit-biased weighted
## pick keeps the tail of long runs balanced without feeling mechanical.

## Friendly openers: readable choice rounds ease a player into a fresh run.
const STARTER_TYPES := [
        GameConfig.TYPE_COMPARISON_SIDES,
        GameConfig.TYPE_ESTIMATION_COUNT,
]

## Input rhythm class per type. COMBINED is the wildcard "twist" beat that
## breaks choice/tap runs on purpose.
const _MODE := {
        GameConfig.TYPE_ESTIMATION_COUNT: "choice",
        GameConfig.TYPE_COMPARISON_SIDES: "choice",
        GameConfig.TYPE_COLOR_TARGET: "tap",
        GameConfig.TYPE_SHAPE_TARGET: "tap",
        GameConfig.TYPE_DONT_TAP: "withhold",
        GameConfig.TYPE_COMBINED_CONDITIONAL: "twist",
}

## Base spin weight per type.
const _WEIGHT := {
        GameConfig.TYPE_ESTIMATION_COUNT: 1.0,
        GameConfig.TYPE_COMPARISON_SIDES: 1.1,
        GameConfig.TYPE_COLOR_TARGET: 1.0,
        GameConfig.TYPE_SHAPE_TARGET: 1.0,
        GameConfig.TYPE_DONT_TAP: 0.85,
        GameConfig.TYPE_COMBINED_CONDITIONAL: 1.15,
}

var _rng := RandomNumberGenerator.new()
var _total: int = 10

func _init(p_seed: int, p_total: int) -> void:
        _rng.seed = p_seed
        _total = maxi(1, p_total)

func build_schedule() -> Array:
        var all_types := _all_types()
        var schedule: Array = []
        if _total >= all_types.size():
                schedule = _coverage_prefix(all_types)
                while schedule.size() < _total:
                        schedule.append(_pick_weighted(schedule))
        else:
                # Short runs: distinct types, no repeats, rhythm-checked.
                var pool := all_types.duplicate()
                while schedule.size() < _total and not pool.is_empty():
                        var legal := []
                        for ctype in pool:
                                if _is_legal_next(str(ctype), schedule):
                                        legal.append(ctype)
                        if legal.is_empty():
                                legal = pool.duplicate()
                        var pick = legal[_rng.randi_range(0, legal.size() - 1)]
                        pool.erase(pick)
                        schedule.append(pick)
        return schedule

func _all_types() -> Array:
        var all_types: Array = []
        for key in _WEIGHT:
                all_types.append(key)
        return all_types

## Opening block: one permutation of every type, constraint-checked.
func _coverage_prefix(all_types: Array) -> Array:
        for attempt in 24:
                var prefix := all_types.duplicate()
                _shuffle(prefix)
                if _prefix_ok(prefix):
                        return prefix
        return _hand_built_prefix(all_types)

func _prefix_ok(prefix: Array) -> bool:
        if prefix.is_empty():
                return false
        if not str(prefix[0]) in STARTER_TYPES:
                return false
        for i in range(2):
                if i < prefix.size() and str(prefix[i]) == GameConfig.TYPE_DONT_TAP:
                        return false
        return _rhythm_ok(prefix)

func _hand_built_prefix(all_types: Array) -> Array:
        # Deterministic safe order built from the pool itself: a friendly starter,
        # then a preference walk that never trips the rhythm or opening rules.
        var prefix: Array = []
        var starter: String = STARTER_TYPES[_rng.randi_range(0, STARTER_TYPES.size() - 1)]
        prefix.append(starter)
        var preference := [
                GameConfig.TYPE_COLOR_TARGET,
                GameConfig.TYPE_ESTIMATION_COUNT,
                GameConfig.TYPE_SHAPE_TARGET,
                GameConfig.TYPE_COMBINED_CONDITIONAL,
                GameConfig.TYPE_DONT_TAP,
                GameConfig.TYPE_COMPARISON_SIDES,
        ]
        var remaining := all_types.duplicate()
        remaining.erase(starter)
        for wanted in preference:
                if remaining.is_empty():
                        break
                if wanted in remaining and _is_legal_next(str(wanted), prefix):
                        prefix.append(wanted)
                        remaining.erase(wanted)
        for leftover in remaining:
                prefix.append(leftover)
        return prefix

## Weighted tail pick: no immediate repeat, Go/No-Go pacing, mode runs capped
## at two, recency soft-penalised, deficit-biased toward under-served types.
func _pick_weighted(history: Array) -> String:
        var last := str(history[history.size() - 1]) if history.size() > 0 else ""
        var run_mode := _tail_mode_run(history)
        var gng_locked := _gonogo_locked(history)
        var total_weight := 0.0
        var scored: Array = []
        for ctype in _WEIGHT:
                var key := str(ctype)
                if key == last:
                        continue
                if key == GameConfig.TYPE_DONT_TAP and gng_locked:
                        continue
                if run_mode != "" and str(_MODE[key]) == run_mode:
                        continue
                var weight := float(_WEIGHT[key])
                var deficit := _deficit(key, history)
                weight *= clampf(1.0 + 0.9 * deficit, 0.35, 2.4)
                if _appears_in_tail(key, history, 3):
                        weight *= 0.45
                scored.append({"type": key, "w": weight})
                total_weight += weight
        if scored.is_empty():
                # Rhythm corner case: fall back to anything that is not a repeat.
                for ctype in _WEIGHT:
                        if str(ctype) != last:
                                return str(ctype)
                return GameConfig.TYPE_COMPARISON_SIDES
        var dart := _rng.randf() * total_weight
        for entry in scored:
                dart -= float(entry["w"])
                if dart <= 0.0:
                        return str(entry["type"])
        return str(scored[scored.size() - 1]["type"])

func _deficit(ctype: String, history: Array) -> float:
        var weight_sum := 0.0
        for w in _WEIGHT:
                weight_sum += float(_WEIGHT[w])
        var expected := float(_WEIGHT[ctype]) / maxf(weight_sum, 0.001) * float(history.size())
        var actual := 0
        for h in history:
                if str(h) == ctype:
                        actual += 1
        return expected - float(actual)

func _appears_in_tail(ctype: String, history: Array, tail: int) -> bool:
        var from_index := maxi(0, history.size() - tail)
        for i in range(from_index, history.size()):
                if str(history[i]) == ctype:
                        return true
        return false

## Mode at the tail if the last two rounds share one; "" when mixed.
func _tail_mode_run(history: Array) -> String:
        if history.size() < 2:
                return ""
        var m_a := str(_MODE[str(history[history.size() - 2])])
        var m_b := str(_MODE[str(history[history.size() - 1])])
        if m_a == m_b and (m_a == "choice" or m_a == "tap"):
                return m_a
        return ""

func _gonogo_locked(history: Array) -> bool:
        var from_index := maxi(0, history.size() - 2)
        for i in range(from_index, history.size()):
                if str(history[i]) == GameConfig.TYPE_DONT_TAP:
                        return true
        return false

func _rhythm_ok(sequence: Array) -> bool:
        for i in range(2, sequence.size()):
                if not _is_legal_next(str(sequence[i]), sequence.slice(0, i)):
                        return false
        return true

func _is_legal_next(ctype: String, history: Array) -> bool:
        if history.is_empty():
                return true
        if ctype == str(history[history.size() - 1]):
                return false
        if history.size() == 1:
                # Second slot: keep the inhibition beat out of the opening pair.
                return ctype != GameConfig.TYPE_DONT_TAP
        if ctype == GameConfig.TYPE_DONT_TAP and _gonogo_locked(history):
                return false
        var run_mode := _tail_mode_run(history)
        if run_mode != "" and str(_MODE[ctype]) == run_mode:
                return false
        return true

## Fisher-Yates bound to the director's own RNG stream (Array.shuffle()
## would use the global RNG and break seed determinism).
func _shuffle(arr: Array) -> void:
        for i in range(arr.size() - 1, 0, -1):
                var j := _rng.randi_range(0, i)
                var tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp
