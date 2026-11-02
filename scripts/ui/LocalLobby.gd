extends Control

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const LanDiscoveryScript = preload("res://scripts/networking/LanDiscovery.gd")
const Records = preload("res://scripts/core/Records.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const CommunityQRCodeRect = preload("res://addons/kenyoni/qr_code/qr_code_rect.gd")
const CommunityQRCode = preload("res://addons/kenyoni/qr_code/qr_code.gd")

enum LobbyTab { CREATE, JOIN, RIVAL }

@onready var btn_back: Button = %BtnBack
@onready var btn_tab_create: Button = %BtnTabCreate
@onready var btn_tab_join: Button = %BtnTabJoin
@onready var btn_tab_rival: Button = %BtnTabRival
@onready var panel_create: Control = %PanelCreate
@onready var panel_join: Control = %PanelJoin
@onready var panel_rival: Control = %PanelRival

@onready var qr_slot: CenterContainer = %QrSlot
@onready var qr_placeholder: Label = %QrPlaceholder
@onready var lbl_room_code: Label = %LblRoomCode
@onready var lbl_create_status: Label = %LblCreateStatus
@onready var btn_create_room: Button = %BtnCreateRoom
@onready var btn_copy_room_code: Button = %BtnCopyRoomCode
@onready var btn_end_room: Button = %BtnEndRoom
@onready var btn_start_match: Button = %BtnStartMatch

@onready var line_edit_room_code: LineEdit = %LineEditRoomCode
@onready var btn_join_room: Button = %BtnJoinRoom
@onready var lbl_join_status: Label = %LblJoinStatus

@onready var lbl_my_rival_code: Label = %LblMyRivalCode
@onready var btn_copy_rival_code: Button = %BtnCopyRivalCode
@onready var btn_new_rival_code: Button = %BtnNewRivalCode
@onready var btn_play_my_rival_code: Button = %BtnPlayMyRivalCode
@onready var line_edit_rival_code: LineEdit = %LineEditRivalCode
@onready var btn_play_rival_code: Button = %BtnPlayRivalCode
@onready var lbl_rival_status: Label = %LblRivalStatus

var _active_tab: LobbyTab = LobbyTab.CREATE
var _room_open: bool = false
var _room_transport: StringName = &"none"
var _friend_connected: bool = false
var _qr_rect: TextureRect
var _watchdog_token: int = 0
var is_navigating: bool = false
var _closing_room: bool = false


func _ready() -> void:
	SpotRushSkin.apply_screen(self, "lobby")
	BackNav.register(self)
	NeuSafe.fit(get_node_or_null("SafeArea"))
	Music.play_menu()

	_connect_ui()
	_style_ui()
	_build_qr()
	_refresh_rival_code()
	_set_active_tab(LobbyTab.CREATE, false)

	NetworkSession.connection_succeeded.connect(_on_join_succeeded)
	NetworkSession.connection_failed.connect(_on_join_failed)
	NetworkSession.peer_connected.connect(_on_peer_connected)
	NetworkSession.peer_disconnected.connect(_on_peer_disconnected)
	NetworkSession.server_disconnected.connect(_on_server_disconnected)
	if DeepLinkRouter.has_signal("invitation_received"):
		DeepLinkRouter.invitation_received.connect(_on_invitation_received)

	var pending_invitation: Dictionary = DeepLinkRouter.consume_pending_invitation()
	if not pending_invitation.is_empty():
		call_deferred("_handle_invitation", pending_invitation)

	_set_create_room_idle()


func _connect_ui() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	btn_tab_create.pressed.connect(func() -> void: _set_active_tab(LobbyTab.CREATE))
	btn_tab_join.pressed.connect(func() -> void: _set_active_tab(LobbyTab.JOIN))
	btn_tab_rival.pressed.connect(func() -> void: _set_active_tab(LobbyTab.RIVAL))

	btn_create_room.pressed.connect(_on_create_room_pressed)
	btn_copy_room_code.pressed.connect(_on_copy_room_code_pressed)
	btn_end_room.pressed.connect(_on_end_room_pressed)
	btn_start_match.pressed.connect(_on_start_match_pressed)

	btn_join_room.pressed.connect(_on_join_room_pressed)
	line_edit_room_code.text_changed.connect(_on_room_code_changed)
	line_edit_room_code.text_submitted.connect(func(_value: String) -> void: _on_join_room_pressed())

	btn_copy_rival_code.pressed.connect(_on_copy_rival_code_pressed)
	btn_new_rival_code.pressed.connect(_on_new_rival_code_pressed)
	btn_play_my_rival_code.pressed.connect(func() -> void: _start_rival_run(Records.my_challenge_code()))
	btn_play_rival_code.pressed.connect(_on_play_rival_code_pressed)
	line_edit_rival_code.text_changed.connect(_on_rival_code_changed)
	line_edit_rival_code.text_submitted.connect(func(_value: String) -> void: _on_play_rival_code_pressed())


func _style_ui() -> void:
	for label in find_children("*", "Label", true, false):
		SpotRushTypography.apply_as(label as Label, SpotRushTypography.Role.BODY)

	for button in [btn_back, btn_tab_create, btn_tab_join, btn_tab_rival,
			btn_create_room, btn_copy_room_code, btn_end_room, btn_start_match,
			btn_join_room, btn_copy_rival_code, btn_new_rival_code,
			btn_play_my_rival_code, btn_play_rival_code]:
		SpotRushTypography.apply_as(button, SpotRushTypography.Role.BUTTON_LARGE)

	NeuKit.style_line_edit(line_edit_room_code, 18.0)
	NeuKit.style_line_edit(line_edit_rival_code, 18.0)
	line_edit_room_code.add_theme_color_override("font_placeholder_color", NeuKit.SLATE)
	line_edit_rival_code.add_theme_color_override("font_placeholder_color", NeuKit.SLATE)

	lbl_room_code.add_theme_color_override("font_color", NeuKit.COBALT)
	lbl_my_rival_code.add_theme_color_override("font_color", NeuKit.COBALT)
	lbl_create_status.add_theme_color_override("font_color", NeuKit.SLATE)
	lbl_join_status.add_theme_color_override("font_color", NeuKit.SLATE)
	lbl_rival_status.add_theme_color_override("font_color", NeuKit.SLATE)


func _build_qr() -> void:
	_qr_rect = CommunityQRCodeRect.new()
	_qr_rect.name = "RoomInvitationQR"
	_qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr_rect.custom_minimum_size = Vector2(292.0, 292.0)
	_qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_qr_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_qr_rect.set("auto_module_size", true)
	_qr_rect.set("mode", CommunityQRCode.Mode.BYTE)
	_qr_rect.set("use_eci", true)
	_qr_rect.set("eci_value", CommunityQRCode.ECI.UTF_8)
	_qr_rect.set("error_correction", CommunityQRCode.ErrorCorrection.MEDIUM)
	_qr_rect.visible = false
	qr_slot.add_child(_qr_rect)


func _set_active_tab(tab: LobbyTab, animate: bool = true) -> void:
	_active_tab = tab
	panel_create.visible = tab == LobbyTab.CREATE
	panel_join.visible = tab == LobbyTab.JOIN
	panel_rival.visible = tab == LobbyTab.RIVAL

	for pair in [
		[btn_tab_create, tab == LobbyTab.CREATE],
		[btn_tab_join, tab == LobbyTab.JOIN],
		[btn_tab_rival, tab == LobbyTab.RIVAL]
	]:
		var button: Button = pair[0]
		var selected: bool = pair[1]
		NeuKit.set_selected(button, selected)
		var color: Color = NeuKit.COBALT if selected else NeuKit.SLATE
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, color)

	if animate and not Feel.reduced():
		var active_panel: Control = panel_create if tab == LobbyTab.CREATE else panel_join if tab == LobbyTab.JOIN else panel_rival
		active_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(active_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_create_room_idle() -> void:
	lbl_room_code.text = "--------"
	qr_placeholder.text = "YOUR ROOM QR\nAPPEARS HERE"
	qr_placeholder.visible = true
	_qr_rect.visible = false
	btn_create_room.visible = true
	btn_create_room.disabled = false
	btn_copy_room_code.visible = false
	btn_end_room.visible = false
	btn_end_room.disabled = false
	btn_start_match.visible = false
	btn_start_match.disabled = false
	_friend_connected = false
	_set_status(lbl_create_status, "Create a room to reveal its QR invitation and shareable code.", NeuKit.SLATE)


func _set_status(label: Label, message: String, color: Color) -> void:
	label.text = message
	label.add_theme_color_override("font_color", color)


func _set_room_invitation(code: String) -> void:
	lbl_room_code.text = code
	btn_create_room.visible = false
	btn_copy_room_code.visible = true
	btn_end_room.visible = true
	btn_start_match.visible = false
	qr_placeholder.visible = false

	var link: String = DeepLinkRouter.make_room_code_link(code)
	if link.is_empty():
		_qr_rect.visible = false
		qr_placeholder.text = "QR INVITATION COULDN'T BE GENERATED"
		qr_placeholder.visible = true
	else:
		_qr_rect.set("data", link)
		_qr_rect.visible = true
		_qr_rect.reset_size()
	_set_status(lbl_create_status, "Room is open. Your friend can scan the QR or enter the code in JOIN.", NeuKit.MINT.darkened(0.34))


func _on_create_room_pressed() -> void:
	if _room_open or is_navigating:
		return
	if not NetworkSession.has_eos_p2p_support():
		_set_status(lbl_create_status, "Online rooms are unavailable in this build. Use RIVAL CODE for offline play.", NeuKit.CORAL)
		Feel.sfx("wrong")
		return

	btn_create_room.disabled = true
	_set_status(lbl_create_status, "Connecting to SpotRush online services...", NeuKit.SLATE)

	var result: Dictionary = await EOSOnline.create_public_room_async()
	if not is_inside_tree():
		return
	if not bool(result.get("ok", false)):
		btn_create_room.disabled = false
		_set_status(lbl_create_status, str(result.get("error", "Couldn't create a room. Please try again.")), NeuKit.CORAL)
		Feel.sfx("wrong")
		return

	_room_open = true
	_room_transport = &"eos_p2p"
	_set_room_invitation(str(result.get("code", EOSOnline.get_current_room_code())))
	Feel.sfx("correct")
	Feel.haptic("success")


func _on_copy_room_code_pressed() -> void:
	if not _room_open:
		return
	DisplayServer.clipboard_set(EOSOnline.get_current_room_code())
	btn_copy_room_code.text = "COPIED!"
	Feel.sfx("correct")
	Feel.haptic("light")
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(btn_copy_room_code) and btn_copy_room_code.is_inside_tree():
			btn_copy_room_code.text = "COPY ROOM CODE"
	)


