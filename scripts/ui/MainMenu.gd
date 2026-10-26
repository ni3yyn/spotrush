extends Control

const MainMenuCanvasScript = preload("res://scripts/ui/MainMenuCanvas.gd")

@onready var main_canvas: Control = %MainMenuCanvas
@onready var btn_solo: Button = %BtnSolo
@onready var btn_multiplayer: Button = %BtnMultiplayer
@onready var btn_how_to_play: Button = %BtnHowToPlay
@onready var btn_profile: Button = %BtnProfile
@onready var btn_settings: Button = %BtnSettings
@onready var btn_streak: Button = %BtnStreak

# Modal Containers
@onready var modal_how_to_play: Control = %ModalHowToPlay
@onready var modal_friends: Control = %ModalFriends
@onready var modal_settings: Control = %ModalSettings
@onready var modal_profile: Control = %ModalProfile
@onready var modal_streak: Control = %ModalStreak
@onready var token_toast: Label = %TokenToast
@onready var mini_game_overlay: Control = %MiniGameOverlay

# Settings Controls
@onready var btn_rounds_5: Button = %BtnRounds5
@onready var btn_rounds_10: Button = %BtnRounds10
@onready var btn_rounds_15: Button = %BtnRounds15
@onready var check_sfx: CheckButton = %CheckSfx
@onready var check_particles: CheckButton = %CheckParticles

# Mini Game Controls
@onready var lbl_mini_timer: Label = %LblMiniTimer
@onready var lbl_mini_score: Label = %LblMiniScore
@onready var lbl_mini_feedback: Label = %LblMiniFeedback
@onready var mini_board_grid: GridContainer = %MiniBoardGrid

# Modal Actions & Close Buttons
@onready var btn_close_how_to: Button = %BtnCloseHowTo
@onready var btn_close_friends: Button = %BtnCloseFriends
@onready var btn_wifi_lobby: Button = %BtnWifiLobby
@onready var btn_pass_play: Button = %BtnPassPlay
@onready var btn_close_settings: Button = %BtnCloseSettings
@onready var btn_close_profile: Button = %BtnCloseProfile
@onready var btn_close_streak: Button = %BtnCloseStreak
@onready var btn_close_mini: Button = %BtnCloseMini

var selected_rounds: int = 10
var sfx_enabled: bool = true

# Audio players for procedural SFX
var audio_player: AudioStreamPlayer

# Mini game state
var mini_score: int = 0
var mini_time_left: float = 5.0
var is_mini_active: bool = false
var mini_odd_index: int = 0

func _ready() -> void:
	_setup_audio()
	_connect_signals()
	_select_rounds(10)
	_close_all_modals()
	
	if main_canvas != null:
		main_canvas.token_clicked.connect(_on_token_clicked)
		main_canvas.emblem_clicked.connect(_on_emblem_clicked)

func _process(delta: float) -> void:
	if is_mini_active:
		mini_time_left -= delta
		if mini_time_left <= 0.0:
			mini_time_left = 0.0
			is_mini_active = false
			play_sfx("wrong")
			lbl_mini_feedback.text = "TIME UP! FINAL SCORE: %d" % mini_score
			lbl_mini_feedback.modulate = GameConfig.COLOR_CORAL
		lbl_mini_timer.text = "%05.2fs" % mini_time_left

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = &"Master"
	add_child(audio_player)

