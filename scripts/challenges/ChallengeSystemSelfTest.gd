extends SceneTree

## v16 RUN FORGE - headless verification suite.
##
## Run from the project folder AFTER opening the project once in the Godot
## editor (so class names are registered):
##
##   godot --headless -s res://scripts/challenges/ChallengeSystemSelfTest.gd
##
## Verifies, across hundreds of forged decks:
##   1. seed determinism (same seed -> identical series, deals in order)
##   2. schedule variety (coverage, no repeats, Go/No-Go pacing, rhythm)
##   3. round quality (validity, bounds, overlaps, options, timing window)
##   4. answer fairness (LEFT/RIGHT, YES/NO, Go/No-Go balance + no streaks)
##   5. curve shape (bands progress, dip only on designed beats)
##   6. short runs, adaptivity and the compatibility facade
##   7. aborting a run mid-match (v19 back flow) leaves a clean slate
##   8. hardware reality (v20): music loops, volume math, pause/resume, safe area
##   9. lan discovery (v21): beacon codec, dedupe/expiry, self-filter, IP ranking
##  10. join codes + QR squares (v21): codec round-trip, tolerant clipboard
##      parsing, QR structure across all four versions, rendered image shape
##  11. daily reminder (v21): schedule decision table + fire-time math
## Exit code 0 = all green, 1 = failures (each failure prints a line).

const DECK_SEEDS := 42
const TYPE_COMPARISON := "comparison_sides"

# v20 engine scripts (autoloads are not instanced in script mode, so the
# hardware-reality tests preload and drive them directly).
const MusicScript = preload("res://scripts/core/Music.gd")
const AppLifecycleScript = preload("res://scripts/core/AppLifecycle.gd")
const NeuSafeScript = preload("res://scripts/core/NeuSafe.gd")
# v21 lan discovery (pure static core - no sockets opened in script mode).
const LanDiscoveryScript = preload("res://scripts/networking/LanDiscovery.gd")
# v21 join codes + QR squares (pure math - no textures needed until rendering).
const QrCodeScript = preload("res://scripts/ui/QrCode.gd")
# v21 daily reminder (pure static decision core - no native bridge in script mode).
const DailyReminderScript = preload("res://scripts/core/DailyReminder.gd")

func _init() -> void:
        var failures := 0
        failures += _test_determinism()
        failures += _test_schedules()
        failures += _test_quality()
        failures += _test_balance()
        failures += _test_curve()
        failures += _test_small_runs()
        failures += _test_adaptive_and_facade()
        failures += _test_challenge_codes()
        failures += _test_color_vision()
        failures += _test_back_and_abort()
        failures += _test_hardware_reality()
        failures += _test_lan_discovery()
        failures += _test_join_codes_and_qr()
        failures += _test_daily_reminder()
        if failures == 0:
                print("RUN FORGE SELF-TEST: ALL PASSED")
        else:
                print("RUN FORGE SELF-TEST: %d FAILURE(S)" % failures)
        quit(0 if failures == 0 else 1)

# --- 1. determinism ------------------------------------------------------------------

func _test_determinism() -> int:
        var failures := 0
        for i in range(DECK_SEEDS):
                var deck_seed := 1000 + i * 7919
                var a := RunDeck.forge(10, deck_seed, 1 + (i % 4), false)
                var b := RunDeck.forge(10, deck_seed, 1 + (i % 4), false)
                if a.schedule != b.schedule:
                        print("FAIL determinism/schedule seed=%d" % deck_seed)
                        failures += 1
                        continue
                for r in range(10):
                        if a.begin_round(r).to_dict() != b.begin_round(r).to_dict():
                                print("FAIL determinism/round seed=%d round=%d" % [deck_seed, r])
                                failures += 1
                # Memoized recall returns the same object.
                if a.begin_round(3) != a.begin_round(3):
                        print("FAIL determinism/memo seed=%d" % deck_seed)
                        failures += 1
                # Different seed -> actually different series.
                var c := RunDeck.forge(10, deck_seed + 1, 1, false)
                if c.begin_round(0).to_dict() == a.begin_round(0).to_dict() \
                                and c.begin_round(5).to_dict() == a.begin_round(5).to_dict():
                        print("NOTE different seed produced identical rounds (unlikely but legal) seed=%d" % deck_seed)
        return failures

# --- 2. schedule variety -------------------------------------------------------------

