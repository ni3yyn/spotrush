extends Control

@onready var lbl_round: Label = %LblRound
@onready var lbl_score_p1: Label = %LblScoreP1
@onready var lbl_score_p2: Label = %LblScoreP2
@onready var timer_bar: ProgressBar = %TimerBar
@onready var challenge_view: Control = %ChallengeView

# Optional HUD enhancement elements
@onready var lbl_timer: Label = (%LblTimer if has_node("%LblTimer") else null)
@onready var lbl_streak: Label = (%LblStreak if has_node("%LblStreak") else null)

# Feedback and countdown overlays
@onready var countdown_overlay: PanelContainer = %CountdownOverlay
@onready var lbl_countdown: Label = %LblCountdown
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var lbl_feedback: Label = %LblFeedback

var is_multiplayer: bool = false
var displayed_score: float = 0.0
var score_tween: Tween = null
var feedback_tween: Tween = null
var countdown_tween: Tween = null

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
	
	if lbl_streak != null:
		lbl_streak.visible = false
	
	feedback_panel.visible = false
	countdown_overlay.visible = false
	
	# If match is already in active round upon scene load, display current round
	if GameManager.match_controller.current_challenge != null:
		_on_round_started(
			GameManager.match_controller.current_round_index + 1,
			GameManager.match_controller.current_challenge,
			GameManager.match_controller.round_duration
		)

func _input(event: InputEvent) -> void:
	# Tap anywhere during feedback skips directly to the next challenge
	if feedback_panel != null and feedback_panel.visible:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			GameManager.skip_feedback()

func _on_countdown_started(round_num: int, total_rounds: int) -> void:
	_kill_tweens()
	
	lbl_round.text = "ROUND %d / %d" % [round_num, total_rounds]
	countdown_overlay.visible = true
	feedback_panel.visible = false
	challenge_view.lock_input()
	
	if lbl_timer != null:
		lbl_timer.text = "--"
		lbl_timer.modulate = GameConfig.COLOR_MINT
		
	# Snappy countdown pulse synchronized with GameConfig.COUNTDOWN_DURATION
	lbl_countdown.text = "GET READY!"
	countdown_overlay.pivot_offset = countdown_overlay.size * 0.5
	countdown_overlay.scale = Vector2(0.92, 0.92)
	
	countdown_tween = create_tween()
	countdown_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	countdown_tween.tween_property(countdown_overlay, "scale", Vector2.ONE, 0.15)
	countdown_tween.tween_interval(maxf(0.2, (GameConfig.COUNTDOWN_DURATION * 0.5) - 0.15))
	countdown_tween.tween_callback(func():
		lbl_countdown.text = "SPOT!"
		lbl_countdown.modulate = GameConfig.COLOR_ACCENT_YELLOW
	)

func _on_round_started(round_num: int, challenge: ChallengeDefinition, duration: float) -> void:
	_kill_tweens()
	
	countdown_overlay.visible = false
	feedback_panel.visible = false
	lbl_round.text = "ROUND %d / %d" % [round_num, GameManager.match_controller.total_rounds]
	
	timer_bar.max_value = duration
	timer_bar.value = duration
	timer_bar.modulate = GameConfig.COLOR_MINT
	
	if lbl_timer != null:
		lbl_timer.text = "%.1fs" % duration
		lbl_timer.modulate = GameConfig.COLOR_MINT
		
	challenge_view.load_challenge(challenge)

func _on_time_tick(remaining: float, total: float) -> void:
	timer_bar.value = remaining
	if lbl_timer != null:
		lbl_timer.text = "%.1fs" % remaining
		
	var ratio = remaining / maxf(total, 0.001)
	if ratio > 0.5:
		timer_bar.modulate = GameConfig.COLOR_MINT
		if lbl_timer != null: lbl_timer.modulate = GameConfig.COLOR_MINT
	elif ratio > 0.25:
		timer_bar.modulate = GameConfig.COLOR_ACCENT_YELLOW
		if lbl_timer != null: lbl_timer.modulate = GameConfig.COLOR_ACCENT_YELLOW
	else:
		timer_bar.modulate = GameConfig.COLOR_ACCENT_RED
		if lbl_timer != null: lbl_timer.modulate = GameConfig.COLOR_ACCENT_RED