func _connect_signals() -> void:
	btn_solo.pressed.connect(_on_solo_pressed)
	btn_multiplayer.pressed.connect(_on_multiplayer_pressed)
	btn_how_to_play.pressed.connect(_on_how_to_play_pressed)
	
	btn_profile.pressed.connect(_on_profile_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_streak.pressed.connect(_on_streak_pressed)
	
	btn_close_how_to.pressed.connect(func(): play_sfx("click"); modal_how_to_play.visible = false)
	btn_close_friends.pressed.connect(func(): play_sfx("click"); modal_friends.visible = false)
	btn_wifi_lobby.pressed.connect(func(): play_sfx("play"); SceneRouter.goto_lobby())
	btn_pass_play.pressed.connect(func(): play_sfx("play"); start_quick_mini_game())
	btn_close_settings.pressed.connect(func(): play_sfx("click"); modal_settings.visible = false)
	btn_close_profile.pressed.connect(func(): play_sfx("click"); modal_profile.visible = false)
	btn_close_streak.pressed.connect(func(): play_sfx("click"); modal_streak.visible = false)
	btn_close_mini.pressed.connect(func(): play_sfx("click"); is_mini_active = false; mini_game_overlay.visible = false)
	
	btn_rounds_5.pressed.connect(func(): _select_rounds(5))
	btn_rounds_10.pressed.connect(func(): _select_rounds(10))
	btn_rounds_15.pressed.connect(func(): _select_rounds(15))
	
	check_sfx.toggled.connect(func(t): sfx_enabled = t)
	check_particles.toggled.connect(func(t): if main_canvas: main_canvas.particles_enabled = t)

func _close_all_modals() -> void:
	modal_how_to_play.visible = false
	modal_friends.visible = false
	modal_settings.visible = false
	modal_profile.visible = false
	modal_streak.visible = false
	mini_game_overlay.visible = false
	token_toast.modulate.a = 0.0

var is_navigating: bool = false

# --- NAVIGATION & ACTION HANDLERS ---

func _on_solo_pressed() -> void:
	if is_navigating:
		return
	is_navigating = true
	btn_solo.disabled = true
	play_sfx("play")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_solo.global_position + (btn_solo.size * 0.5))
		
	# Quick snappy tactile bounce transition before starting match
	var tw = create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn_solo, "scale", Vector2(0.95, 0.95), 0.05)
	tw.tween_property(btn_solo, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func():
		GameManager.start_single_player_match(selected_rounds)
		SceneRouter.goto_game()
	)

func _on_multiplayer_pressed() -> void:
	play_sfx("click")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_multiplayer.global_position + (btn_multiplayer.size * 0.5))
	modal_friends.visible = true

func _on_how_to_play_pressed() -> void:
	play_sfx("click")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_how_to_play.global_position + (btn_how_to_play.size * 0.5))
	modal_how_to_play.visible = true

func _on_profile_pressed() -> void:
	play_sfx("click")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_profile.global_position + (btn_profile.size * 0.5))
	modal_profile.visible = true

func _on_settings_pressed() -> void:
	play_sfx("click")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_settings.global_position + (btn_settings.size * 0.5))
	modal_settings.visible = true

func _on_streak_pressed() -> void:
	play_sfx("click")
	if main_canvas:
		main_canvas.trigger_sparkles(btn_streak.global_position + (btn_streak.size * 0.5))
	modal_streak.visible = true

func _on_token_clicked(token_name: String) -> void:
	play_sfx("correct")
	token_toast.text = "⚡ %s Collected!" % token_name
	token_toast.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(token_toast, "modulate:a", 0.0, 0.4)

func _on_emblem_clicked() -> void:
	play_sfx("click")

func _select_rounds(rounds: int) -> void:
	selected_rounds = rounds
	_update_round_button_styles()

func _update_round_button_styles() -> void:
	var active_color = GameConfig.COLOR_COBALT
	var inactive_color = Color("94A3B8")
	
	btn_rounds_5.modulate = active_color if selected_rounds == 5 else inactive_color
	btn_rounds_10.modulate = active_color if selected_rounds == 10 else inactive_color
	btn_rounds_15.modulate = active_color if selected_rounds == 15 else inactive_color

# --- QUICK INTERACTIVE MINI-GAME ---

func start_quick_mini_game() -> void:
	_close_all_modals()
	mini_game_overlay.visible = true
	mini_score = 0
	lbl_mini_score.text = "0"
	lbl_mini_feedback.text = "TAP THE ODD SHAPE!"
	lbl_mini_feedback.modulate = GameConfig.COLOR_COBALT
	is_mini_active = true
	_generate_mini_board()
	mini_time_left = 5.0