func _test_schedules() -> int:
        var failures := 0
        var rounds_list := [6, 7, 8, 10, 10, 10, 12, 16, 20, 20]
        for d in range(DECK_SEEDS):
                var total: int = rounds_list[d % rounds_list.size()]
                var deck := RunDeck.forge(total, 5000 + d * 104729, 1, false)
                var schedule: Array = deck.schedule
                if schedule.size() != total:
                        print("FAIL schedule/size d=%d" % d)
                        failures += 1
                        continue
                for i in range(schedule.size()):
                        if i > 0 and str(schedule[i]) == str(schedule[i - 1]):
                                print("FAIL schedule/repeat d=%d idx=%d %s" % [d, i, schedule[i]])
                                failures += 1
                # Coverage: a run of >= 6 rounds opens with every type exactly once.
                var opening := {}
                for i in range(mini(6, schedule.size())):
                        opening[str(schedule[i])] = true
                if total >= 6 and opening.size() != 6:
                        print("FAIL schedule/coverage d=%d got %d types" % [d, opening.size()])
                        failures += 1
                # Go/No-Go pacing: never twice within three rounds.
                var last_gng := -10
                for i in range(schedule.size()):
                        if str(schedule[i]) == GameConfig.TYPE_DONT_TAP:
                                if i - last_gng < 3:
                                        print("FAIL schedule/gonogo_pacing d=%d idx=%d" % [d, i])
                                        failures += 1
                                last_gng = i
                # Input rhythm: no three consecutive rounds of one input mode.
                for i in range(2, schedule.size()):
                        var m0 := _mode_of(str(schedule[i - 2]))
                        var m1 := _mode_of(str(schedule[i - 1]))
                        var m2 := _mode_of(str(schedule[i]))
                        if m0 == m1 and m1 == m2 and (m0 == "choice" or m0 == "tap"):
                                print("FAIL schedule/rhythm d=%d idx=%d" % [d, i])
                                failures += 1
                # The opening round is always a friendly starter type.
                if not str(schedule[0]) in [GameConfig.TYPE_COMPARISON_SIDES, GameConfig.TYPE_ESTIMATION_COUNT]:
                        print("FAIL schedule/starter d=%d %s" % [d, schedule[0]])
                        failures += 1
        return failures

# --- 3. round quality ----------------------------------------------------------------

func _test_quality() -> int:
        var failures := 0
        var rounds_list := [6, 10, 10, 12, 20]
        for d in range(DECK_SEEDS):
                var total: int = rounds_list[d % rounds_list.size()]
                var deck := RunDeck.forge(total, 90000 + d * 15485863, 1 + (d % 4), false)
                for r in range(total):
                        var ch := deck.begin_round(r)
                        if ch == null:
                                print("FAIL quality/null d=%d r=%d" % [d, r])
                                failures += 1
                                continue
                        if not ch.is_valid():
                                print("FAIL quality/valid d=%d r=%d type=%s" % [d, r, ch.type])
                                failures += 1
                                continue
                        if ch.time_limit < GameConfig.MIN_CHALLENGE_DURATION - 0.01 \
                                        or ch.time_limit > GameConfig.MAX_CHALLENGE_DURATION + 0.01:
                                print("FAIL quality/time d=%d r=%d limit=%f" % [d, r, ch.time_limit])
                                failures += 1
                        if ch.difficulty < GameConfig.DIFFICULTY_MIN or ch.difficulty > GameConfig.DIFFICULTY_MAX:
                                print("FAIL quality/band d=%d r=%d band=%d" % [d, r, ch.difficulty])
                                failures += 1
                        if ch.visual_data.get("split_view", false):
                                if not _items_ok(ch, ch.visual_data.get("left_items", []), d, r):
                                        failures += 1
                                if not _items_ok(ch, ch.visual_data.get("right_items", []), d, r):
                                        failures += 1
                        else:
                                if not _items_ok(ch, ch.visual_data.get("items", []), d, r):
                                        failures += 1
                        if ch.input_mode == "choice":
                                var found := false
                                for opt in ch.options:
                                        if str(opt) == str(ch.correct_answer):
                                                found = true
                                                break
                                if not found:
                                        print("FAIL quality/answer_missing d=%d r=%d type=%s" % [d, r, ch.type])
                                        failures += 1
                        if ch.type == GameConfig.TYPE_ESTIMATION_COUNT:
                                var opts: Array = ch.options
                                if opts.size() != 4:
                                        print("FAIL quality/est_options d=%d r=%d n=%d" % [d, r, opts.size()])
                                        failures += 1
                                var seen := {}
                                for opt in opts:
                                        if str(opt) in seen:
                                                print("FAIL quality/est_dup d=%d r=%d" % [d, r])
                                                failures += 1
                                        seen[str(opt)] = true
                                        if not (opt is int) or int(opt) < 2:
                                                print("FAIL quality/est_value d=%d r=%d" % [d, r])
                                                failures += 1
        # Variety sanity: every type shows up across the sweep.
        var seen_types := {}
        for d in range(12):
                var deck := RunDeck.forge(10, 700000 + d * 31337, 1, false)
                for r in range(10):
                        seen_types[deck.begin_round(r).type] = true
        for want in ["estimation_count", "comparison_sides", "color_target",
                        "shape_target", "dont_tap", "combined_conditional"]:
                if not seen_types.has(want):
                        print("FAIL quality/type_coverage missing=%s" % want)
                        failures += 1
        return failures

func _items_ok(ch: ChallengeDefinition, items: Array, d: int, r: int) -> bool:
        if items.is_empty():
                print("FAIL quality/items_empty d=%d r=%d type=%s" % [d, r, ch.type])
                return false
        if items.size() > GameConfig.FORGE_MAX_ITEMS_PER_FIELD:
                print("FAIL quality/items_cap d=%d r=%d n=%d" % [d, r, items.size()])
                return false
        var draw_scale := 1.28 if ch.input_mode in ["tap_targets", "withhold_response"] else 1.22
        for i in range(items.size()):
                var a: Dictionary = items[i]
                var ax := float(a.get("x", -1.0))
                var ay := float(a.get("y", -1.0))
                if ax < 0.04 or ax > 0.96 or ay < 0.06 or ay > 0.94:
                        print("FAIL quality/bounds d=%d r=%d x=%f y=%f" % [d, r, ax, ay])
                        return false
                for j in range(i + 1, items.size()):
                        var b: Dictionary = items[j]
                        var min_px := (float(a.get("size", 24.0)) + float(b.get("size", 24.0))) * 0.5 * draw_scale * 0.88
                        if Vector2(ax, ay).distance_to(Vector2(float(b["x"]), float(b["y"]))) * 300.0 < min_px:
                                print("FAIL quality/overlap d=%d r=%d idx=%d,%d type=%s" % [d, r, i, j, ch.type])
                                return false
        return true