func _on_end_room_pressed() -> void:
	if _closing_room or is_navigating:
		return
	btn_back.disabled = true
	btn_end_room.disabled = true
	btn_start_match.disabled = true
	await _close_current_room()
	btn_back.disabled = false
	_set_create_room_idle()
	_set_status(lbl_create_status, "Room ended. Create a new one whenever you're ready.", NeuKit.SLATE)
	Feel.sfx("click")


func _close_current_room() -> void:
	if _closing_room:
		return
	_closing_room = true
	_cancel_join_watchdog()

	if EOSOnline.has_current_lobby():
		await EOSOnline.leave_current_lobby_async()
	NetworkSession.disconnect_session()

	_room_open = false
	_room_transport = &"none"
	_friend_connected = false
	_closing_room = false


func _on_peer_connected(_peer_id: int) -> void:
	if not _room_open or not NetworkSession.is_host():
		return
	_friend_connected = true
	_set_status(lbl_create_status, "Your friend is connected. You're both ready!", NeuKit.MINT.darkened(0.34))
	btn_start_match.visible = true
	await EOSOnline.update_current_room_status_async("full")
	Feel.sfx("correct")
	Feel.haptic("success")


func _on_peer_disconnected(_peer_id: int) -> void:
	if not _room_open or not NetworkSession.is_host():
		return
	_friend_connected = false
	btn_start_match.visible = false
	_set_status(lbl_create_status, "Your friend left. The room is open again.", NeuKit.SLATE)
	await EOSOnline.update_current_room_status_async("open")


func _on_start_match_pressed() -> void:
	if is_navigating or not _friend_connected:
		return
	is_navigating = true
	btn_start_match.disabled = true
	btn_back.disabled = true
	btn_end_room.disabled = true
	await EOSOnline.update_current_room_status_async("playing")
	GameManager.queue_multiplayer_host_start(10)
	SceneRouter.goto_game()


func _on_join_room_pressed() -> void:
	var code: String = line_edit_room_code.text.strip_edges().to_upper()
	if code.length() != EOSOnline.ROOM_CODE_LENGTH:
		_set_status(lbl_join_status, "Enter the 8-character room code.", NeuKit.CORAL)
		Feel.sfx("wrong")
		return
	await _join_online_code(code)


func _join_online_code(code: String) -> void:
	if is_navigating:
		return
	if not NetworkSession.has_eos_p2p_support():
		_set_status(lbl_join_status, "Online rooms are unavailable in this build. RIVAL CODE works offline.", NeuKit.CORAL)
		return

	btn_join_room.disabled = true
	_set_status(lbl_join_status, "Finding room %s..." % code, NeuKit.SLATE)
	var joined: bool = await EOSOnline.join_room_code_async(code)
	if not is_inside_tree():
		return
	if not joined:
		btn_join_room.disabled = false
		_set_status(lbl_join_status, EOSOnline.last_error, NeuKit.CORAL)
		Feel.sfx("wrong")
		return

	_room_transport = &"eos_p2p"
	_arm_join_watchdog(25.0)
	_set_status(lbl_join_status, "Room found. Connecting directly to your friend...", NeuKit.SLATE)
	Feel.sfx("correct")


func _on_room_code_changed(new_text: String) -> void:
	var clean: String = new_text.to_upper()
	var filtered: String = ""
	for character in clean:
		var char_text: String = str(character)
		if EOSOnline.ROOM_CODE_ALPHABET.contains(char_text) and filtered.length() < EOSOnline.ROOM_CODE_LENGTH:
			filtered += char_text
	if filtered != new_text:
		var caret: int = line_edit_room_code.caret_column
		line_edit_room_code.text = filtered
		line_edit_room_code.caret_column = mini(caret, filtered.length())


func _on_join_succeeded() -> void:
	_cancel_join_watchdog()
	btn_join_room.disabled = true
	_set_status(lbl_join_status, "Connected. Your friend will start the duel.", NeuKit.MINT.darkened(0.34))
	Feel.sfx("correct")
	Feel.haptic("success")


func _on_join_failed() -> void:
	_cancel_join_watchdog()
	if EOSOnline.has_current_lobby():
		await EOSOnline.leave_current_lobby_async()
	_room_transport = &"none"
	btn_join_room.disabled = false
	_set_status(lbl_join_status, "Couldn't connect. Check the code and try again.", NeuKit.CORAL)
	Feel.sfx("wrong")
	Feel.haptic("error")


func _on_server_disconnected() -> void:
	if is_navigating:
		return
	_cancel_join_watchdog()
	if EOSOnline.has_current_lobby():
		await EOSOnline.leave_current_lobby_async()
	_room_transport = &"none"
	btn_join_room.disabled = false
	_set_status(lbl_join_status, "The host closed the room.", NeuKit.CORAL)


func _arm_join_watchdog(timeout_seconds: float) -> void:
	_watchdog_token += 1
	var token: int = _watchdog_token
	get_tree().create_timer(timeout_seconds).timeout.connect(_on_join_watchdog_timeout.bind(token))


func _cancel_join_watchdog() -> void:
	_watchdog_token += 1


func _on_join_watchdog_timeout(token: int) -> void:
	if token != _watchdog_token or is_navigating or not NetworkSession.is_connecting():
		return
	NetworkSession.disconnect_session()
	if EOSOnline.has_current_lobby():
		await EOSOnline.leave_current_lobby_async()
	_room_transport = &"none"
	btn_join_room.disabled = false
	_set_status(lbl_join_status, "No response from that room. Check the code and try again.", NeuKit.CORAL)


func _on_invitation_received(invitation: Dictionary) -> void:
	_handle_invitation(invitation)


func _handle_invitation(invitation: Dictionary) -> void:
	if is_navigating or not is_inside_tree():
		return
	var invitation_type: String = str(invitation.get("type", ""))
	if invitation_type == "online":
		var code: String = str(invitation.get("code", "")).to_upper()
		_set_active_tab(LobbyTab.JOIN)
		line_edit_room_code.text = code
		await _join_online_code(code)
	elif invitation_type == "lan":
		_set_active_tab(LobbyTab.JOIN)
		var ip: String = str(invitation.get("ip", ""))
		var port: int = int(invitation.get("port", GameConfig.DEFAULT_PORT))
		if not LanDiscoveryScript.is_valid_ipv4(ip) or port < 1 or port > 65535:
			_set_status(lbl_join_status, "This older LAN invitation is invalid.", NeuKit.CORAL)
			return
		_start_legacy_lan_join(ip, port)


func _start_legacy_lan_join(ip: String, port: int) -> void:
	_room_transport = &"enet"
	btn_join_room.disabled = true
	_set_status(lbl_join_status, "Connecting to the local room...", NeuKit.SLATE)
	var err: Error = NetworkSession.join_host(ip, port)
	if err != OK:
		btn_join_room.disabled = false
		_room_transport = &"none"
		_set_status(lbl_join_status, "Couldn't start the LAN connection.", NeuKit.CORAL)
		return
	_arm_join_watchdog(10.0)


func _refresh_rival_code() -> void:
	lbl_my_rival_code.text = ChallengeCodes.display_form(Records.my_challenge_code())
	line_edit_rival_code.text = ""
	_set_status(lbl_rival_status, "No internet needed. Both players use the same code to play the same run.", NeuKit.SLATE)


func _on_copy_rival_code_pressed() -> void:
	var code: String = ChallengeCodes.display_form(Records.my_challenge_code())
	DisplayServer.clipboard_set(code)
	btn_copy_rival_code.text = "COPIED!"
	Feel.sfx("correct")
	Feel.haptic("light")
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(btn_copy_rival_code) and btn_copy_rival_code.is_inside_tree():
			btn_copy_rival_code.text = "COPY MY CODE"
	)


func _on_new_rival_code_pressed() -> void:
	Records.reroll_my_challenge_code()
	_refresh_rival_code()
	_set_status(lbl_rival_status, "New code created. Your previous code remains valid for anyone who saved it.", NeuKit.MINT.darkened(0.34))
	Feel.sfx("spot")
	Feel.haptic("medium")


func _on_play_rival_code_pressed() -> void:
	if line_edit_rival_code.text.strip_edges().is_empty():
		_set_status(lbl_rival_status, "Enter your friend's rival code first.", NeuKit.CORAL)
		Feel.sfx("wrong")
		return
	_start_rival_run(line_edit_rival_code.text)


func _on_rival_code_changed(new_text: String) -> void:
	var clean: String = ChallengeCodes.normalize(new_text)
	if clean.length() > ChallengeCodes.CODE_CHARS:
		clean = clean.substr(0, ChallengeCodes.CODE_CHARS)
	var formatted: String = ChallengeCodes.display_form(clean)
	if formatted == new_text:
		return
	var caret: int = line_edit_rival_code.caret_column
	var at_end: bool = caret >= new_text.length()
	line_edit_rival_code.text = formatted
	line_edit_rival_code.caret_column = formatted.length() if at_end else mini(caret, formatted.length())


func _start_rival_run(code: String) -> void:
	if is_navigating:
		return
	if not GameManager.queue_challenge_start(code):
		_set_status(lbl_rival_status, "That code isn't valid. Check the 9 characters and try again.", NeuKit.CORAL)
		Feel.sfx("wrong")
		Feel.haptic("error")
		return
	is_navigating = true
	# Rival Codes are standalone offline runs. If the player switches to this
	# tab while an EOS room is still open, close that session before launching.
	if EOSOnline.has_current_lobby() or NetworkSession.is_connected_to_network() or NetworkSession.is_connecting():
		await _close_current_room()
	SceneRouter.goto_game()


func _on_back_pressed() -> void:
	_leave_lobby()


func _leave_lobby() -> void:
	if is_navigating or _closing_room or SceneRouter.is_transitioning:
		return
	is_navigating = true
	btn_back.disabled = true
	await _close_current_room()
	SceneRouter.goto_main_menu()


func handle_back() -> bool:
	if is_navigating or _closing_room or SceneRouter.is_transitioning:
		return true
	_leave_lobby()
	return true


func _exit_tree() -> void:
	BackNav.unregister(self)
	_cancel_join_watchdog()