extends Control

const MainMenuCanvasScript = preload("res://scripts/ui/MainMenuCanvas.gd")
const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Records = preload("res://scripts/core/Records.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const Settings = preload("res://scripts/core/Settings.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const SpotRushGlyph = preload("res://scripts/ui/SpotRushGlyph.gd")
const MainMenuIcon = preload("res://scripts/ui/MainMenuIcon.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")

@onready var main_canvas: Control = %MainMenuCanvas
@onready var btn_solo: Button = %BtnSolo
@onready var btn_multiplayer: Button = %BtnMultiplayer
@onready var btn_how_to_play: Button = %BtnHowToPlay
@onready var btn_profile: Button = %BtnProfile
@onready var btn_settings: Button = %BtnSettings
@onready var btn_streak: Button = %BtnStreak
@onready var action_row: Control = $SafeArea/VBoxMain/ActionRow
@onready var title_text: RichTextLabel = %TitleText
@onready var title_extrusion: RichTextLabel = %TitleExtrusion
@onready var title_highlight: RichTextLabel = %TitleHighlight
@onready var online_label: Label = $SafeArea/VBoxMain/HeaderBar/BtnProfile/OnlineContent/OnlineLabel
@onready var tagline_text: Label = %SubtitleText
@onready var play_text: Label = %PlayText
@onready var play_mode_badge: Label = %PlayModeBadge
@onready var friends_text: Label = %FriendsText
@onready var how_text: Label = %HowText
@onready var best_score_label: Label = %BestScoreLabel
@onready var best_score_value: Label = %BestScoreValue
@onready var play_content: HBoxContainer = %PlayContent
@onready var friends_content: HBoxContainer = %FriendsContent
@onready var how_content: HBoxContainer = %HowContent
@onready var best_modal_value: Label = %BestModalValue
@onready var best_modal_hint: Label = %BestModalHint
@onready var modal_scrim: ColorRect = %ModalScrim

# Modal Containers
@onready var modal_how_to_play: Control = %ModalHowToPlay
@onready var modal_friends: Control = %ModalFriends
@onready var modal_profile: Control = %ModalProfile
@onready var modal_streak: Control = %ModalStreak
@onready var lbl_daily_number: Label = (%LblDailyNumber if has_node("%LblDailyNumber") else null)
@onready var lbl_daily_streak: Label = (%LblDailyStreak if has_node("%LblDailyStreak") else null)
@onready var lbl_daily_countdown: Label = (%LblDailyCountdown if has_node("%LblDailyCountdown") else null)
@onready var btn_play_daily: Button = (%BtnPlayDaily if has_node("%BtnPlayDaily") else null)
@onready var lbl_daily_done: Label = (%LblDailyDone if has_node("%LblDailyDone") else null)
@onready var btn_share_daily: Button = (%BtnShareDaily if has_node("%BtnShareDaily") else null)

# Rival Codes (v17) - the async challenge sheet.
@onready var modal_challenge: Control = %ModalChallenge
@onready var lbl_my_code: Label = (%LblMyCode if has_node("%LblMyCode") else null)
@onready var btn_copy_code: Button = (%BtnCopyCode if has_node("%BtnCopyCode") else null)
@onready var btn_new_code: Button = (%BtnNewCode if has_node("%BtnNewCode") else null)
@onready var btn_play_mine: Button = (%BtnPlayMine if has_node("%BtnPlayMine") else null)
@onready var edt_code: LineEdit = (%EdtCode if has_node("%EdtCode") else null)
@onready var btn_play_friend: Button = (%BtnPlayFriend if has_node("%BtnPlayFriend") else null)
@onready var lbl_challenge_status: Label = (%LblChallengeStatus if has_node("%LblChallengeStatus") else null)
@onready var btn_close_challenge: Button = (%BtnCloseChallenge if has_node("%BtnCloseChallenge") else null)
@onready var btn_challenge_code: Button = (%BtnChallengeCode if has_node("%BtnChallengeCode") else null)
@onready var token_toast: Label = %TokenToast
@onready var mini_game_overlay: Control = %MiniGameOverlay

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
@onready var btn_close_profile: Button = %BtnCloseProfile
@onready var btn_close_streak: Button = %BtnCloseStreak
@onready var btn_close_mini: Button = %BtnCloseMini

var selected_rounds: int = 10

# Mini game state
var mini_score: int = 0
var mini_time_left: float = 5.0
var is_mini_active: bool = false
var mini_odd_index: int = 0

func _ready() -> void:
		SpotRushSkin.apply_screen(self, "menu")
		BackNav.register(self)
		NeuSafe.fit(get_node_or_null("SafeArea")) # real OS insets (v20)
		_style_toast()
		_style_hero_actions()
		_style_how_to_modal()
		_style_friends_modal()
		_style_personal_best_modal()
		_style_daily_modal()
		_style_challenge_modal()
		_refresh_personal_best()
		_apply_responsive_layout()
		call_deferred("_center_button_pivots")
		get_viewport().size_changed.connect(_apply_responsive_layout)
		_connect_signals()
		SceneRouter.transition_started.connect(_close_all_modals)
		selected_rounds = Settings.match_rounds()
		play_mode_badge.text = "%d ROUND SPRINT" % selected_rounds
		_close_all_modals()
		
		if main_canvas != null:
				main_canvas.token_clicked.connect(_on_token_clicked)
				main_canvas.emblem_clicked.connect(_on_emblem_clicked)
				main_canvas.particles_enabled = Settings.particles()
		Feel.warm_up() # builds the sound bank one sound per frame; no startup hitch
		Music.play_menu() # ambient loop fades in as soon as the boot thread forges it
		_add_version_chip()
		_play_entrance()
		_prime_game_music_after_entrance()


func _prime_game_music_after_entrance() -> void:
		# Let the first-screen transition, layout and entrance animation finish before
		# spending background CPU on the second (gameplay) music loop.
		await get_tree().create_timer(1.8).timeout
		if is_inside_tree():
				Music.prime_game()

## Small build stamp on the menu footer so the running build is always
## identifiable at a glance (e.g. right after installing a fresh zip).
func _add_version_chip() -> void:
		var chip := Label.new()
		chip.name = "VersionChip"
		chip.text = GameConfig.APP_VERSION
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_font_override("font", NeuKit.bold_font(chip, 0.3))
		SpotRushTypography.apply_as(chip, SpotRushTypography.Role.MICRO)
		chip.add_theme_color_override("font_color", NeuKit.MUTED)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		chip.offset_left = -72.0
		chip.offset_top = -36.0
		chip.offset_right = -18.0
		chip.offset_bottom = -14.0
		var safe_root := get_node_or_null("SafeArea")
		if safe_root != null:
				safe_root.add_child(chip) # inside the padded area (v20 safe insets)
		else:
				add_child(chip)

## Parts of the menu rise in one after another (skipped when Reduce Motion is on).
func _play_entrance() -> void:
		if Feel.reduced():
				return
		var vbox := get_node_or_null("SafeArea/VBoxMain")
		if vbox == null:
				return
		var items: Array = []
		for node_name in ["HeaderBar", "TitleContainer", "SubtitleText"]:
				items.append(vbox.get_node_or_null(node_name))
		items.append_array([btn_solo, btn_multiplayer, btn_how_to_play, vbox.get_node_or_null("FooterBar")])
		for item in items:
				if item is Control:
						(item as Control).modulate.a = 0.0 # hidden before the first frame, so nothing flashes
		await get_tree().process_frame
		for i in items.size():
				var item = items[i]
				if not (item is Control) or not is_instance_valid(item):
						continue
				var c := item as Control
				c.pivot_offset = c.size * 0.5
				c.scale = Vector2(0.9, 0.9)
				var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(c, "scale", Vector2.ONE, 0.5).set_delay(0.06 * i)
				tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(0.06 * i)

var _hero_font_cache: Font = null

## VERY bold wordmark: Baloo 2 ExtraBold through the real variable-font "wght"
## axis (800), plus a display-size embolden kick on top. The hero title is
## display-sized, so it can take the full kick without clogging the letterforms;
## every layer of the 3D stack (shadow, extrusion, highlight, face) shares this
## face so the wordmark reads as one fat, slab-like piece.
func _hero_font() -> Font:
		if _hero_font_cache == null:
				var base: Font = title_text.get_theme_default_font()
				if base == null:
						base = ThemeDB.fallback_font
				_hero_font_cache = NeuKit.weighted_font(base, 800.0, 0.44)
		return _hero_font_cache


func _apply_responsive_layout() -> void:
		if action_row == null or btn_solo == null:
				return
		var view_size := get_viewport_rect().size
		if view_size.x <= 0.0 or view_size.y <= 0.0:
				return
		var narrow := view_size.x < 350.0
		var compact_height := view_size.y < 600.0
		play_mode_badge.visible = not compact_height

		# Size type relative to logical viewport width. The previous values made the title
		# and supporting labels look tiny in the real 900x1600 portrait preview.
		# Typography is semantic and centralized; layout adapts with anchors and
		# wrapping, rather than shrinking type to fit a narrow phone.
		for layer in title_text.get_parent().get_children():
				if layer is RichTextLabel:
						SpotRushTypography.apply_as(layer as RichTextLabel, SpotRushTypography.Role.WORDMARK)
						(layer as RichTextLabel).add_theme_font_override("bold_font", _hero_font())
		SpotRushTypography.apply_as(tagline_text, SpotRushTypography.Role.BODY)
		SpotRushTypography.apply_as(play_text, SpotRushTypography.Role.SCREEN_TITLE)
		SpotRushTypography.apply_as(play_mode_badge, SpotRushTypography.Role.MICRO)
		SpotRushTypography.apply_as(friends_text, SpotRushTypography.Role.CARD_TITLE)
		SpotRushTypography.apply_as(how_text, SpotRushTypography.Role.CARD_TITLE)
		SpotRushTypography.apply_as(best_score_label, SpotRushTypography.Role.CAPTION)
		SpotRushTypography.apply_as(best_score_value, SpotRushTypography.Role.CARD_TITLE)
		SpotRushTypography.apply_as(online_label, SpotRushTypography.Role.CAPTION)

		# Expand the pill hit targets on very narrow screens while preserving the poster-like ratios.
		var play_half_width := 0.325 if narrow else 0.32
		btn_solo.anchor_left = 0.5 - play_half_width
		btn_solo.anchor_right = 0.5 + play_half_width
		btn_solo.anchor_top = 0.425 if compact_height else 0.438
		btn_solo.anchor_bottom = 0.54 if compact_height else 0.548
		btn_solo.custom_minimum_size = Vector2(0, 66 if compact_height else 70)

		var side_half_width := 0.30 if narrow else 0.27
		btn_multiplayer.anchor_left = 0.5 - side_half_width
		btn_multiplayer.anchor_right = 0.5 + side_half_width
		btn_how_to_play.anchor_left = 0.5 - side_half_width
		btn_how_to_play.anchor_right = 0.5 + side_half_width
		btn_multiplayer.anchor_top = 0.565 if compact_height else 0.578
		btn_multiplayer.anchor_bottom = 0.648 if compact_height else 0.658
		btn_how_to_play.anchor_top = 0.67 if compact_height else 0.686
		btn_how_to_play.anchor_bottom = 0.753 if compact_height else 0.766
		btn_multiplayer.custom_minimum_size = Vector2(0, 50 if compact_height else 53)
		btn_how_to_play.custom_minimum_size = Vector2(0, 50 if compact_height else 53)

		# Optical vertical centring: each pill casts its dark shadow downward, so the
		# eye reads extra body below the button and the content looks high. Seat the
		# content rows a few px lower (0 on compact heights, where slack is zero, and
		# gentler near the minimum button height so nothing ever feels clipped).
		var optical_bias := 0.0 if compact_height else (3.0 if view_size.y < 700.0 else 5.0)
		play_content.offset_top = 6.0 + optical_bias
		play_content.offset_bottom = -6.0 + optical_bias
		friends_content.offset_top = 1.0 + optical_bias
		friends_content.offset_bottom = -1.0 + optical_bias
		how_content.offset_top = 1.0 + optical_bias
		how_content.offset_bottom = -1.0 + optical_bias

		# The reference score capsule is deliberately compact (about 30% of screen width).
		btn_streak.anchor_left = 0.35
		btn_streak.anchor_right = 0.65
		btn_streak.anchor_top = 0.835 if compact_height else 0.855
		btn_streak.anchor_bottom = 0.915 if compact_height else 0.93
		btn_streak.custom_minimum_size = Vector2(0, 48 if compact_height else 50)

		# The remaining menu sheets keep generous dimensions; settings now has
		# its own full-screen scene and is intentionally not part of this layout.
		var panel_width := minf(view_size.x - 24.0, 624.0)
		var available_height := maxf(360.0, view_size.y - 48.0)
		var modal_sizes: Array[Vector2] = [
				Vector2(panel_width, minf(600.0, available_height)),
				Vector2(panel_width, minf(640.0, available_height)),
				Vector2(panel_width, minf(660.0, available_height)),
				Vector2(panel_width, minf(660.0, available_height)),
				Vector2(panel_width, minf(660.0, available_height))
		]
		var modals: Array[Control] = [modal_how_to_play, modal_friends, modal_profile, modal_streak, modal_challenge]
		for i in range(modals.size()):
				var modal := modals[i]
				modal.offset_left = -modal_sizes[i].x * 0.5
				modal.offset_right = modal_sizes[i].x * 0.5
				modal.offset_top = -modal_sizes[i].y * 0.5
				modal.offset_bottom = modal_sizes[i].y * 0.5
		var friends_compact := view_size.y < 640.0
		for friend_button in [btn_wifi_lobby, btn_pass_play, btn_challenge_code]:
			if friend_button != null:
				friend_button.custom_minimum_size.y = 78.0 if friends_compact else 92.0
		var friends_vbox := modal_friends.get_node_or_null("Margin/VBox") as VBoxContainer
		if friends_vbox != null:
			friends_vbox.add_theme_constant_override("separation", 8 if friends_compact else 12)
		var friends_margin := modal_friends.get_node_or_null("Margin") as MarginContainer
		if friends_margin != null:
			var margin_value := 14 if friends_compact else 22
			for side in ["margin_top", "margin_bottom"]:
				friends_margin.add_theme_constant_override(side, margin_value)
		var friends_title := modal_friends.get_node_or_null("Margin/VBox/TitleRow/Title") as Label
		if friends_title != null:
			friends_title.add_theme_font_size_override("font_size", 26 if view_size.x < 360.0 else 32)

func _center_button_pivots() -> void:
		for button in [btn_solo, btn_multiplayer, btn_how_to_play, btn_streak]:
				if is_instance_valid(button):
						button.pivot_offset = button.size * 0.5

func _present_modal(modal: Control) -> void:
		if modal == null:
				return
		modal_scrim.visible = true
		modal.visible = true
		modal.pivot_offset = modal.size * 0.5
		modal.scale = Vector2(0.94, 0.94)
		modal.modulate.a = 0.0
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(modal, "scale", Vector2.ONE, 0.20)
		tw.tween_property(modal, "modulate:a", 1.0, 0.16)

func _dismiss_modal(modal: Control) -> void:
		if modal == null:
				return
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(modal, "scale", Vector2(0.97, 0.97), 0.10)
		tw.tween_property(modal, "modulate:a", 0.0, 0.10)
		tw.chain().tween_callback(func():
				modal.visible = false
				modal.scale = Vector2.ONE
				modal.modulate.a = 1.0
				modal_scrim.visible = false
		)

func _process(delta: float) -> void:
		if modal_streak.visible:
				_daily_countdown_acc += delta
				if _daily_countdown_acc >= 1.0:
						_daily_countdown_acc = 0.0
						_update_daily_countdown()
		if is_mini_active:
				mini_time_left -= delta
				if mini_time_left <= 0.0:
						mini_time_left = 0.0
						is_mini_active = false
						play_sfx("wrong")
						_set_mini_feedback("TIME UP! FINAL SCORE: %d" % mini_score, GameConfig.COLOR_ACCENT_RED)
				lbl_mini_timer.text = "%05.2fs" % mini_time_left

func _connect_signals() -> void:
		btn_solo.pressed.connect(_on_solo_pressed)
		btn_multiplayer.pressed.connect(_on_multiplayer_pressed)
		btn_how_to_play.pressed.connect(_on_how_to_play_pressed)
		
		btn_profile.pressed.connect(_on_profile_pressed)
		btn_settings.pressed.connect(_on_settings_pressed)
		btn_streak.pressed.connect(_on_streak_pressed)
		if btn_play_daily != null:
				btn_play_daily.pressed.connect(func(): play_sfx("play"); _on_play_daily_pressed())
		if btn_share_daily != null:
				btn_share_daily.pressed.connect(func(): play_sfx("pop"); _on_share_daily_pressed())
		
		btn_close_how_to.pressed.connect(func(): play_sfx("click"); _dismiss_modal(modal_how_to_play))
		btn_close_friends.pressed.connect(func(): play_sfx("click"); _dismiss_modal(modal_friends))
		btn_wifi_lobby.pressed.connect(func(): play_sfx("play"); modal_scrim.visible = false; SceneRouter.goto_lobby())
		btn_pass_play.pressed.connect(func(): play_sfx("play"); start_quick_mini_game())
		if btn_challenge_code != null:
				btn_challenge_code.pressed.connect(func(): play_sfx("click"); _open_challenge_modal())
		if btn_copy_code != null:
				btn_copy_code.pressed.connect(_on_copy_code_pressed)
		if btn_new_code != null:
				btn_new_code.pressed.connect(_on_new_code_pressed)
		if btn_play_mine != null:
				btn_play_mine.pressed.connect(func(): play_sfx("play"); _play_my_challenge())
		if btn_play_friend != null:
				btn_play_friend.pressed.connect(func(): play_sfx("play"); _play_friend_code())
		if btn_close_challenge != null:
				btn_close_challenge.pressed.connect(func(): play_sfx("click"); _dismiss_modal(modal_challenge))
		if edt_code != null:
				edt_code.text_changed.connect(_on_code_input_changed)
				edt_code.text_submitted.connect(func(_txt):
						if edt_code.text.strip_edges() != "":
								play_sfx("play")
								_play_friend_code())
		btn_close_profile.pressed.connect(func(): play_sfx("click"); _dismiss_modal(modal_profile))
		btn_close_streak.pressed.connect(func(): play_sfx("click"); _dismiss_modal(modal_streak))
		btn_close_mini.pressed.connect(func(): play_sfx("click"); is_mini_active = false; _dismiss_modal(mini_game_overlay))
		
func _close_all_modals() -> void:
		modal_how_to_play.visible = false
		modal_friends.visible = false
		modal_profile.visible = false
		modal_streak.visible = false
		modal_challenge.visible = false
		mini_game_overlay.visible = false
		modal_scrim.visible = false
		token_toast.modulate.a = 0.0

# --- HARDWARE BACK (v19) ------------------------------------------------------------

func _exit_tree() -> void:
		BackNav.unregister(self)

## Android back / desktop Escape: whatever sheet is on top closes first;
## at the root, leaving the game is a two-tap decision - never a stray press.
func handle_back() -> bool:
		if is_navigating or SceneRouter.is_transitioning:
				return true
		# Newest sheet first (the challenge sheet opens on top of the friends flow,
		# the mini-game sits above everything while it runs).
		var sheets: Array = [mini_game_overlay, modal_challenge, modal_streak,
						modal_profile, modal_friends, modal_how_to_play]
		for sheet in sheets:
				if sheet != null and sheet.visible:
						if sheet == mini_game_overlay:
								is_mini_active = false
						play_sfx("click")
						_dismiss_modal(sheet)
						return true
		if modal_scrim.visible:
				play_sfx("click")
				_close_all_modals()
				return true
		NeuDialog.ask("LEAVE SPOTRUSH?",
						"Your streaks, records and rival codes are saved automatically - nothing is lost by leaving.",
						"EXIT", "STAY", func(): get_tree().quit())
		return true

var is_navigating: bool = false
var _daily_countdown_acc: float = 0.0

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
				# Queue the match instead of starting its countdown over the menu. GameScreen
				# consumes this after its signals are connected, so GET READY! is never missed.
				GameManager.queue_single_player_start(selected_rounds)
				SceneRouter.goto_game()
		)