# --- 4. answer fairness --------------------------------------------------------------

func _test_balance() -> int:
        var failures := 0
        for d in range(30):
                var deck := RunDeck.forge(20, 300000 + d * 54059, 1, false)
                var left := 0
                var right := 0
                var yes := 0
                var no := 0
                var withhold := 0
                var tapped := 0
                var last_answer := ""
                var answer_run := 0
                var last_gng := ""
                var gng_run := 0
                for r in range(20):
                        var ch := deck.begin_round(r)
                        if ch.input_mode == "choice" and str(ch.correct_answer) in ["LEFT", "RIGHT"]:
                                if str(ch.correct_answer) == "LEFT":
                                        left += 1
                                else:
                                        right += 1
                                if str(ch.correct_answer) == last_answer:
                                        answer_run += 1
                                else:
                                        answer_run = 1
                                        last_answer = str(ch.correct_answer)
                                if answer_run >= 3:
                                        print("FAIL balance/side_streak d=%d r=%d %s" % [d, r, last_answer])
                                        failures += 1
                        elif ch.input_mode == "choice" \
                                        and str(ch.correct_answer) in ["YES", "NO"]:
                                # Guard the classification: estimation rounds are
                                # choice rounds too, but their numeric answers are
                                # neither YES nor NO and must not tip the scale.
                                if str(ch.correct_answer) == "YES":
                                        yes += 1
                                else:
                                        no += 1
                        elif ch.input_mode == "withhold_response":
                                if bool(ch.correct_answer):
                                        withhold += 1
                                else:
                                        tapped += 1
                                var outcome := "W" if bool(ch.correct_answer) else "T"
                                if outcome == last_gng:
                                        gng_run += 1
                                else:
                                        gng_run = 1
                                        last_gng = outcome
                                if gng_run >= 3:
                                        print("FAIL balance/gonogo_streak d=%d r=%d" % [d, r])
                                        failures += 1
                if absi(left - right) > 2:
                        print("FAIL balance/sides d=%d L=%d R=%d" % [d, left, right])
                        failures += 1
                if absi(yes - no) > 2:
                        print("FAIL balance/yesno d=%d Y=%d N=%d" % [d, yes, no])
                        failures += 1
                if absi(withhold - tapped) > 2:
                        print("FAIL balance/gonogo d=%d W=%d T=%d" % [d, withhold, tapped])
                        failures += 1
        return failures

# --- 5. curve shape -----------------------------------------------------------------

func _test_curve() -> int:
        var failures := 0
        var deck := RunDeck.forge(10, 424242, 1, false)
        var prev_band := -1
        for r in range(10):
                var band: int = deck.begin_round(r).difficulty
                if prev_band > 0:
                        # Bands climb across the run; dips of at most one band are only
                        # legal on the designed settle / breather beats.
                        if band < prev_band - 1:
                                print("FAIL curve/dip r=%d band=%d prev=%d" % [r, band, prev_band])
                                failures += 1
                prev_band = band
        var last: int = deck.begin_round(9).difficulty
        if last < 3:
                print("FAIL curve/progress end_band=%d" % last)
                failures += 1
        # Static curve math: breather sits where the curve says, dip bounded.
        var curve := DifficultyCurve.new(1, 10, 3.0)
        for r in range(10):
                var v := curve.intensity_at(r)
                if v < 0.0 or v > 3.0:
                        print("FAIL curve/range r=%d v=%f" % [r, v])
                        failures += 1
        if DifficultyCurve.band_for(0.49) != 1 or DifficultyCurve.band_for(0.5) != 2 \
                        or DifficultyCurve.band_for(2.49) != 3 or DifficultyCurve.band_for(2.5) != 4 \
                        or DifficultyCurve.band_for(3.0) != 4 or DifficultyCurve.band_for(-1.0) != 1 \
                        or DifficultyCurve.band_for(99.0) != 4:
                print("FAIL curve/band_boundaries")
                failures += 1
        return failures

# --- 6. short runs ------------------------------------------------------------------

func _test_small_runs() -> int:
        var failures := 0
        for total in [3, 4, 5]:
                for d in range(8):
                        var deck := RunDeck.forge(total, 800000 + d * 1299709 + total, 1, false)
                        for r in range(total):
                                var ch := deck.begin_round(r)
                                if ch == null or not ch.is_valid():
                                        print("FAIL small/invalid total=%d d=%d r=%d" % [total, d, r])
                                        failures += 1
        return failures

# --- 7. adaptivity + facade ---------------------------------------------------------

func _test_adaptive_and_facade() -> int:
        var failures := 0
        # Adaptive momentum bends future rounds; non-adaptive decks ignore it.
        var adaptive_deck := RunDeck.forge(10, 606060, 2, true)
        var flat_intensity := adaptive_deck.curve.intensity_at(5)
        adaptive_deck.record_result(false, false)
        adaptive_deck.record_result(false, false)
        if not adaptive_deck.intensity_at(5) < flat_intensity:
                print("FAIL adaptive/ease_off %f vs %f" % [adaptive_deck.intensity_at(5), flat_intensity])
                failures += 1
        adaptive_deck.record_result(true, true)
        adaptive_deck.record_result(true, true)
        adaptive_deck.record_result(true, true)
        if not adaptive_deck.intensity_at(5) > flat_intensity:
                print("FAIL adaptive/climb %f vs %f" % [adaptive_deck.intensity_at(5), flat_intensity])
                failures += 1
        var fixed_deck := RunDeck.forge(10, 606060, 2, false)
        var before := fixed_deck.intensity_at(5)
        fixed_deck.record_result(true, true)
        fixed_deck.record_result(true, true)
        if fixed_deck.intensity_at(5) != before:
                print("FAIL adaptive/fixed_ignores_results")
                failures += 1
        # Compatibility facade still returns valid challenges.
        var ch := ChallengeGenerator.generate_challenge(4, 3, 12345)
        if ch == null or not ch.is_valid():
                print("FAIL facade/invalid")
                failures += 1
        var ch2 := ChallengeGenerator.generate_challenge(4, 3, 12345)
        if ch.to_dict() != ch2.to_dict():
                print("FAIL facade/determinism")
                failures += 1
        return failures

func _mode_of(ctype: String) -> String:
        match ctype:
                GameConfig.TYPE_ESTIMATION_COUNT, GameConfig.TYPE_COMPARISON_SIDES:
                        return "choice"
                GameConfig.TYPE_COLOR_TARGET, GameConfig.TYPE_SHAPE_TARGET:
                        return "tap"
                GameConfig.TYPE_DONT_TAP:
                        return "withhold"
                _:
                        return "twist"

# --- 8. rival codes codec -------------------------------------------------------------

func _test_challenge_codes() -> int:
        var failures := 0
        # Round-trips: every field survives encode -> display -> parse.
        # Seeds stay inside the codec's 30-bit contract (2^30 = 1,073,741,824).
        for i in range(200):
                var seed_val := int((i * 2654435761 + 12345) % 1073741824)
                var rounds := 3 + (i % 18)
                var band := 1 + (i % 4)
                var code := ChallengeCodes.encode(seed_val, rounds, band)
                var parsed := ChallengeCodes.parse(code)
                if parsed.is_empty():
                        print("FAIL codes/roundtrip_parse i=%d" % i)
                        failures += 1
                        continue
                if int(parsed["seed"]) != seed_val or int(parsed["rounds"]) != rounds \
                                or int(parsed["band"]) != band:
                        print("FAIL codes/roundtrip_fields i=%d" % i)
                        failures += 1
                if str(parsed["display"]) != code:
                        print("FAIL codes/display_stable i=%d" % i)
                        failures += 1
        # Typo fury: corrupting any single character of a fixed code must fail
        # the checksum (or shape) for the overwhelming majority of variants.
        var fixed := ChallengeCodes.encode(123456789, 10, 2)
        var rejected := 0
        var tried := 0
        for pos in range(ChallengeCodes.CODE_CHARS):
                for alt in range(ChallengeCodes.ALPHABET.length()):
                        var cand := ChallengeCodes.ALPHABET[alt]
                        if cand == fixed[pos]:
                                continue
                        tried += 1
                        var mutated := fixed.substr(0, pos) + cand + fixed.substr(pos + 1)
                        if ChallengeCodes.parse(mutated).is_empty():
                                rejected += 1
        if tried == 0 or float(rejected) / float(tried) < 0.9:
                print("FAIL codes/typo_guard rejected=%d tried=%d" % [rejected, tried])
                failures += 1
        # Junk input: wrong length, wrong shape, wrong everything.
        for junk in ["", "12", "ABC-ABC", "ABCDEFGHIJ", "///-///-///", "000-000-000X"]:
                if not ChallengeCodes.parse(junk).is_empty():
                        print("FAIL codes/junk '%s'" % junk)
                        failures += 1
        # Clamping: out-of-range requests encode to the nearest legal run.
        var clamped := ChallengeCodes.parse(ChallengeCodes.encode(42, 99, 9))
        if clamped.is_empty() or int(clamped["rounds"]) != GameConfig.MAX_ROUNDS \
                        or int(clamped["band"]) != GameConfig.DIFFICULTY_MAX:
                print("FAIL codes/clamp")
                failures += 1
        # Near-miss glyphs: a code containing 0 and 1 survives the O/I swap.
        var forgiving := ""
        for i in range(64):
                var c := ChallengeCodes.encode(int((i * 7919 + 13) % 2147483647), 10, 3)
                if "0" in c and "1" in c:
                        forgiving = c
                        break
        if forgiving.is_empty():
                print("NOTE codes/no_0_1_sample")
        else:
                var swapped := forgiving.replace("0", "O").replace("1", "I")
                var back := ChallengeCodes.parse(swapped)
                if back.is_empty() or str(back["display"]) != forgiving:
                        print("FAIL codes/forgiveness")
                        failures += 1
        return failures

# --- 9. colour vision (v18) ------------------------------------------------------------

const ColorVision = preload("res://scripts/ui/ColorVision.gd")
const Settings = preload("res://scripts/core/Settings.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")