func _on_player_choice(choice: Variant) -> void:
	GameManager.submit_answer(choice)

func _on_answer_feedback(_player_id: int, is_correct: bool, score_delta: int, details: String) -> void:
	feedback_panel.visible = true
	
	var local_id = NetworkSession.get_local_id() if is_multiplayer else 1
	var stats = GameManager.match_controller.score_manager.get_player_stats(local_id)
	var streak = stats.get("current_streak", 0)
	
	# Update HUD streak badge
	if lbl_streak != null:
		if streak >= 2:
			lbl_streak.visible = true
			lbl_streak.text = "🔥 x%d" % streak
			var tw_streak = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw_streak.tween_property(lbl_streak, "scale", Vector2(1.2, 1.2), 0.08)
			tw_streak.tween_property(lbl_streak, "scale", Vector2.ONE, 0.12)
		else:
			lbl_streak.visible = false
	
	var text = ""
	if is_correct:
		feedback_panel.modulate = GameConfig.COLOR_MINT
		if "Withheld" in details:
			text = "PERFECT RESTRAINT! +%d PTS\n%s" % [score_delta, details]
		elif streak >= 3:
			text = "🔥 HOT STREAK x%d! +%d PTS\n%s" % [streak, score_delta, details]
		elif streak == 2:
			text = "STREAK x2! +%d PTS\n%s" % [score_delta, details]
		else:
			text = "CORRECT! +%d PTS\n%s" % [score_delta, details]
	else:
		feedback_panel.modulate = GameConfig.COLOR_ACCENT_RED
		if "Don't Tap" in details:
			text = "IMPULSE FAULT! %d PTS\n%s" % [score_delta, details]
		else:
			text = "MISSED! %d PTS\n%s" % [score_delta, details]
		
	lbl_feedback.text = text
	
	# Tactile bounce entrance animation
	feedback_panel.pivot_offset = feedback_panel.size * 0.5
	feedback_panel.scale = Vector2(0.9, 0.9)
	feedback_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(feedback_panel, "scale", Vector2.ONE, 0.18)
	
	# Authoritative score update with smooth count-up animation
	var my_score = GameManager.match_controller.score_manager.get_player_score(local_id)
	_animate_score_to(my_score)
	
	if is_multiplayer:
		var opp_id = -1
		for pid in GameManager.match_controller.player_ids:
			if pid != local_id:
				opp_id = pid
				break
		var opp_score = GameManager.match_controller.score_manager.get_player_score(opp_id) if opp_id != -1 else 0
		lbl_score_p2.text = "OPPONENT: %d" % opp_score

func _animate_score_to(target_score: int) -> void:
	if score_tween != null and score_tween.is_valid():
		score_tween.kill()
		
	var start_val = displayed_score
	score_tween = create_tween()
	score_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	score_tween.tween_method(
		func(val: float):
			displayed_score = val
			lbl_score_p1.text = "YOU: %d" % int(round(val)) if is_multiplayer else "SCORE: %d" % int(round(val)),
		start_val,
		float(target_score),
		0.25
	)
	score_tween.tween_callback(func():
		displayed_score = float(target_score)
		lbl_score_p1.text = "YOU: %d" % target_score if is_multiplayer else "SCORE: %d" % target_score
	)

func _kill_tweens() -> void:
	if countdown_tween != null and countdown_tween.is_valid():
		countdown_tween.kill()
	if feedback_tween != null and feedback_tween.is_valid():
		feedback_tween.kill()

func _on_round_ended(_round_num: int, _scores: Dictionary) -> void:
	challenge_view.lock_input()

func _on_match_ended(_results: Dictionary) -> void:
	_kill_tweens()
	if score_tween != null and score_tween.is_valid():
		score_tween.kill()
	SceneRouter.goto_results()