func _on_multiplayer_pressed() -> void:
		play_sfx("click")
		if main_canvas:
				main_canvas.trigger_sparkles(btn_multiplayer.global_position + (btn_multiplayer.size * 0.5))
		_present_modal(modal_friends)

func _on_how_to_play_pressed() -> void:
		play_sfx("click")
		if main_canvas:
				main_canvas.trigger_sparkles(btn_how_to_play.global_position + (btn_how_to_play.size * 0.5))
		_present_modal(modal_how_to_play)

func _on_profile_pressed() -> void:
		play_sfx("click")
		if main_canvas:
				main_canvas.trigger_sparkles(btn_profile.global_position + (btn_profile.size * 0.5))
		_present_modal(modal_profile)

func _on_settings_pressed() -> void:
		play_sfx("click")
		if main_canvas:
				main_canvas.trigger_sparkles(btn_settings.global_position + (btn_settings.size * 0.5))
		SceneRouter.goto_settings()

func _on_streak_pressed() -> void:
		play_sfx("click")
		if main_canvas:
				main_canvas.trigger_sparkles(btn_streak.global_position + (btn_streak.size * 0.5))
		_refresh_personal_best()
		_refresh_daily_modal()
		_present_modal(modal_streak)

func _on_token_clicked(token_name: String) -> void:
		play_sfx("correct")
		token_toast.text = "%s Collected!" % token_name
		token_toast.modulate.a = 1.0
		var tw = create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(token_toast, "modulate:a", 0.0, 0.4)

func _on_emblem_clicked() -> void:
		play_sfx("click")

func _style_hero_actions() -> void:
		# Give the primary action a richer enamel finish while secondary keys stay quiet.
		var play_style = btn_solo.get_meta("neu_style", null)
		if play_style != null:
				play_style.gradient = 0.95
				play_style.rim = 0.88
				play_style.distance = 11.0
				play_style.blur = 24.0
				play_style.glow = Color(NeuKit.COBALT.r, NeuKit.COBALT.g, NeuKit.COBALT.b, 0.34)
				play_style.emit_changed()
		for button in [btn_multiplayer, btn_how_to_play]:
				var style = button.get_meta("neu_style", null)
				if style != null:
						style.gradient = 0.62
						style.rim = 0.78
						style.emit_changed()
		var badge_style := NeuKit.raised(999.0, 3.0, 9.0, NeuKit.SURFACE.lerp(NeuKit.CANARY, 0.10))
		badge_style.content_margin_left = 13.0
		badge_style.content_margin_right = 13.0
		badge_style.content_margin_top = 3.0
		badge_style.content_margin_bottom = 3.0
		badge_style.gradient = 0.65
		play_mode_badge.add_theme_stylebox_override("normal", badge_style)
		play_mode_badge.add_theme_color_override("font_color", NeuKit.COBALT)
		play_mode_badge.add_theme_font_override("font", NeuKit.bold_font(play_mode_badge, 0.65))