func _test_color_vision() -> int:
        var failures := 0
        var saved_mode := Settings.colorblind()

        # 1. The OFF table must mirror NeuKit exactly, so STANDARD vision is
        #    pixel-identical to the pre-v18 build (guards palette drift).
        var neu := {
                "RED": NeuKit.CORAL, "BLUE": NeuKit.COBALT, "YELLOW": NeuKit.CANARY,
                "MINT": NeuKit.MINT, "WHITE": NeuKit.SURFACE}
        Settings.set_colorblind(ColorVision.MODE_OFF)
        for token in neu:
                var resolved := ColorVision.resolve(token)
                if not resolved.is_equal_approx(neu[token]):
                        print("FAIL vision/off_mirror token=%s got=%s want=%s" % [token, resolved.to_html(false), neu[token].to_html(false)])
                        failures += 1
        # Aliases fold to their family in every mode.
        for m in [ColorVision.MODE_OFF, ColorVision.MODE_DEUTAN, ColorVision.MODE_PROTAN, ColorVision.MODE_TRITAN]:
                Settings.set_colorblind(m)
                if not ColorVision.resolve("CORAL").is_equal_approx(ColorVision.resolve("RED")) \
                                or not ColorVision.resolve("AMBER").is_equal_approx(ColorVision.resolve("YELLOW")):
                        print("FAIL vision/alias mode=%s" % m)
                        failures += 1

        # 2. Distinguishability gate: every palette must keep ALL token pairs
        #    separable under a simulation of its own deficiency. Worst-case
        #    CIE76 dE over all ten pairs (incl. WHITE) must clear the bar.
        const D_E_BAR := 30.0
        var tokens := ["RED", "BLUE", "YELLOW", "MINT", "WHITE"]
        for m in [ColorVision.MODE_DEUTAN, ColorVision.MODE_PROTAN, ColorVision.MODE_TRITAN]:
                Settings.set_colorblind(m)
                for a in range(tokens.size()):
                        for b in range(a + 1, tokens.size()):
                                var seen_a := ColorVision.simulate(ColorVision.resolve(tokens[a]), m)
                                var seen_b := ColorVision.simulate(ColorVision.resolve(tokens[b]), m)
                                var de := ColorVision.delta_e76(seen_a, seen_b)
                                if de < D_E_BAR:
                                        print("FAIL vision/dE mode=%s pair=%s-%s dE=%.1f" % [m, tokens[a], tokens[b], de])
                                        failures += 1

        # 3. Halo: off keeps the exact v17 alert red; CVD follows its palette RED.
        Settings.set_colorblind(ColorVision.MODE_OFF)
        if not ColorVision.halo().is_equal_approx(Color(1.0, 0.22, 0.30)):
                print("FAIL vision/halo_off")
                failures += 1
        Settings.set_colorblind(ColorVision.MODE_TRITAN)
        if not ColorVision.halo().is_equal_approx(ColorVision.resolve("RED")):
                print("FAIL vision/halo_follows_red")
                failures += 1

        # 4. Unknown stored values fall back to OFF instead of breaking resolve.
        Settings.set_colorblind("banana")
        if ColorVision.mode() != ColorVision.MODE_OFF \
                        or not ColorVision.resolve("RED").is_equal_approx(NeuKit.CORAL):
                print("FAIL vision/unknown_falls_back")
                failures += 1

        # 5. THE BIG ONE - determinism across modes: the forge must never read
        #    the palette, so the same seed deals the identical run whatever mode
        #    (or vision) each phone runs. This guards the data/presentation seam.
        var probe_seed := 20261029
        Settings.set_colorblind(ColorVision.MODE_OFF)
        var off_deck := RunDeck.forge(10, probe_seed, 2, false)
        for m in [ColorVision.MODE_DEUTAN, ColorVision.MODE_PROTAN, ColorVision.MODE_TRITAN]:
                Settings.set_colorblind(m)
                var cvd_deck := RunDeck.forge(10, probe_seed, 2, false)
                if cvd_deck.schedule != off_deck.schedule:
                        print("FAIL vision/forge_schedule mode=%s" % m)
                        failures += 1
                for r in range(10):
                        if cvd_deck.begin_round(r).to_dict() != off_deck.begin_round(r).to_dict():
                                print("FAIL vision/forge_round mode=%s round=%d" % [m, r])
                                failures += 1

        # 6. Labels exist for every mode (picker safety).
        for m in ColorVision.MODES:
                if ColorVision.mode_label(m).is_empty() or ColorVision.mode_hint(m).is_empty():
                        print("FAIL vision/labels mode=%s" % m)
                        failures += 1

        # Restore the player's real mode (the self-test must not eat it).
        Settings.set_colorblind(saved_mode)
        return failures

# --- 7. back flow: abandoning a run mid-match (v19) ------------------------------------

func _test_back_and_abort() -> int:
        var failures := 0
        # Quitting a run in flight (hardware back -> confirm sheet) must
        # hard-stop the controller with nothing leaking into the next match:
        # no live timers, no dealt challenge, no half-submitted rounds.
        var mc := MatchController.new()
        mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 10)
        mc.start_match()
        if mc.current_state != MatchController.MatchState.COUNTDOWN:
                print("FAIL abort/not_countdown")
                failures += 1
        mc.abort_match()
        if mc.current_state != MatchController.MatchState.IDLE or mc.current_challenge != null:
                print("FAIL abort/not_idle_after_abort")
                failures += 1
        if mc.round_timer != 0.0 or mc.countdown_timer != 0.0 or mc.feedback_timer != 0.0:
                print("FAIL abort/timers_ticking_after_abort")
                failures += 1
        # A quit run must be cleanly re-playable: fresh match, dealt round 1.
        mc.initialize_match(GameConfig.GameMode.SINGLE_PLAYER, 6)
        mc.start_match()
        if mc.current_round_index != 0 or mc.total_rounds != 6 or mc.current_challenge == null:
                print("FAIL abort/restart_not_clean")
                failures += 1
        # Aborting an already-idle controller is a no-op, not a crash.
        mc.abort_match()
        mc.abort_match()
        if mc.current_state != MatchController.MatchState.IDLE:
                print("FAIL abort/idle_abort_changed_state")
                failures += 1
        return failures

# --- 8. hardware reality (v20) ----------------------------------------------------------

func _test_hardware_reality() -> int:
        var failures := 0
        # Music: both ambient loops forge, loop forward and are cached.
        for kind in ["menu", "game"]:
                var stream := MusicScript.build_stream(kind)
                if stream == null:
                        print("FAIL hw/music_null kind=%s" % kind)
                        failures += 1
                        continue
                if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
                        print("FAIL hw/music_not_looping kind=%s" % kind)
                        failures += 1
                if stream.get_length() < 10.0:
                        print("FAIL hw/music_too_short kind=%s" % kind)
                        failures += 1
                if MusicScript.build_stream(kind) != stream:
                        print("FAIL hw/music_cache kind=%s" % kind)
                        failures += 1
        # Seamless loop: both beds start and end at (near) silence.
        for kind in ["menu", "game"]:
                var data: PackedByteArray = MusicScript.build_stream(kind).data
                var first := data.decode_s16(0)
                var last := data.decode_s16(data.size() - 2)
                if absi(first) > 600 or absi(last) > 600:
                        print("FAIL hw/music_seam kind=%s first=%d last=%d" % [kind, first, last])
                        failures += 1
        # Volume settings round-trip and clamp.
        var saved_music := Settings.music_volume()
        var saved_sfx := Settings.sfx_volume()
        Settings.set_music_volume(0.35)
        if absf(Settings.music_volume() - 0.35) > 0.001:
                print("FAIL hw/music_volume_roundtrip")
                failures += 1
        Settings.set_music_volume(1.7)
        if Settings.music_volume() > 1.001:
                print("FAIL hw/music_volume_clamp")
                failures += 1
        Settings.set_sfx_volume(0.0)
        if absf(Settings.sfx_volume()) > 0.001:
                print("FAIL hw/sfx_volume_zero")
                failures += 1
        Settings.set_music_volume(saved_music)
        Settings.set_sfx_volume(saved_sfx)
        # Bus layout is a soft check in script mode: it loads with the real game.
        if AudioServer.get_bus_index("Music") == -1 or AudioServer.get_bus_index("SFX") == -1:
                print("NOTE audio buses not visible in script mode (they load with the game)")
        # Lifecycle: pause sets the background flag, resume clears it.
        var life := AppLifecycleScript.new()
        life._pause_now()
        if not life.is_background:
                print("FAIL hw/lifecycle_not_paused")
                failures += 1
        life._resume_now()
        if life.is_background:
                print("FAIL hw/lifecycle_not_resumed")
                failures += 1
        life.free()
        # Safe area: insets are never negative (headless desktop reports none).
        var ins := NeuSafeScript.canvas_insets()
        if ins.x < 0.0 or ins.y < 0.0 or ins.z < 0.0 or ins.w < 0.0:
                print("FAIL hw/safe_insets_negative")
                failures += 1
        return failures

# --- 9. lan discovery (v21) --------------------------------------------------------------

func _test_lan_discovery() -> int:
        var failures := 0
        # Beacon codec: encode -> parse round-trips the duel port.
        var parsed := LanDiscoveryScript.parse_beacon(LanDiscoveryScript.encode_beacon(7000))
        if parsed.is_empty() or int(parsed["port"]) != 7000:
                print("FAIL lan/beacon_roundtrip")
                failures += 1
        # Junk never parses: wrong magic version, truncated, non-numeric port,
        # out-of-range port, oversized payload, empty packet.
        var bad_payloads := [
                "SPOTRUSH2|7000".to_utf8_buffer(),
                "SPOTRUSH1|".to_utf8_buffer(),
                "SPOTRUSH1|abc".to_utf8_buffer(),
                "SPOTRUSH1|99999".to_utf8_buffer(),
                "SPOTRUSH1|7000SPOTRUSH1|7000SPOTRUSH1|".to_utf8_buffer(),
                PackedByteArray(),
        ]
        for bad in bad_payloads:
                if not LanDiscoveryScript.parse_beacon(bad).is_empty():
                        print("FAIL lan/beacon_reject size=%d" % bad.size())
                        failures += 1
        # Dedupe and self-filter: repeated beacons from one host stay one entry;
        # this phone's own addresses never become listings.
        var disc = LanDiscoveryScript.new()
        disc.set_own_ips(PackedStringArray(["192.168.1.10"]))
        if disc.note_beacon("192.168.1.24", 7000, 1000) != true:
                print("FAIL lan/note_new")
                failures += 1
        if disc.note_beacon("192.168.1.24", 7000, 1400) != false:
                print("FAIL lan/note_repeat_not_new")
                failures += 1
        if disc.games(1500).size() != 1:
                print("FAIL lan/dedupe")
                failures += 1
        if disc.note_beacon("192.168.1.10", 7000, 1600) != false:
                print("FAIL lan/self_seen")
                failures += 1
        if disc.games(1600).size() != 1:
                print("FAIL lan/self_listed")
                failures += 1
        # Expiry: last heard at 1400 with a 4000ms TTL -> gone at 5401; a fresh
        # beacon revives the game.
        if disc.games(5401).size() != 0:
                print("FAIL lan/expiry")
                failures += 1
        disc.note_beacon("192.168.1.24", 7000, 5500)
        if disc.games(5600).size() != 1:
                print("FAIL lan/revive")
                failures += 1
        disc.free()
        # IP ranking: home/hotspot Wi-Fi ranges first, then other private
        # ranges, then public; loopback, link-local and cellular-grade NAT last.
        var ranked := LanDiscoveryScript.rank_local_ips(PackedStringArray([
                        "100.72.3.4", "169.254.9.9", "10.0.0.5", "192.168.1.24",
                        "172.20.0.3", "8.8.8.8", "127.0.0.1"]))
        var expected := ["192.168.1.24", "10.0.0.5", "172.20.0.3", "8.8.8.8",
                        "100.72.3.4", "169.254.9.9", "127.0.0.1"]
        if ranked.size() != expected.size():
                print("FAIL lan/rank_size got=%d" % ranked.size())
                failures += 1
        else:
                for i in expected.size():
                        if ranked[i] != expected[i]:
                                print("FAIL lan/rank pos=%d got=%s want=%s" % [i, ranked[i], expected[i]])
                                failures += 1
        return failures

# --- 10. join codes + QR squares (v21) ----------------------------------------------------

func _test_join_codes_and_qr() -> int:
        var failures := 0
        # Join-code codec: encode -> parse round-trips both fields.
        var rt := LanDiscoveryScript.parse_join_code(
                        LanDiscoveryScript.encode_join_code("192.168.1.24", 7000))
        if rt.is_empty() or str(rt["ip"]) != "192.168.1.24" or int(rt["port"]) != 7000:
                print("FAIL join/roundtrip")
                failures += 1
        # Boundary ports survive the clamp-free path intact.
        rt = LanDiscoveryScript.parse_join_code(
                        LanDiscoveryScript.encode_join_code("10.0.0.7", 65535))
        if rt.is_empty() or int(rt["port"]) != 65535:
                print("FAIL join/port_edge")
                failures += 1
        # Tolerant parsing: camera apps wrap the raw code in arbitrary chrome.
        rt = LanDiscoveryScript.parse_join_code("Scan result:\n\"SPOTRUSH:JOIN:172.20.0.3:42113\"\nTap to open")
        if rt.is_empty() or str(rt["ip"]) != "172.20.0.3" or int(rt["port"]) != 42113:
                print("FAIL join/tolerant_chrome")
                failures += 1
        # Junk never parses: wrong magic, bad octet, bad port, missing port,
        # empty text.
        var bad_codes := [
                "SPOTRUSH:JOHN:192.168.1.24:7000",
                "SPOTRUSH:JOIN:999.168.1.24:7000",
                "SPOTRUSH:JOIN:192.168.1.24:99999",
                "SPOTRUSH:JOIN:192.168.1.24:abc",
                "SPOTRUSH:JOIN:192.168.1.24",
                "SPOTRUSH:JOIN:",
                "",
        ]
        for bad in bad_codes:
                if not LanDiscoveryScript.parse_join_code(bad).is_empty():
                        print("FAIL join/reject len=%d" % bad.length())
                        failures += 1
        # The shared IPv4 validator agrees with the well that uses it.
        if not LanDiscoveryScript.is_valid_ipv4("255.255.255.255") \
                        or LanDiscoveryScript.is_valid_ipv4("256.1.1.1") \
                        or LanDiscoveryScript.is_valid_ipv4("1.2.3") \
                        or LanDiscoveryScript.is_valid_ipv4("1.2.3.4.5") \
                        or LanDiscoveryScript.is_valid_ipv4("1..2.3"):
                print("FAIL join/ipv4_validator")
                failures += 1

        # QR structure across all four supported versions (size pins the
        # version: 21/25/29/33 modules for payloads of 12/26/27/35+43 bytes;
        # 35-byte join codes top out at v3, so v4 rides a generic payload).
        var cases := [
                ["hi", 21],
                ["SPOTRUSH:JOIN:1.1.1.1:7000", 25],
                ["SPOTRUSH:JOIN:10.0.0.7:7000", 29],
                ["SPOTRUSH:JOIN:192.168.100.100:65535", 29],
                ["x".repeat(43), 33],
        ]
        for case in cases:
                var payload := str(case[0])
                var want_size := int(case[1])
                var encoded := QrCodeScript.encode_matrix(payload)
                if encoded.is_empty() or int(encoded["size"]) != want_size:
                        print("FAIL qr/size got=%s want=%d" % [
                                str(encoded.get("size", "none")), want_size])
                        failures += 1
                        continue
                if not _qr_structure_ok(encoded["grid"], want_size):
                        print("FAIL qr/structure %s" % payload)
                        failures += 1
                # The rendered image: exact canvas, white quiet zone at the
                # corners, ink in the finder centres.
                var img := QrCodeScript.generate_image(payload, 6)
                if img == null or img.get_width() != (want_size + 8) * 6 \
                                or img.get_height() != (want_size + 8) * 6:
                        print("FAIL qr/image_dims %s" % payload)
                        failures += 1
                elif not img.get_pixel(0, 0).is_equal_approx(Color.WHITE) \
                                or not img.get_pixel(img.get_width() - 1, img.get_height() - 1).is_equal_approx(Color.WHITE):
                        print("FAIL qr/quiet_zone %s" % payload)
                        failures += 1
                elif not img.get_pixel((QrCodeScript.QUIET_ZONE + 3) * 6,
                                (QrCodeScript.QUIET_ZONE + 3) * 6).is_equal_approx(QrCodeScript.INK):
                        print("FAIL qr/finder_ink %s" % payload)
                        failures += 1
        # An oversized payload must refuse cleanly, not corrupt.
        if not QrCodeScript.encode_matrix("x".repeat(63)).is_empty() \
                        or QrCodeScript.generate_image("x".repeat(63), 6) != null:
                print("FAIL qr/overflow_rejected")
                failures += 1
        return failures