func _generate_mini_board() -> void:
	for child in mini_board_grid.get_children():
		child.queue_free()
		
	var palette = [
		GameConfig.COLOR_COBALT,
		GameConfig.COLOR_TANGERINE,
		GameConfig.COLOR_CORAL,
		GameConfig.COLOR_LAVENDER,
		GameConfig.COLOR_MINT
	]
	
	var base_color = palette[randi() % palette.size()]
	var odd_color = palette[randi() % palette.size()]
	while odd_color == base_color:
		odd_color = palette[randi() % palette.size()]
		
	mini_odd_index = randi() % 9
	var shapes = ["circle", "square", "triangle", "diamond"]
	var common_shape = shapes[randi() % shapes.size()]
	
	for i in range(9):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(76, 76)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var style = StyleBoxFlat.new()
		style.bg_color = GameConfig.COLOR_BUTTER
		style.set_corner_radius_all(16)
		style.shadow_color = Color("C3B89B", 0.5)
		style.shadow_size = 4
		style.shadow_offset = Vector2(2, 4)
		btn.add_theme_stylebox_override("normal", style)
		
		# Text icon representing shape
		var is_odd = (i == mini_odd_index)
		var col = odd_color if is_odd else base_color
		var symbol = "●"
		match common_shape:
			"square": symbol = "■"
			"triangle": symbol = "▲"
			"diamond": symbol = "◆"
			_: symbol = "●"
			
		btn.text = symbol
		btn.add_theme_font_size_override("font_size", 34)
		btn.add_theme_color_override("font_color", col)
		
		var idx = i
		btn.pressed.connect(func(): _on_mini_item_pressed(idx, btn))
		mini_board_grid.add_child(btn)

func _on_mini_item_pressed(index: int, btn: Button) -> void:
	if not is_mini_active:
		return
		
	if index == mini_odd_index:
		play_sfx("correct")
		if main_canvas:
			main_canvas.trigger_sparkles(btn.global_position + (btn.size * 0.5))
		mini_score += 100
		lbl_mini_score.text = str(mini_score)
		lbl_mini_feedback.text = "PERFECT SPOT! +100"
		lbl_mini_feedback.modulate = GameConfig.COLOR_MINT
		mini_time_left = 5.0
		_generate_mini_board()
	else:
		play_sfx("wrong")
		mini_time_left = maxf(0.0, mini_time_left - 1.0)
		lbl_mini_feedback.text = "WRONG! -1.0s PENALTY"
		lbl_mini_feedback.modulate = GameConfig.COLOR_CORAL

# --- PROCEDURAL SYNTHESIZED AUDIO SFX ---

func play_sfx(type: String) -> void:
	if not sfx_enabled or audio_player == null:
		return
		
	var stream = _generate_procedural_wav(type)
	if stream != null:
		audio_player.stream = stream
		audio_player.play()

func _generate_procedural_wav(type: String) -> AudioStreamWAV:
	var sample_rate = 22050
	var duration: float = 0.08
	match type:
		"play": duration = 0.24
		"correct": duration = 0.20
		"wrong": duration = 0.18
		_: duration = 0.06
		
	var num_samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var progress = t / duration
		var sample_val: float = 0.0
		
		if type == "click":
			# Sine chirp 360Hz -> 780Hz with exponential decay
			var freq = lerpf(360.0, 780.0, progress)
			var env = (1.0 - progress) * (1.0 - progress)
			sample_val = sin(TAU * freq * t) * env * 0.4
		elif type == "play":
			# Rising triangle chirp 220Hz -> 880Hz
			var freq = lerpf(220.0, 880.0, progress)
			var phase = fposmod(freq * t, 1.0)
			var tri = (phase * 2.0 - 1.0) if phase < 0.5 else ((1.0 - phase) * 2.0 - 1.0)
			var env = 1.0 - progress
			sample_val = tri * env * 0.45
		elif type == "correct":
			# Dual arpeggio chord 523Hz (C5) -> 659Hz (E5)
			var freq = 523.25 if progress < 0.4 else 659.25
			var env = 1.0 - progress
			sample_val = sin(TAU * freq * t) * env * 0.4
		elif type == "wrong":
			# Sawtooth low buzz 160Hz -> 90Hz
			var freq = lerpf(160.0, 90.0, progress)
			var phase = fposmod(freq * t, 1.0)
			var saw = (phase * 2.0) - 1.0
			var env = 1.0 - progress
			sample_val = saw * env * 0.35
		else:
			sample_val = sin(TAU * 440.0 * t) * (1.0 - progress) * 0.3
			
		var val_16 = int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val_16)
		
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav
