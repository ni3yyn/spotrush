extends Control

@onready var lbl_round: Label = %LblRound
@onready var lbl_score_p1: Label = %LblScoreP1
@onready var lbl_score_p2: Label = %LblScoreP2
@onready var timer_bar: ProgressBar = %TimerBar
@onready var challenge_view: Control = %ChallengeView

# Feedback and countdown overlays
@onready var countdown_overlay: PanelContainer = %CountdownOverlay
@onready var lbl_countdown: Label = %LblCountdown
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var lbl_feedback: Label = %LblFeedback

var is_multiplayer: bool = false

func _ready() -> void:
	GameManager.ui_countdown_started.connect(_on_countdown_started)
	GameManager.ui_round_started.connect(_on_round_started)
	GameManager.ui_time_tick.connect(_on_time_tick)
	GameManager.ui_answer_feedback.connect(_on_answer_feedback)
	GameManager.ui_round_ended.connect(_on_round_ended)
	GameManager.ui_match_ended.connect(_on_match_ended)
	
	challenge_view.option_selected.connect(_on_player_choice)
	
	is_multiplayer = (GameManager.current_game_mode != GameConfig.GameMode.SINGLE_PLAYER)
	lbl_score_p2.visible = is_multiplayer
	
	feedback_panel.visible = false
	countdown_overlay.visible = false
	
	# If match is already in active round upon scene load, display current round
	if GameManager.match_controller.current_challenge != null:
		_on_round_started(
			GameManager.match_controller.current_round_index + 1,
			GameManager.match_controller.current_challenge,
			GameManager.match_controller.round_duration
		)

func _on_countdown_started(round_num: int, total_rounds: int) -> void:
	lbl_round.text = "ROUND %d / %d" % [round_num, total_rounds]
	countdown_overlay.visible = true
	feedback_panel.visible = false
	challenge_view.lock_input()
	
	# Simple countdown pulse
	lbl_countdown.text = "GET READY!"
	var tw = create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func(): lbl_countdown.text = "SPOT!")

func _on_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
	countdown_overlay.visible = false
	feedback_panel.visible = false
	lbl_round.text = "ROUND %d / %d" % [round_num, GameManager.match_controller.total_rounds]
	
	timer_bar.max_value = duration
	timer_bar.value = duration
	timer_bar.modulate = GameConfig.COLOR_MINT
	
	challenge_view.load_challenge(challenge)

func _on_time_tick(remaining: float, total: float) -> void:
	timer_bar.value = remaining
	var ratio = remaining / maxf(total, 0.001)
	if ratio > 0.5:
		timer_bar.modulate = GameConfig.COLOR_MINT
	elif ratio > 0.25:
		timer_bar.modulate = GameConfig.COLOR_ACCENT_YELLOW
	else:
		timer_bar.modulate = GameConfig.COLOR_ACCENT_RED

func _on_player_choice(choice: Variant) -> void:
	GameManager.submit_answer(choice)

func _on_answer_feedback(_player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
	feedback_panel.visible = true
	
	var text = ""
	if is_correct:
		feedback_panel.modulate = GameConfig.COLOR_MINT
		text = "CORRECT! +%d PTS\n%s" % [score_delta, details]
	else:
		feedback_panel.modulate = GameConfig.COLOR_ACCENT_RED
		text = "MISSED! %d PTS\n%s" % [score_delta, details]
		
	lbl_feedback.text = text
	
	# Update score display
	var local_id = NetworkSession.get_local_id() if is_multiplayer else 1
	var my_score = GameManager.match_controller.score_manager.get_player_score(local_id)
	lbl_score_p1.text = "YOU: %d" % my_score if is_multiplayer else "SCORE: %d" % my_score
	
	if is_multiplayer:
		var opp_id = -1
		for pid in GameManager.match_controller.player_ids:
			if pid != local_id:
				opp_id = pid
				break
		var opp_score = GameManager.match_controller.score_manager.get_player_score(opp_id) if opp_id != -1 else 0
		lbl_score_p2.text = "OPPONENT: %d" % opp_score

func _on_round_ended(_round_num: int, _scores: Dictionary) -> void:
	challenge_view.lock_input()

func _on_match_ended(_results: Dictionary) -> void:
	SceneRouter.goto_results()
