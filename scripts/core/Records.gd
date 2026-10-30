extends RefCounted

# Tiny local record keeper (best solo score). Stored in user:// so it survives restarts.

const PATH := "user://spotrush_records.cfg"

static func best() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("solo", "best_score", 0))

## Stores `score` if it beats the saved best. Returns true when it is a new personal best.
static func submit(score: int) -> bool:
		if score <= 0:
				return false
		var previous := best()
		if score <= previous:
				return false
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("solo", "best_score", score)
		cfg.save(PATH)
		return true

## Persisted adaptive-difficulty rating (1..4). Survives restarts so the
## next session opens at the player's flow channel instead of the floor.
static func skill_rating() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 1
		return clampi(int(cfg.get_value("solo", "skill_rating", 1)), 1, 4)

static func set_skill_rating(v: int) -> void:
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("solo", "skill_rating", clampi(v, 1, 4))
		cfg.save(PATH)

# --- Scoring 2.0 (cross-session records) ----------------------------------------------

## Best single-round score ever landed in solo play
## (difficulty base + speed + bolt, all scaled by the combo tier).
static func best_round() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("solo", "best_round_score", 0))

## Stores a round score if it beats the saved best. True = new all-time best.
static func submit_round(points: int) -> bool:
		if points <= 0:
				return false
		var previous := best_round()
		if points <= previous:
				return false
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("solo", "best_round_score", points)
		cfg.save(PATH)
		return true

## Longest correct streak ever held in solo play.
static func best_streak() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("solo", "best_streak", 0))

## Stores a streak if it beats the saved best. True = new all-time best.
static func submit_streak(n: int) -> bool:
		if n <= 0:
				return false
		var previous := best_streak()
		if n <= previous:
				return false
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("solo", "best_streak", n)
		cfg.save(PATH)
		return true

# --- Daily Spot (the once-a-day seeded challenge) -------------------------------------

const DAILY_LAUNCH_DAY: int = 20755  # 2026-10-29: Daily Spot #1

## Local calendar day as an integer (days since 1970-01-01, shifted to local time),
## so "one daily per day" follows the player's own midnight, like the classic
## once-a-day puzzle games.
static func _local_day() -> int:
		var unix := Time.get_unix_time_from_system()
		var offset_sec := 0
		var tz := Time.get_time_zone_from_system()
		if tz.has("bias"):
				offset_sec = int(tz["bias"]) * 60
		return int(floor((unix + float(offset_sec)) / 86400.0))

## Today's issue number, starting at #1 on launch day.
static func daily_number() -> int:
		return _local_day() - DAILY_LAUNCH_DAY + 1

## Deterministic per-day seed: everyone plays the exact same challenge series.
static func daily_seed() -> int:
		return int((_local_day() * 2654435761 + 12345) % 2147483647)

static func daily_completed_today() -> bool:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return false
		return int(cfg.get_value("daily", "last_day", -1)) == _local_day()

static func daily_streak() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("daily", "streak", 0))

static func daily_today_score() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("daily", "last_score", 0))

static func daily_today_correct() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("daily", "last_correct", 0))

static func daily_today_rounds() -> int:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return 0
		return int(cfg.get_value("daily", "last_rounds", 0))

## The copy-paste result card, e.g.
## "SpotRush Daily #12 - 9/10 correct - 16,450 pts - x3 max combo"
static func daily_share_text() -> String:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) != OK:
				return ""
		var text := "SpotRush Daily #%d - %d/%d correct - %s pts - x%d max combo" % [
				int(cfg.get_value("daily", "daily_no", 1)),
				int(cfg.get_value("daily", "last_correct", 0)),
				int(cfg.get_value("daily", "last_rounds", 0)),
				format(int(cfg.get_value("daily", "last_score", 0))),
				int(cfg.get_value("daily", "last_mult", 1))]
		var s_ranks := int(cfg.get_value("daily", "last_s", 0))
		if s_ranks > 0:
				text += " - %d S-rank%s" % [s_ranks, "s" if s_ranks != 1 else ""]
		return text

