class_name ScoreManager
extends RefCounted

# Player ID -> stats dictionary
var player_stats: Dictionary = {}

func reset() -> void:
        player_stats.clear()

func register_player(player_id: int, player_name: String = "") -> void:
        if not player_stats.has(player_id):
                player_stats[player_id] = {
                        "id": player_id,
                        "name": player_name if not player_name.is_empty() else ("Player %d" % player_id),
                        "total_score": 0,
                        "correct_count": 0,
                        "incorrect_count": 0,
                        "missed_count": 0,
                        "current_streak": 0,
                        "max_streak": 0,
                        "response_times": [],
                        "round_scores": [],
                        "best_round_score": 0,
                        "best_round_index": -1,
                        "max_multiplier": 1,
                        "last_break_streak": 0,
                        "round_grades": [],
                        "grade_counts": {"S": 0, "A": 0, "B": 0, "C": 0},
                        "last_breakdown": {}
                }

## Combo multiplier for a consecutive-correct streak: 3 in a row -> x2,
## 6 -> x3, 10 -> x4. One miss drops straight back to x1.
static func combo_multiplier(streak: int) -> int:
        if streak >= GameConfig.COMBO_TIER_4:
                return 4
        if streak >= GameConfig.COMBO_TIER_3:
                return 3
        if streak >= GameConfig.COMBO_TIER_2:
                return 2
        return 1

## Correct answers still needed to reach the next multiplier tier
## (0 when already at x4).
static func tier_gap(streak: int) -> int:
        if streak >= GameConfig.COMBO_TIER_4:
                return 0
        if streak >= GameConfig.COMBO_TIER_3:
                return GameConfig.COMBO_TIER_4 - streak
        if streak >= GameConfig.COMBO_TIER_2:
                return GameConfig.COMBO_TIER_3 - streak
        return GameConfig.COMBO_TIER_2 - streak

## Letter grade for how much of the clock a correct answer used.
## S = lightning reflexes, A = quick, B = steady, C = just made it.
static func grade_for_time(used_ratio: float) -> String:
        if used_ratio <= GameConfig.GRADE_S_TIME:
                return "S"
        if used_ratio <= GameConfig.GRADE_A_TIME:
                return "A"
        if used_ratio <= GameConfig.GRADE_B_TIME:
                return "B"
        return "C"

## Score one round and return the FULL breakdown so the HUD, the feedback card
## and the multiplayer packet all show the exact math the score used:
##   total = (difficulty base + eased speed bonus + lightning bonus) x combo tier
func score_round(
        is_correct: bool,
        is_timeout: bool,
        response_time: float,
        time_limit: float,
        is_withhold_challenge: bool = false,
        streak: int = 0,
        difficulty: int = 2,
        broke_streak: int = 0
) -> Dictionary:
        if is_timeout:
                if is_withhold_challenge and is_correct:
                        # Player correctly refrained from tapping before timeout
                        return {
                                "kind": "withhold", "base": 0, "speed_bonus": 0,
                                "lightning_bonus": 0, "subtotal": GameConfig.WITHHOLD_SUCCESS_SCORE,
                                "mult": 1, "total": GameConfig.WITHHOLD_SUCCESS_SCORE,
                                "grade": "", "speed_ratio": 0.0, "broke": 0
                        }
                return {"kind": "timeout", "base": 0, "speed_bonus": 0, "lightning_bonus": 0,
                        "subtotal": 0, "mult": 1, "total": 0, "grade": "", "speed_ratio": 0.0,
                        "broke": broke_streak}
        
        if not is_correct:
                return {"kind": "wrong", "base": 0, "speed_bonus": 0, "lightning_bonus": 0,
                        "subtotal": 0, "mult": 1, "total": -GameConfig.WRONG_ANSWER_PENALTY,
                        "grade": "", "speed_ratio": 0.0, "broke": broke_streak}
        
        # Correct answer: difficulty-weighted base + eased speed curve (plus a
        # lightning bolt for near-instant answers), all scaled by the combo tier.
        var base: int = GameConfig.base_score_for(difficulty)
        var speed_ratio: float = clampf(1.0 - (response_time / maxf(time_limit, 0.001)), 0.0, 1.0)
        var speed_bonus: int = int(round(pow(speed_ratio, GameConfig.SPEED_CURVE_EXP) * float(GameConfig.MAX_SPEED_BONUS)))
        var lightning_bonus: int = GameConfig.LIGHTNING_BONUS if speed_ratio >= GameConfig.LIGHTNING_THRESHOLD else 0
        var mult: int = combo_multiplier(streak)
        var subtotal: int = base + speed_bonus + lightning_bonus
        return {
                "kind": "correct", "base": base, "speed_bonus": speed_bonus,
                "lightning_bonus": lightning_bonus, "subtotal": subtotal, "mult": mult,
                "total": subtotal * mult, "grade": grade_for_time(1.0 - speed_ratio),
                "speed_ratio": speed_ratio, "broke": 0
        }

## Backwards-compatible int wrapper (call sites that only need the points).
func calculate_round_score(
        is_correct: bool,
        is_timeout: bool,
        response_time: float,
        time_limit: float,
        is_withhold_challenge: bool = false,
        streak: int = 0,
        difficulty: int = 2
) -> int:
        return int(score_round(is_correct, is_timeout, response_time, time_limit,
                is_withhold_challenge, streak, difficulty)["total"])

func record_submission(
        player_id: int,
        round_index: int,
        is_correct: bool,
        is_timeout: bool,
        response_time: float,
        time_limit: float,
        is_withhold_challenge: bool = false,
        difficulty: int = 2
) -> int:
        if not player_stats.has(player_id):
                register_player(player_id)
                
        var stats: Dictionary = player_stats[player_id]
        var streak_before: int = stats.get("current_streak", 0)
        if is_correct:
                stats["current_streak"] = streak_before + 1
                if stats["current_streak"] > stats.get("max_streak", 0):
                        stats["max_streak"] = stats["current_streak"]
        else:
                stats["current_streak"] = 0
                stats["last_break_streak"] = streak_before
                
        var current_streak: int = stats.get("current_streak", 0)
        var breakdown: Dictionary = score_round(
                is_correct,
                is_timeout,
                response_time,
                time_limit,
                is_withhold_challenge,
                current_streak,
                difficulty,
                streak_before
        )
        var score_change: int = int(breakdown["total"])
        stats["last_breakdown"] = breakdown
        var round_grade: String = str(breakdown["grade"])
        var grades: Array = stats.get("round_grades", [])
        grades.append(round_grade)
        stats["round_grades"] = grades
        var counts: Dictionary = stats.get("grade_counts", {})
        if round_grade != "" and counts.has(round_grade):
                counts[round_grade] = int(counts[round_grade]) + 1
                stats["grade_counts"] = counts
        
        stats["total_score"] = maxi(0, stats["total_score"] + score_change)
        stats["round_scores"].append(score_change)
        
        if is_timeout:
                if is_withhold_challenge and is_correct:
                        stats["correct_count"] += 1
                else:
                        stats["missed_count"] += 1
        elif is_correct:
                stats["correct_count"] += 1
                stats["response_times"].append(response_time)
        else:
                stats["incorrect_count"] += 1
                stats["response_times"].append(response_time)
                
        if score_change > stats["best_round_score"]:
                stats["best_round_score"] = score_change
                stats["best_round_index"] = round_index

        var mult: int = combo_multiplier(stats.get("current_streak", 0))
        if mult > stats.get("max_multiplier", 1):
                stats["max_multiplier"] = mult
                
        return score_change

func get_player_score(player_id: int) -> int:
        if player_stats.has(player_id):
                return player_stats[player_id]["total_score"]
        # Check string key variant in case of network serialization
        if player_stats.has(str(player_id)):
                return player_stats[str(player_id)]["total_score"]
        return 0

func set_player_score(player_id: int, total_score: int) -> void:
        if not player_stats.has(player_id):
                register_player(player_id)
        player_stats[player_id]["total_score"] = maxi(0, total_score)

