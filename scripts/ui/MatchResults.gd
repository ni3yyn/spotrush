extends Control

@onready var lbl_outcome: Label = %LblOutcome
@onready var lbl_final_scores: Label = %LblFinalScores
@onready var lbl_accuracy: Label = %LblAccuracy
@onready var lbl_avg_time: Label = %LblAvgTime
@onready var lbl_correct_stats: Label = %LblCorrectStats
@onready var lbl_best_round: Label = %LblBestRound
@onready var btn_rematch: Button = %BtnRematch
@onready var btn_menu: Button = %BtnMenu

func _ready() -> void:
	btn_rematch.pressed.connect(_on_rematch_pressed)
	btn_menu.pressed.connect(_on_menu_pressed)
	
	_populate_results()

func _populate_results() -> void:
	var results = GameManager.last_match_results
	var is_multiplayer = (GameManager.current_game_mode != GameConfig.GameMode.SINGLE_PLAYER)
	
	if results.is_empty():
		lbl_outcome.text = "MATCH COMPLETE"
		return
		
	var local_id = NetworkSession.get_local_id() if is_multiplayer else 1
	var winner_id = results.get("winner_id", -1)
	
	# Outcome header
	if not is_multiplayer:
		lbl_outcome.text = "MATCH COMPLETED!"
		lbl_outcome.modulate = GameConfig.COLOR_MINT
	else:
		if results.get("is_tie", false):
			lbl_outcome.text = "IT'S A TIE!"
			lbl_outcome.modulate = GameConfig.COLOR_ACCENT_YELLOW
		elif winner_id == local_id:
			lbl_outcome.text = "VICTORY!"
			lbl_outcome.modulate = GameConfig.COLOR_MINT
		else:
			lbl_outcome.text = "DEFEAT"
			lbl_outcome.modulate = GameConfig.COLOR_ACCENT_RED
			
	# Scores
	var player_stats = results.get("player_stats", {})
	var my_stats = player_stats.get(local_id, player_stats.get(str(local_id), {}))
	var my_score = my_stats.get("total_score", 0)
	
	if not is_multiplayer:
		lbl_final_scores.text = "FINAL SCORE: %d PTS" % my_score
	else:
		var opp_id = -1
		for pid in GameManager.match_controller.player_ids:
			if pid != local_id:
				opp_id = pid
				break
		var opp_stats = player_stats.get(opp_id, player_stats.get(str(opp_id), {}))
		var opp_score = opp_stats.get("total_score", 0)
		lbl_final_scores.text = "YOU: %d PTS   |   OPPONENT: %d PTS" % [my_score, opp_score]
		
	# Detailed stats from local player
	var accuracy = my_stats.get("accuracy", 0.0)
	var avg_time = my_stats.get("avg_response_time", 0.0)
	var correct = my_stats.get("correct_count", 0)
	var incorrect = my_stats.get("incorrect_count", 0)
	var missed = my_stats.get("missed_count", 0)
	var best_score = my_stats.get("best_round_score", 0)
	var best_idx = my_stats.get("best_round_index", -1)
	
	lbl_accuracy.text = "Accuracy: %.1f%%" % accuracy
	lbl_avg_time.text = "Avg Response Time: %.2fs" % avg_time
	lbl_correct_stats.text = "Correct: %d  |  Wrong: %d  |  Timeouts: %d" % [correct, incorrect, missed]
	
	if best_idx >= 0:
		lbl_best_round.text = "Best Round: Round %d (+%d pts)" % [best_idx + 1, best_score]
	else:
		lbl_best_round.text = "Best Round: N/A"

func _on_rematch_pressed() -> void:
	if GameManager.current_game_mode == GameConfig.GameMode.SINGLE_PLAYER:
		GameManager.start_single_player_match(GameManager.match_controller.total_rounds)
		SceneRouter.goto_game()
	elif GameManager.current_game_mode == GameConfig.GameMode.MULTIPLAYER_HOST:
		GameManager.start_multiplayer_host_match(GameManager.match_controller.total_rounds)
		SceneRouter.goto_game()
	elif GameManager.current_game_mode == GameConfig.GameMode.MULTIPLAYER_CLIENT:
		# Wait for host to restart or return to lobby
		lbl_outcome.text = "WAITING FOR HOST..."

func _on_menu_pressed() -> void:
	NetworkSession.disconnect_session()
	SceneRouter.goto_main_menu()
