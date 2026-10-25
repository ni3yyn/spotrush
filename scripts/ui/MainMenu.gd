extends Control

@onready var btn_solo: Button = %BtnSolo
@onready var btn_multiplayer: Button = %BtnMultiplayer
@onready var btn_how_to_play: Button = %BtnHowToPlay
@onready var btn_rounds_5: Button = %BtnRounds5
@onready var btn_rounds_10: Button = %BtnRounds10
@onready var btn_rounds_15: Button = %BtnRounds15
@onready var how_to_play_popup: PanelContainer = %HowToPlayPopup
@onready var btn_close_guide: Button = %BtnCloseGuide

var selected_rounds: int = 10

func _ready() -> void:
	btn_solo.pressed.connect(_on_solo_pressed)
	btn_multiplayer.pressed.connect(_on_multiplayer_pressed)
	btn_how_to_play.pressed.connect(_on_how_to_play_pressed)
	btn_close_guide.pressed.connect(_on_close_guide_pressed)
	
	btn_rounds_5.pressed.connect(func(): _select_rounds(5))
	btn_rounds_10.pressed.connect(func(): _select_rounds(10))
	btn_rounds_15.pressed.connect(func(): _select_rounds(15))
	_select_rounds(10)
	
	how_to_play_popup.visible = false

func _select_rounds(rounds: int) -> void:
	selected_rounds = rounds
	_update_round_button_styles()

func _update_round_button_styles() -> void:
	var active_color = GameConfig.COLOR_MINT
	var inactive_color = GameConfig.COLOR_SURFACE_LIGHT
	
	btn_rounds_5.modulate = active_color if selected_rounds == 5 else inactive_color
	btn_rounds_10.modulate = active_color if selected_rounds == 10 else inactive_color
	btn_rounds_15.modulate = active_color if selected_rounds == 15 else inactive_color

func _on_solo_pressed() -> void:
	GameManager.start_single_player_match(selected_rounds)
	SceneRouter.goto_game()

func _on_multiplayer_pressed() -> void:
	SceneRouter.goto_lobby()

func _on_how_to_play_pressed() -> void:
	how_to_play_popup.visible = true

func _on_close_guide_pressed() -> void:
	how_to_play_popup.visible = false
