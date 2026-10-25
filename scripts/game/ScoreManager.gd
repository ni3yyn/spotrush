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
			"response_times": [],
			"round_scores": [],
			"best_round_score": 0,
			"best_round_index": -1
		}

func calculate_round_score(
	is_correct: bool,
	is_timeout: bool,
	response_time: float,
	time_limit: float,
	is_withhold_challenge: bool = false
) -> int:
	if is_timeout:
		if is_withhold_challenge and is_correct:
			# Player correctly refrained from tapping before timeout
			return GameConfig.WITHHOLD_SUCCESS_SCORE
		return 0
	
	if not is_correct:
		return -GameConfig.WRONG_ANSWER_PENALTY
	
	# Correct answer
	var base: int = GameConfig.BASE_CORRECT_SCORE
	var speed_ratio: float = clampf(1.0 - (response_time / maxf(time_limit, 0.001)), 0.0, 1.0)
	var speed_bonus: int = int(round(speed_ratio * float(GameConfig.MAX_SPEED_BONUS)))
	return base + speed_bonus

func record_submission(
	player_id: int,
	round_index: int,
	is_correct: bool,
	is_timeout: bool,
	response_time: float,
	time_limit: float,
	is_withhold_challenge: bool = false
) -> int:
	if not player_stats.has(player_id):
		register_player(player_id)
		
	var score_change: int = calculate_round_score(is_correct, is_timeout, response_time, time_limit, is_withhold_challenge)
	var stats: Dictionary = player_stats[player_id]
	
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
		
	return score_change

func get_player_score(player_id: int) -> int:
	if player_stats.has(player_id):
		return player_stats[player_id]["total_score"]
	return 0

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