## The friends sheet: three distinct ways to duel, each presented as a spacious
## icon-led choice row. The existing buttons and their navigation remain intact.
func _style_friends_modal() -> void:
		var card: PanelContainer = modal_friends as PanelContainer
		if card == null:
			return
		var card_style: NeuStyle = card.get_theme_stylebox("panel") as NeuStyle
		if card_style != null:
			card_style.corner_radius = 34.0
			card_style.distance = 13.0
			card_style.blur = 28.0
			card_style.rim = 0.82
			card_style.emit_changed()
		var vbox := card.get_node_or_null("Margin/VBox") as VBoxContainer
		if vbox == null:
			return
		vbox.add_theme_constant_override("separation", 12)

		var title := vbox.get_node_or_null("TitleRow/Title") as Label
		if title != null:
			var base: Font = title.get_theme_default_font()
			if base == null:
				base = ThemeDB.fallback_font
			title.add_theme_font_override("font", NeuKit.weighted_font(base, 800.0, 0.42))
			title.add_theme_font_size_override("font_size", 32)
			title.add_theme_color_override("font_color", NeuKit.INK)
			NeuKit.etch(title)
		var subtitle := vbox.get_node_or_null("Subtitle") as Label
		if subtitle != null:
			subtitle.add_theme_font_size_override("font_size", 18)
			subtitle.add_theme_color_override("font_color", NeuKit.SLATE)
		var people_glyph := vbox.get_node_or_null("TitleRow/GlyphPeople") as Control
		if people_glyph != null and people_glyph.has_method("set"):
			people_glyph.set("icon_color", NeuKit.COBALT)

		# Each route is now a proper choice row: a sculpted icon well, a clear title,
		# a one-line explanation, and a quiet directional cue. The actual Buttons,
		# signals, and navigation targets remain the original ones.
		_build_friends_option(
			vbox.get_node_or_null("BtnWifiLobby") as Button,
			"wifi", "WI-FI DUEL", "Two phones · same Wi-Fi network",
			NeuKit.COBALT, true
		)
		_build_friends_option(
			vbox.get_node_or_null("BtnPassPlay") as Button,
			"quick", "QUICK MINI-GAME", "One phone · 5-second spot sprint",
			NeuKit.MINT, false
		)
		_build_friends_option(
			vbox.get_node_or_null("BtnChallengeCode") as Button,
			"code", "RIVAL CODE", "Share a code · same seeded run",
			NeuKit.LAVENDER, false
		)
		_caption_button(vbox.get_node_or_null("BtnCloseFriends") as Button,
			"CLOSE", "", 18, 0, NeuKit.SLATE, NeuKit.COBALT, NeuKit.MUTED)

func _build_friends_option(btn: Button, icon_key: String, option_title_text: String,
	caption_text: String, tint: Color, primary: bool) -> void:
		if btn == null:
			return
		btn.text = ""
		btn.custom_minimum_size.y = 92.0
		btn.focus_mode = Control.FOCUS_ALL

		var button_style = btn.get_meta("neu_style", null)
		if button_style is NeuStyle:
			var style := button_style as NeuStyle
			if not primary:
				style.surface = NeuKit.SURFACE.lerp(tint, 0.055)
				style.colored = false
				style.distance = 6.0
				style.blur = 15.0
				style.rim = 0.82
			else:
				style.glow = Color(tint.r, tint.g, tint.b, 0.34)
				style.distance = 8.0
				style.blur = 18.0
			style.emit_changed()

		var row := HBoxContainer.new()
		row.name = "ChoiceContent"
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 16.0
		row.offset_top = 8.0
		row.offset_right = -16.0
		row.offset_bottom = -8.0
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(row)

		var icon_well := PanelContainer.new()
		icon_well.name = "IconWell"
		icon_well.custom_minimum_size = Vector2(56.0, 56.0)
		icon_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var well_surface := tint.darkened(0.18) if primary else NeuKit.SURFACE.lerp(tint, 0.12)
		var well_style := NeuKit.inset(28.0, 3.0, 8.0, well_surface)
		well_style.rim = 0.72
		icon_well.add_theme_stylebox_override("panel", well_style)
		row.add_child(icon_well)

		var icon := MainMenuIcon.new()
		icon.name = "ChoiceIcon"
		icon.icon_name = icon_key
		icon.icon_color = Color.WHITE if primary else tint.darkened(0.26)
		icon.accent_surface = primary
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 12.0
		icon.offset_top = 12.0
		icon.offset_right = -12.0
		icon.offset_bottom = -12.0
		icon_well.add_child(icon)

		var copy := VBoxContainer.new()
		copy.name = "ChoiceCopy"
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		copy.add_theme_constant_override("separation", 3)
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(copy)

		var title := Label.new()
		title.name = "ChoiceTitle"
		title.text = option_title_text
		title.clip_text = true
		title.add_theme_font_override("font", NeuKit.bold_font(title, 0.42))
		SpotRushTypography.apply_as(title, SpotRushTypography.Role.BUTTON_LARGE)
		title.add_theme_color_override("font_color", Color.WHITE if primary else NeuKit.INK)
		copy.add_child(title)

		var caption := Label.new()
		caption.name = "ChoiceCaption"
		caption.text = caption_text
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD
		SpotRushTypography.apply_as(caption, SpotRushTypography.Role.CAPTION)
		caption.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.82) if primary else NeuKit.SLATE)
		copy.add_child(caption)

		var arrow := MainMenuIcon.new()
		arrow.name = "ChoiceArrow"
		arrow.icon_name = "chevron"
		arrow.icon_color = Color(1.0, 1.0, 1.0, 0.86) if primary else NeuKit.SLATE
		arrow.custom_minimum_size = Vector2(24.0, 34.0)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(arrow)
## Results-screen style key: a NeuText caption that dips with the key press,
## plus an optional small guidance line pinned to the bottom of the key face.
func _caption_button(btn: Button, button_title_text: String, caption_text: String, font_size: int, look: int, color: Color, base: Color, caption_color: Color) -> void:
		if btn == null:
				return
		btn.text = ""
		var label := NeuText.new()
		label.text = button_title_text
		label.font_size = font_size
		label.color = color
		label.look = look
		label.accent_base = base
		label.tracking = 2.0
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		if not caption_text.is_empty():
				label.offset_bottom = -24.0 # re-centres the title above the guidance line
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(label)
		if btn.has_meta("neu_style"):
				label.bind_style(btn.get_meta("neu_style"))
		if caption_text.is_empty():
				return
		var caption := Label.new()
		caption.text = caption_text
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		SpotRushTypography.apply_as(caption, SpotRushTypography.Role.CAPTION)
		caption.add_theme_color_override("font_color", caption_color)
		caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		caption.offset_top = -26.0
		caption.offset_bottom = -6.0
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(caption)

## The how-to sheet: pure typography on inset wells - no icons anywhere. The title
## shares the wordmark's extra-bold face so the sheet reads as part of the poster,
## and every rule keeps big, high-contrast type.
func _style_how_to_modal() -> void:
		var card: PanelContainer = modal_how_to_play as PanelContainer
		if card == null:
				return
		var vbox: Control = card.get_node_or_null("Margin/VBox")
		if vbox == null:
				return
		var title: Label = vbox.get_node_or_null("Header/Title") as Label
		if title != null:
				var base: Font = title.get_theme_default_font()
				if base == null:
						base = ThemeDB.fallback_font
				title.add_theme_font_override("font", NeuKit.weighted_font(base, 800.0, 0.40))
				title.add_theme_color_override("font_color", NeuKit.INK)
				NeuKit.etch(title)
		var subtitle: Label = vbox.get_node_or_null("Header/Subtitle") as Label
		if subtitle != null:
				subtitle.add_theme_color_override("font_color", NeuKit.SLATE)
		var grid: GridContainer = vbox.get_node_or_null("ModeGrid") as GridContainer
		if grid != null:
				for cell in grid.get_children():
						var name_label: Label = cell.get_node_or_null("Margin/Col/Name") as Label
						if name_label != null:
								name_label.add_theme_font_override("font", NeuKit.bold_font(name_label, 0.45))
								name_label.add_theme_color_override("font_color", NeuKit.INK)
								NeuKit.etch(name_label)
						var desc_label: Label = cell.get_node_or_null("Margin/Col/Desc") as Label
						if desc_label != null:
								desc_label.add_theme_color_override("font_color", NeuKit.SLATE)
		var tip: Label = vbox.get_node_or_null("Tip") as Label
		if tip != null:
				tip.add_theme_color_override("font_color", NeuKit.SLATE)

## The personal-best sheet: a letterpressed caption over one sunken score well.
## Quiet, monochrome, and driven entirely by the saved Records value.
func _style_personal_best_modal() -> void:
		var card: PanelContainer = modal_streak as PanelContainer
		if card == null:
				return
		var vbox: Control = card.get_node_or_null("Margin/VBox")
		if vbox == null:
				return
		var caption: Label = vbox.get_node_or_null("Caption") as Label
		if caption != null:
				caption.add_theme_font_override("font", NeuKit.bold_font(caption, 0.35))
				caption.add_theme_color_override("font_color", NeuKit.MUTED)
		var value: Label = vbox.get_node_or_null("ScoreWell/WellMargin/WellVBox/BestModalValue") as Label
		if value != null:
				var base: Font = value.get_theme_default_font()
				if base == null:
						base = ThemeDB.fallback_font
				value.add_theme_font_override("font", NeuKit.weighted_font(base, 800.0, 0.30))
				value.add_theme_color_override("font_color", NeuKit.COBALT)
				NeuKit.etch(value)
		var hint: Label = vbox.get_node_or_null("ScoreWell/WellMargin/WellVBox/BestModalHint") as Label
		if hint != null:
				hint.add_theme_color_override("font_color", NeuKit.SLATE)

## Writes the REAL saved best score everywhere it is shown (footer pill + modal).
func _refresh_personal_best() -> void:
		var best: int = Records.best()
		best_score_value.text = Records.format(best)
		if best_modal_value != null:
				best_modal_value.text = Records.format(best)
		if best_modal_hint != null:
				if best <= 0:
						best_modal_hint.text = "No record yet - play a solo sprint to set one!"
				else:
						best_modal_hint.text = "Your record to beat. Can you top it in a %d-round sprint?" % selected_rounds

## Results-screen style keys for the daily hub, same anatomy as the friends sheet.
func _style_daily_modal() -> void:
		if btn_play_daily != null:
				_caption_button(btn_play_daily, "PLAY TODAY'S SPOT",
								"10 seeded rounds - everyone plays the same", 28,
								3, Color.WHITE, NeuKit.COBALT, Color(1, 1, 1, 0.78))
		if btn_share_daily != null:
				_caption_button(btn_share_daily, "SHARE RESULT", "", 20,
								0, NeuKit.SLATE, NeuKit.COBALT, NeuKit.MUTED)
		var card := modal_streak as PanelContainer
		if card != null:
				var cs: NeuStyle = card.get_theme_stylebox("panel") as NeuStyle
				if cs != null:
						cs.corner_radius = 32.0
						cs.distance = 12.0
						cs.blur = 26.0
						cs.emit_changed()

## Refresh the daily hub every time it opens: issue number, streak line, and
## either the play key (not done yet) or today's result + share key (done).
func _refresh_daily_modal() -> void:
		if lbl_daily_number != null:
				lbl_daily_number.text = "SPOT #%d" % Records.daily_number()
		var done := Records.daily_completed_today()
		if btn_play_daily != null:
				btn_play_daily.visible = not done
		if lbl_daily_done != null:
				lbl_daily_done.visible = done
				if done:
						lbl_daily_done.text = "TODAY: %s PTS  -  %d/%d CORRECT" % [
								Records.format(Records.daily_today_score()),
								Records.daily_today_correct(),
								Records.daily_today_rounds()]
		if btn_share_daily != null:
				btn_share_daily.visible = done
		if lbl_daily_streak != null:
				var st := Records.daily_streak()
				if st <= 0:
						lbl_daily_streak.text = "Play today's spot to start your streak!"
				else:
						lbl_daily_streak.text = "Day streak: %d  -  1 shield a week guards it" % st
		_update_daily_countdown()

func _update_daily_countdown() -> void:
		if lbl_daily_countdown == null:
				return
		var t := Time.get_time_dict_from_system()
		var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
		var hours: int = floori(float(left) / 3600.0)
		var minutes: int = floori(float(left) / 60.0) % 60
		var seconds: int = posmod(left, 60)
		lbl_daily_countdown.text = "NEXT SPOT IN %02d:%02d:%02d" % [hours, minutes, seconds]

func _on_play_daily_pressed() -> void:
		if is_navigating or Records.daily_completed_today():
				return
		is_navigating = true
		modal_scrim.visible = false
		GameManager.queue_daily_start()
		SceneRouter.goto_game()

func _on_share_daily_pressed() -> void:
		DisplayServer.clipboard_set(Records.daily_share_text())
		Feel.sfx("pop")
		if btn_share_daily != null:
				_set_key_title_text(btn_share_daily, "COPIED!")
				get_tree().create_timer(1.2).timeout.connect(func():
						if is_instance_valid(btn_share_daily) and btn_share_daily.is_inside_tree():
								_set_key_title_text(btn_share_daily, "SHARE RESULT"))

func _set_key_title_text(btn: Button, txt: String) -> void:
		for k in btn.get_children():
				if k is NeuText:
						(k as NeuText).text = txt
						return

# --- RIVAL CODES (v17 async challenges) ----------------------------------------------

## The Rival Codes sheet: the same editorial anatomy as the friends sheet, plus
## a deep code well and a seeded-run input. Copying brags, NEW mints a fresh
## run, and the friend field forgives every paste format chat apps invent.
func _style_challenge_modal() -> void:
		var card: PanelContainer = modal_challenge as PanelContainer
		if card == null:
				return
		var card_style: NeuStyle = card.get_theme_stylebox("panel") as NeuStyle
		if card_style != null:
				card_style.corner_radius = 32.0
				card_style.distance = 12.0
				card_style.blur = 26.0
				card_style.emit_changed()
		var vbox: Control = card.get_node_or_null("Margin/VBox")
		if vbox == null:
				return
		var title: Label = vbox.get_node_or_null("TitleRow/Title") as Label
		if title != null:
				var tbase: Font = title.get_theme_default_font()
				if tbase == null:
						tbase = ThemeDB.fallback_font
				title.add_theme_font_override("font", NeuKit.weighted_font(tbase, 800.0, 0.40))
				title.add_theme_color_override("font_color", NeuKit.INK)
				NeuKit.etch(title)
		var subtitle: Label = vbox.get_node_or_null("Subtitle") as Label
		if subtitle != null:
				subtitle.add_theme_color_override("font_color", NeuKit.SLATE)
		var glyph: Control = vbox.get_node_or_null("TitleRow/GlyphTarget") as Control
		if glyph != null:
				glyph.set("glyph_color", NeuKit.SLATE)
		var code_label: Label = vbox.get_node_or_null("CodeRow/CodeWell/WellMargin/LblMyCode") as Label
		if code_label != null:
				var cbase: Font = code_label.get_theme_default_font()
				if cbase == null:
						cbase = ThemeDB.fallback_font
				code_label.add_theme_font_override("font", NeuKit.weighted_font(cbase, 800.0, 0.24))
				code_label.add_theme_color_override("font_color", NeuKit.COBALT)
				NeuKit.etch(code_label)
		var edt := vbox.get_node_or_null("EdtCode") as LineEdit
		if edt != null:
				edt.add_theme_font_override("font", NeuKit.bold_font(edt, 0.55))
				NeuKit.style_line_edit(edt, 20.0)
		_caption_button(vbox.get_node_or_null("BtnPlayMine") as Button,
						"PLAY MY CHALLENGE", "Your seeded run - your score to share", 26,
						3, Color.WHITE, NeuKit.COBALT, Color(1, 1, 1, 0.78))
		_caption_button(vbox.get_node_or_null("BtnPlayFriend") as Button,
						"PLAY FRIEND'S RUN", "Same rounds, same clock - may the best spotter win", 26,
						3, Color.WHITE, NeuKit.COBALT, Color(1, 1, 1, 0.78))
		for key_name in ["BtnCopyCode", "BtnNewCode"]:
				var key := vbox.get_node_or_null("CodeRow/" + key_name) as Button
				if key != null:
						SpotRushTypography.apply_as(key, SpotRushTypography.Role.BUTTON)
		var close_btn := vbox.get_node_or_null("BtnCloseChallenge") as Button
		if close_btn != null:
				SpotRushTypography.apply_as(close_btn, SpotRushTypography.Role.BUTTON)

func _open_challenge_modal() -> void:
		_refresh_challenge_modal()
		_present_modal(modal_challenge)

func _refresh_challenge_modal() -> void:
		if lbl_my_code != null:
				lbl_my_code.text = ChallengeCodes.display_form(Records.my_challenge_code())
		if edt_code != null:
				edt_code.text = ""
		_set_challenge_status(" ", NeuKit.SLATE)

func _on_copy_code_pressed() -> void:
		DisplayServer.clipboard_set(Records.challenge_invite_text())
		Feel.sfx("pop")
		Feel.haptic("light")
		if btn_copy_code != null:
				btn_copy_code.text = "COPIED!"
				get_tree().create_timer(1.2).timeout.connect(func():
						if is_instance_valid(btn_copy_code) and btn_copy_code.is_inside_tree():
								btn_copy_code.text = "COPY")

## A new seed under the same tap. The previous code keeps working for anyone
## who already typed it in - the code IS the match, nothing server-side moves.
func _on_new_code_pressed() -> void:
		Records.reroll_my_challenge_code()
		Feel.sfx("spot")
		Feel.haptic("medium")
		_refresh_challenge_modal()
		_set_challenge_status("FRESH RUN MINTED - YOUR OLD CODE KEEPS WORKING", NeuKit.SLATE)

func _play_my_challenge() -> void:
		_start_challenge_run(Records.my_challenge_code())

func _play_friend_code() -> void:
		if edt_code == null:
				return
		if edt_code.text.strip_edges().is_empty():
				_set_challenge_status("TYPE OR PASTE A CODE FIRST", NeuKit.SLATE)
				return
		_start_challenge_run(edt_code.text)

func _start_challenge_run(code: String) -> void:
		if is_navigating:
				return
		if not GameManager.queue_challenge_start(code):
				Feel.sfx("wrong")
				Feel.haptic("error")
				_set_challenge_status("THAT CODE DOESN'T CHECK OUT - RETYPE IT?", Color("D63A4A"))
				return
		is_navigating = true
		modal_scrim.visible = false
		SceneRouter.goto_game()

## Keep the input clean while typing: uppercase, base36 only, grouped in threes.
## The equality guard stops the rewrite from re-firing the signal forever.
func _on_code_input_changed(new_text: String) -> void:
		if edt_code == null:
				return
		var formatted := _format_code_input(new_text)
		if formatted == new_text:
				return
		var caret := edt_code.caret_column
		var was_at_end := caret >= new_text.length()
		edt_code.text = formatted
		edt_code.caret_column = formatted.length() if was_at_end else mini(caret, formatted.length())

func _format_code_input(raw: String) -> String:
		var clean := ChallengeCodes.normalize(raw)
		if clean.length() > ChallengeCodes.CODE_CHARS:
				clean = clean.substr(0, ChallengeCodes.CODE_CHARS)
		var out := ""
		for i in clean.length():
				if i > 0 and i % ChallengeCodes.GROUP == 0:
						out += "-"
				out += clean[i]
		return out

func _set_challenge_status(message: String, color: Color) -> void:
		if lbl_challenge_status == null:
				return
		lbl_challenge_status.text = message
		lbl_challenge_status.add_theme_color_override("font_color", color)

func _style_toast() -> void:
		var chip := NeuKit.raised(18.0, 5.0, 12.0)
		chip.content_margin_left = 14.0
		chip.content_margin_right = 14.0
		token_toast.add_theme_stylebox_override("normal", chip)
		token_toast.add_theme_color_override("font_color", NeuKit.COBALT)

func _set_mini_feedback(message: String, color: Color) -> void:
		lbl_mini_feedback.text = message
		lbl_mini_feedback.add_theme_color_override("font_color", color)
		lbl_mini_feedback.modulate = Color.WHITE

# --- QUICK INTERACTIVE MINI-GAME ---

func start_quick_mini_game() -> void:
		_close_all_modals()
		_present_modal(mini_game_overlay)
		mini_score = 0
		lbl_mini_score.text = "0"
		_set_mini_feedback("TAP THE ODD SHAPE!", GameConfig.COLOR_ACCENT_BLUE)
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
				
				NeuKit.style_button(btn, "raised", 22.0)
				
				# Vector icons drawn in-engine: symbol glyphs (circle/square/triangle/diamond)
				# are missing from Baloo 2 and would fall back to tofu boxes on device.
				var is_odd = (i == mini_odd_index)
				var col = odd_color if is_odd else base_color
				var icon: Control = SpotRushGlyph.new()
				icon.glyph = common_shape
				icon.glyph_color = col
				icon.set_anchors_preset(Control.PRESET_FULL_RECT)
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(icon)

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
				_set_mini_feedback("PERFECT SPOT! +100", Color("2E9658"))
				mini_time_left = 5.0
				_generate_mini_board()
		else:
				play_sfx("wrong")
				mini_time_left = maxf(0.0, mini_time_left - 1.0)
				_set_mini_feedback("WRONG! -1.0s PENALTY", GameConfig.COLOR_ACCENT_RED)

# --- PROCEDURAL SYNTHESIZED AUDIO SFX ---

func play_sfx(type: String) -> void:
		# Every NeuKit key now makes its own press/release sound, so "click" needs nothing here.
		# Only the non-button cues are mapped onto the shared sound bank.
		match type:
				"play":
						Feel.sfx("spot")
						Feel.haptic("medium")
				"correct":
						Feel.sfx("correct")
						Feel.haptic("success")
				"wrong":
						Feel.sfx("wrong")
						Feel.haptic("error")