func apply_authoritative_scores(scores: Dictionary) -> void:
        for raw_key in scores.keys():
                var pid = int(raw_key)
                var sc = int(scores[raw_key])
                set_player_score(pid, sc)

## Live combo streak for the HUD (0 when unknown).
func get_streak(player_id: int) -> int:
        if player_stats.has(player_id):
                return int(player_stats[player_id].get("current_streak", 0))
        if player_stats.has(str(player_id)):
                return int(player_stats[str(player_id)].get("current_streak", 0))
        return 0

## The full score_round() breakdown of a player's most recent answer, for the
## feedback card and the network packet. Empty when nothing was scored yet.
func get_last_breakdown(player_id: int) -> Dictionary:
        if player_stats.has(player_id):
                return player_stats[player_id].get("last_breakdown", {})
        if player_stats.has(str(player_id)):
                return player_stats[str(player_id)].get("last_breakdown", {})
        return {}

## Client-side mirror of a round the host scored authoritatively: refresh the
## streak and the breakdown the live HUD reads, without ever recomputing points
## (totals still arrive via MSG_ROUND_END / MSG_MATCH_END).
func apply_remote_round(player_id: int, breakdown: Dictionary, streak: int) -> void:
        if not player_stats.has(player_id):
                register_player(player_id)
        var stats: Dictionary = player_stats[player_id]
        stats["current_streak"] = streak
        if streak > stats.get("max_streak", 0):
                stats["max_streak"] = streak
        var mult: int = combo_multiplier(streak)
        if mult > stats.get("max_multiplier", 1):
                stats["max_multiplier"] = mult
        if not breakdown.is_empty():
                stats["last_breakdown"] = breakdown
                var round_grade: String = str(breakdown.get("grade", ""))
                var counts: Dictionary = stats.get("grade_counts", {})
                if round_grade != "" and counts.has(round_grade):
                        counts[round_grade] = int(counts[round_grade]) + 1
                        stats["grade_counts"] = counts
                var total: int = int(breakdown.get("total", 0))
                if total > stats.get("best_round_score", 0):
                        stats["best_round_score"] = total

func get_player_stats(player_id: int) -> Dictionary:
        if not player_stats.has(player_id):
                return {}
        
        var raw = player_stats[player_id]
        var total_attempts = raw["correct_count"] + raw["incorrect_count"] + raw["missed_count"]
        var accuracy = 0.0
        if total_attempts > 0:
                accuracy = (float(raw["correct_count"]) / float(total_attempts)) * 100.0
                
        var avg_time = 0.0
        var times: Array = raw["response_times"]
        if not times.is_empty():
                var sum_time = 0.0
                for t in times:
                        sum_time += float(t)
                avg_time = sum_time / float(times.size())
                
        var res = raw.duplicate(true)
        res["accuracy"] = accuracy
        res["avg_response_time"] = avg_time
        res["current_streak"] = raw.get("current_streak", 0)
        res["max_streak"] = raw.get("max_streak", 0)
        return res

func determine_match_result() -> Dictionary:
        if player_stats.is_empty():
                return {"is_tie": true, "winner_id": -1, "scores": {}}
                
        var ids = player_stats.keys()
        if ids.size() == 1:
                var p_id = ids[0]
                var single_score = player_stats[p_id]["total_score"]
                return {
                        "is_tie": false,
                        "winner_id": p_id,
                        "winner_name": player_stats[p_id]["name"],
                        "highest_score": single_score,
                        "scores": { p_id: single_score }
                }
                
        # 2 players or more
        var highest_score: int = -999999
        var winner_id: int = -1
        var is_tie: bool = false
        var scores_dict: Dictionary = {}
        
        for pid in ids:
                var sc: int = player_stats[pid]["total_score"]
                scores_dict[pid] = sc
                if sc > highest_score:
                        highest_score = sc
                        winner_id = pid
                        is_tie = false
                elif sc == highest_score:
                        is_tie = true
                        
        return {
                "is_tie": is_tie,
                "winner_id": -1 if is_tie else winner_id,
                "winner_name": "TIE" if is_tie else player_stats[winner_id]["name"],
                "highest_score": highest_score,
                "scores": scores_dict
        }