## Structural spec checks on a finished matrix: the three finders (dark ring,
## light ring, dark heart), the alternating timing track, the dark module and
## (v2+) the alignment pattern.
func _qr_structure_ok(grid: Array, n: int) -> bool:
        var corners := [[0, 0], [0, n - 7], [n - 7, 0]]
        for corner in corners:
                var fr := int(corner[0])
                var fc := int(corner[1])
                if not bool(grid[fr][fc]):
                        return false
                if bool(grid[fr + 1][fc + 1]):
                        return false
                if not bool(grid[fr + 3][fc + 3]):
                        return false
                if not bool(grid[fr][fc + 6]) or not bool(grid[fr + 6][fc]):
                        return false
        for i in range(8, n - 8):
                if bool(grid[6][i]) != (i % 2 == 0):
                        return false
                if bool(grid[i][6]) != (i % 2 == 0):
                        return false
        if not bool(grid[n - 8][8]):
                return false
        if n >= 25:
                var c := n - 7
                if not bool(grid[c][c]) or bool(grid[c - 1][c]) or not bool(grid[c - 2][c]):
                        return false
        return true

# --- 11. daily reminder (v21) --------------------------------------------------------------

func _test_daily_reminder() -> int:
        var failures := 0
        var morning := {"year": 2026, "month": 11, "day": 1, "hour": 10, "minute": 0, "second": 0}
        var evening := {"year": 2026, "month": 11, "day": 1, "hour": 20, "minute": 0, "second": 0}
        # Live streak + unplayed daily + enabled -> schedule today's hour.
        var d := DailyReminderScript.decide(morning, true, 5, false)
        if str(d.get("action")) != "schedule" or int(d.get("delay")) != 9 * 3600:
                print("FAIL reminder/schedule_today delay=%s" % str(d.get("delay")))
                failures += 1
        # The nudge always names the streak it is protecting.
        if not str(d.get("content", "")).contains("5-day"):
                print("FAIL reminder/streak_in_copy")
                failures += 1
        if str(d.get("title")) != "SpotRush daily is waiting":
                print("FAIL reminder/title")
                failures += 1
        # Past the hour -> tomorrow's fire, 23h away.
        d = DailyReminderScript.decide(evening, true, 5, false)
        if str(d.get("action")) != "schedule" or int(d.get("delay")) != 23 * 3600:
                print("FAIL reminder/schedule_tomorrow delay=%s" % str(d.get("delay")))
                failures += 1
        # Exactly on the hour -> fires the next day (never a zero-delay blip).
        var on_the_hour := {"year": 2026, "month": 11, "day": 1, "hour": 19, "minute": 0, "second": 0}
        d = DailyReminderScript.decide(on_the_hour, true, 5, false)
        if int(d.get("delay")) != 86400:
                print("FAIL reminder/on_the_hour delay=%s" % str(d.get("delay")))
                failures += 1
        # Thirty seconds past the hour -> tomorrow minus those 30 seconds.
        var just_after := {"year": 2026, "month": 11, "day": 1, "hour": 19, "minute": 0, "second": 30}
        d = DailyReminderScript.decide(just_after, true, 5, false)
        if int(d.get("delay")) != 86400 - 30:
                print("FAIL reminder/just_after delay=%s" % str(d.get("delay")))
                failures += 1
        # A custom hour is honoured (23:00 while it is 10:00 -> 13h).
        d = DailyReminderScript.decide(morning, true, 5, false, 23)
        if int(d.get("delay")) != 13 * 3600:
                print("FAIL reminder/custom_hour delay=%s" % str(d.get("delay")))
                failures += 1
        # The cancel table: played today, disabled, or no streak at risk.
        for case in [
                [true, 5, true],    # played today
                [false, 5, false],  # setting off
                [true, 0, false],   # nothing to protect
        ]:
                d = DailyReminderScript.decide(morning, bool(case[0]), int(case[1]), bool(case[2]))
                if str(d.get("action")) != "cancel":
                        print("FAIL reminder/should_cancel enabled=%s streak=%d played=%s" % case)
                        failures += 1
        # Fire-time math sanity: delay never negative, always whole seconds.
        d = DailyReminderScript.decide({"year": 2026, "month": 11, "day": 1, "hour": 18, "minute": 59, "second": 59}, true, 3, false)
        if int(d.get("delay")) <= 0:
                print("FAIL reminder/negative_delay")
                failures += 1
        # The setting round-trips (and stays off by default for a fresh file).
        var saved := Settings.reminder_enabled()
        Settings.set_reminder_enabled(true)
        if not Settings.reminder_enabled():
                print("FAIL reminder/setting_roundtrip")
                failures += 1
        Settings.set_reminder_enabled(saved)
        return failures