## Record today's result (once - replays overwrite but never double-count).
## Streak rules: played yesterday -> +1; exactly one missed day and this week's
## shield is unused -> streak survives (one auto-shield per week, Duolingo-style
## loss aversion); anything longer restarts the streak at 1.
static func daily_record(score: int, correct: int, rounds: int, max_mult: int, s_count: int = 0) -> Dictionary:
		var day := _local_day()
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		var last := int(cfg.get_value("daily", "last_day", -1))
		var streak := int(cfg.get_value("daily", "streak", 0))
		if last != day:
				if last == day - 1:
						streak += 1
				elif last == day - 2 and int(cfg.get_value("daily", "freeze_week", -1)) != int(day / 7):
						streak += 1
						cfg.set_value("daily", "freeze_week", int(day / 7))
				else:
						streak = 1
				cfg.set_value("daily", "last_day", day)
				cfg.set_value("daily", "streak", streak)
		cfg.set_value("daily", "daily_no", daily_number())
		cfg.set_value("daily", "last_score", score)
		cfg.set_value("daily", "last_correct", correct)
		cfg.set_value("daily", "last_rounds", rounds)
		cfg.set_value("daily", "last_mult", max_mult)
		cfg.set_value("daily", "last_s", s_count)
		cfg.save(PATH)
		return {"daily_no": daily_number(), "streak": streak, "already": last == day}

# --- Rival Codes (v17 async challenges) ------------------------------------------------

## The player's own challenge code: stable across sessions so a friend can
## still join a run shared days ago. Minted once on first use, anchored at the
## current skill rating, stored forever.
static func my_challenge_code() -> String:
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		var code := str(cfg.get_value("challenge", "my_code", ""))
		if ChallengeCodes.parse(code).is_empty():
				code = ChallengeCodes.create(10, skill_rating())
				cfg.set_value("challenge", "my_code", code)
				cfg.save(PATH)
		return code

## Mint a fresh challenge run as the player's code (new seed, rating re-anchored).
## The old code simply stops being shared - friends who already typed it in
## keep their run, since the code itself is the whole match.
static func reroll_my_challenge_code() -> String:
		var code := ChallengeCodes.create(10, skill_rating())
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("challenge", "my_code", code)
		cfg.save(PATH)
		return code

## Stores the result of a challenge run if (and only if) it was played on the
## player's OWN code, so the invite text can brag ("I scored X - beat it")
## once the sender has actually run their own gauntlet. Returns true when stored.
static func challenge_record_own_result(played_code_display: String, score: int, correct: int, rounds: int) -> bool:
		if ChallengeCodes.normalize(played_code_display) != ChallengeCodes.normalize(my_challenge_code()):
				return false
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("challenge", "own_score", score)
		cfg.set_value("challenge", "own_correct", correct)
		cfg.set_value("challenge", "own_rounds", rounds)
		cfg.save(PATH)
		return true

## The modal's copy-paste invite, e.g.
## "SpotRush challenge - 10 rounds - I scored 12,340 pts - beat it! Code: 4K7-2MP-9QX"
static func challenge_invite_text() -> String:
		var code := my_challenge_code()
		var parsed := ChallengeCodes.parse(code)
		var rounds := int(parsed.get("rounds", 10))
		var text := "SpotRush challenge - %d rounds - " % rounds
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		var own := int(cfg.get_value("challenge", "own_score", 0))
		if own > 0:
				text += "I scored %s pts - beat it! " % format(own)
		else:
				text += "think you can keep up? "
		return text + "Code: %s" % ChallengeCodes.display_form(code)

## The results-screen share card for a played challenge run, e.g.
## "SpotRush challenge - 8/10 correct - 12,340 pts - my run: code 4K7-2MP-9QX. Beat it!"
static func challenge_result_share_text(score: int, correct: int, rounds: int, code_display: String) -> String:
		return "SpotRush challenge - %d/%d correct - %s pts - my run: code %s. Beat it!" % [
						correct, rounds, format(score), ChallengeCodes.display_form(code_display)]

static func format(value: int) -> String:
		var digits := str(absi(value))
		var out := ""
		for i in digits.length():
				if i > 0 and (digits.length() - i) % 3 == 0:
						out += ","
				out += digits.substr(i, 1)
		return ("-" if value < 0 else "") + out
