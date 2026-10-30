extends Control

# Local multiplayer lobby - the guided, game-shaped version.
#
# Everything on this screen speaks player, not protocol: a big "game code" well
# with a copy key, two player chips that light up when the friend arrives, a
# pulsing status line that always says what to do next, and results-screen
# style action keys (lit caption on cobalt, engraved caption on the pad) with
# a guidance line under each title. No ports, no jargon.
#
# v21: joining stopped requiring typing, three ways over. While a room is open
# the host's phone shouts a small beacon onto the Wi-Fi (LanDiscovery), the
# join tab lists the games it hears under NEARBY GAMES, and one tap joins.
# The host screen also shows a QR square (QrCode) encoding the game code:
# the friend scans it with their own camera app, copies the code it shows,
# and taps PASTE on the JOIN tab - no typing, no reading digits out loud.
# The typed game code well stays as the fallback for Wi-Fi networks that
# block device broadcast.
#
# Network behaviour is otherwise unchanged: NetworkSession owns the transport
# and GameManager launches the same 10-round duel. Two robustness upgrades from
# earlier versions remain: the host match start is queued so GameScreen never
# misses the opening countdown, and the join flow carries a 10s watchdog so a
# wrong code can't hang the UI.

const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const LanDiscoveryScript = preload("res://scripts/networking/LanDiscovery.gd")
const QrCodeScript = preload("res://scripts/ui/QrCode.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

const GUIDE_HOST := "[b]HOW TO DUEL[/b]
1. Tap [color=#2B52E2]CREATE ROOM[/color] - your game pops up on your friend's phone.
2. Your friend taps your game in [color=#2B52E2]JOIN[/color], or scans your QR square.
3. When their chip lights up, hit [color=#2B52E2]START THE DUEL![/color]"

const GUIDE_JOIN := "[b]HOW TO JOIN[/b]
1. Ask your friend to [color=#2B52E2]CREATE ROOM[/color] - their game appears above.
2. Tap it - or scan their QR square with your camera, copy the code, then [color=#2B52E2]PASTE[/color].
3. Stay on the same Wi-Fi - the duel starts when the host says go!"

@onready var btn_back: Button = %BtnBack
@onready var btn_tab_host: Button = %BtnTabHost
@onready var btn_tab_join: Button = %BtnTabJoin
@onready var panel_host: Control = %PanelHost
@onready var panel_join: Control = %PanelJoin
@onready var lbl_host_ip: Label = %LblHostIP
@onready var btn_copy_ip: Button = %BtnCopyIP
@onready var wait_dot: Control = %WaitDot
@onready var lbl_host_status: Label = %LblHostStatus
@onready var lbl_chip_p2: Label = %ChipLbl2
@onready var avatar_p2: Control = %AvatarP2
@onready var btn_create_room: Button = %BtnCreateRoom
@onready var btn_launch_match: Button = %BtnLaunchMatch
@onready var line_edit_ip: LineEdit = %LineEditIP
@onready var btn_paste_ip: Button = %BtnPasteIP
@onready var btn_connect: Button = %BtnConnect
@onready var lbl_join_status: Label = %LblJoinStatus
@onready var nearby_list: VBoxContainer = %NearbyList
@onready var nearby_hint: Label = %NearbyHint
@onready var nearby_caption: Label = %NearbyCaption
@onready var guide_text: RichTextLabel = %GuideText

# v21: the QR card (built in code, parked right under the game code well).
var _qr_card: PanelContainer = null
var _qr_rect: TextureRect = null

var is_navigating: bool = false
var _host_mode: bool = true
var _room_open: bool = false
var _local_ips: PackedStringArray = []
var _pulse_tween: Tween = null
var _watchdog_token: int = 0
var discovery = null  # v21: the Lan beacon engine (advertiser + scanner)

# Action-key caption labels (NeuText titles dip with the key press).
var _create_title: NeuText = null
var _create_caption: Label = null
var _launch_title: NeuText = null
var _launch_caption: Label = null
var _connect_title: NeuText = null
var _connect_caption: Label = null

func _ready() -> void:
        SpotRushSkin.apply_screen(self, "lobby")
        BackNav.register(self)
        NeuSafe.fit(get_node_or_null("SafeArea"))
        Music.play_menu()
        _label_action_keys()
        _boost_lobby_readability()
        btn_back.pressed.connect(_on_back_pressed)
        btn_tab_host.pressed.connect(_on_tab_host_pressed)
        btn_tab_join.pressed.connect(_on_tab_join_pressed)
        btn_copy_ip.pressed.connect(_on_copy_ip_pressed)
        btn_paste_ip.pressed.connect(_on_paste_ip_pressed)
        btn_create_room.pressed.connect(_on_create_room_pressed)
        btn_launch_match.pressed.connect(_on_launch_match_pressed)
        btn_connect.pressed.connect(_on_connect_pressed)
        NeuKit.style_line_edit(line_edit_ip, 16.0)
        line_edit_ip.add_theme_color_override("font_placeholder_color", NeuKit.SLATE)
        line_edit_ip.gui_input.connect(_on_ip_gui_input)
        line_edit_ip.text_changed.connect(_on_ip_text_changed)
        # v21: the LAN beacon engine - the host side shouts, the join side listens.
        discovery = LanDiscoveryScript.new()
        add_child(discovery)
        discovery.games_changed.connect(_refresh_nearby_games)
        # v21: the scannable square that carries the game code to a friend's
        # camera app.
        _build_qr_card()

        NetworkSession.connection_succeeded.connect(_on_join_succeeded)
        NetworkSession.connection_failed.connect(_on_join_failed)
        NetworkSession.peer_connected.connect(_on_peer_connected)
        NetworkSession.peer_disconnected.connect(_on_peer_disconnected)
        NetworkSession.server_disconnected.connect(_on_server_disconnected)

        btn_launch_match.disabled = true
        _launch_caption.text = "create your room first"
        _set_key_fade(btn_launch_match, false)
        _display_local_ips()
        _set_chip(lbl_chip_p2, "WAITING...", NeuKit.SLATE)
        _update_tabs()
        _start_pulse()
        _play_entrance()

## Keep the lobby readable on phone screens without changing its layout or
## shrinking text to make the content fit. Important copy stays at 19px or more.
func _boost_lobby_readability() -> void:
        for node in find_children("*", "Label", true, false):
                var label := node as Label
                if label == null:
                        continue
                var current_size := label.get_theme_font_size("font_size")
                if current_size > 0 and current_size <= 16:
                        SpotRushTypography.apply_as(label, SpotRushTypography.Role.MICRO)
                elif current_size > 16 and current_size < 19:
                        SpotRushTypography.apply_as(label, SpotRushTypography.Role.CAPTION)
        SpotRushTypography.apply_as(guide_text, SpotRushTypography.Role.BODY)
        guide_text.add_theme_constant_override("line_separation", 4)
        guide_text.add_theme_color_override("default_color", NeuKit.INK)
        # Keep the back key and title geometrically identical to Settings.
        btn_back.custom_minimum_size = Vector2(100, 56)
        SpotRushTypography.apply_as(btn_back, SpotRushTypography.Role.BUTTON)

## Entrance: the lobby pieces rise in one after another, the same choreography
## as the results screen, so this screen feels like part of the same game.
## Skipped entirely under Reduce Motion.
func _play_entrance() -> void:
        if Feel.reduced():
                return
        var vbox := get_node_or_null("SafeArea/VBoxLobby") as Control
        if vbox == null:
                return
        var items: Array = []
        for node_name in ["HeaderBar", "ModeTabs"]:
                var n := vbox.get_node_or_null(node_name)
                if n != null:
                        items.append(n)
        items.append(panel_host if _host_mode else panel_join)
        items.append(vbox.get_node_or_null("HotspotGuide"))
        for item in items:
                if item is Control:
                        (item as Control).modulate.a = 0.0
        await get_tree().process_frame
        for item in items:
                if item is Control:
                        var c := item as Control
                        c.pivot_offset = c.size * 0.5
                        c.scale = Vector2(0.96, 0.96)
        for i in items.size():
                var c := items[i] as Control
                var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
                tw.tween_property(c, "scale", Vector2.ONE, 0.38).set_delay(0.07 * i)
                tw.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(0.07 * i)

# --- action keys ----------------------------------------------------------------------

## Results-screen style keys: a NeuText title that dips with the press plus a
## small guidance line pinned to the bottom of the key face.
func _label_action_keys() -> void:
        _create_title = _key_title(btn_create_room, "CREATE ROOM", 30, 3, Color.WHITE, NeuKit.COBALT)
        _create_caption = _key_caption(btn_create_room, "open your room on this Wi-Fi", Color(1, 1, 1, 0.90))
        _launch_title = _key_title(btn_launch_match, "START THE DUEL", 30, 3, Color.WHITE, NeuKit.COBALT)
        _launch_caption = _key_caption(btn_launch_match, "create your room first", Color(1, 1, 1, 0.90))
        _connect_title = _key_title(btn_connect, "JOIN THE DUEL", 30, 3, Color.WHITE, NeuKit.COBALT)
        _connect_caption = _key_caption(btn_connect, "same Wi-Fi as the host", Color(1, 1, 1, 0.90))

func _key_title(btn: Button, caption: String, font_size: int, look: int, color: Color, base: Color) -> NeuText:
        btn.text = ""
        var label := NeuText.new()
        label.text = caption
        label.font_size = font_size
        label.color = color
        label.look = look
        label.accent_base = base
        label.tracking = 2.0
        label.set_anchors_preset(Control.PRESET_FULL_RECT)
        label.offset_bottom = -38.0 # reserve a deeper, readable two-line caption area
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(label)
        if btn.has_meta("neu_style"):
                label.bind_style(btn.get_meta("neu_style"))
        return label

func _key_caption(btn: Button, caption: String, color: Color) -> Label:
        var label := Label.new()
        label.text = caption
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.custom_minimum_size.y = 34
        SpotRushTypography.apply_as(label, SpotRushTypography.Role.BODY)
        label.add_theme_color_override("font_color", color)
        label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        label.offset_top = -40.0
        label.offset_bottom = -5.0
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(label)
        return label

## Disabled keys keep their labels but sit back visually.
func _set_key_fade(btn: Button, enabled: bool) -> void:
        for child in btn.get_children():
                if child is CanvasItem:
                        (child as CanvasItem).modulate.a = 1.0 if enabled else 0.72

# --- helpers --------------------------------------------------------------------------

func _neutral_color() -> Color:
        return NeuKit.SLATE

func _ok_color() -> Color:
        return NeuKit.MINT.darkened(0.34)

func _err_color() -> Color:
        return NeuKit.CORAL.darkened(0.12)

func _set_host_status(text: String, color: Color) -> void:
        lbl_host_status.text = text
        lbl_host_status.add_theme_color_override("font_color", color)

func _set_join_status(text: String, color: Color) -> void:
        lbl_join_status.text = text
        lbl_join_status.add_theme_color_override("font_color", color)

func _set_chip(label: Label, text: String, color: Color) -> void:
        label.text = text
        label.add_theme_color_override("font_color", color)

## v21: the strict check moved into LanDiscovery so the clipboard parser,
## the typed-code path and the self-test all share one validator.
func _is_valid_ipv4(ip: String) -> bool:
        return LanDiscoveryScript.is_valid_ipv4(ip)

func _start_pulse() -> void:
        if Feel.reduced():
                return
        _pulse_tween = create_tween().set_loops()
        _pulse_tween.tween_property(wait_dot, "modulate:a", 0.35, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        _pulse_tween.tween_property(wait_dot, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- tabs -----------------------------------------------------------------------------

func _on_tab_host_pressed() -> void:
        if not _host_mode:
                _host_mode = true
                _update_tabs()
                _crossfade(panel_host)
                # Back to hosting: stop listening for games (and never list our
                # own), and re-read the addresses in case Wi-Fi just connected.
                if discovery != null:
                        discovery.stop_scanning()
                _display_local_ips()

func _on_tab_join_pressed() -> void:
        if _host_mode:
                _host_mode = false
                _update_tabs()
                _crossfade(panel_join)
                # v21: start listening for beacons the moment the tab opens.
                if discovery != null:
                        discovery.start_scanning()

func _update_tabs() -> void:
        var tabs: Array[Array] = [[btn_tab_host, true], [btn_tab_join, false]]
        for pair in tabs:
                var button: Button = pair[0]
                var selected: bool = bool(pair[1]) == _host_mode
                NeuKit.set_selected(button, selected)
                var text_color: Color = NeuKit.COBALT if selected else NeuKit.SLATE
                for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
                        button.add_theme_color_override(key, text_color)
        guide_text.text = GUIDE_HOST if _host_mode else GUIDE_JOIN

func _crossfade(panel: Control) -> void:
        panel.modulate.a = 0.0
        var tw := create_tween()
        tw.tween_property(panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# --- host flow ------------------------------------------------------------------------

func _display_local_ips() -> void:
        _local_ips.clear()
        for ip in IP.get_local_addresses():
                # IPv4 only, skip loopback: on phones the hotspot/Wi-Fi address is what matters.
                if not ip.contains(":") and ip != "127.0.0.1":
                        _local_ips.append(ip)
        # v21: rank the addresses - the Wi-Fi/hotspot range first, so the game
        # code shown is never the mobile-data or VPN address by accident.
        _local_ips = LanDiscoveryScript.rank_local_ips(_local_ips)
        if discovery != null:
                discovery.set_own_ips(_local_ips)
        if _local_ips.is_empty():
                lbl_host_ip.text = "No Wi-Fi yet"
                btn_copy_ip.disabled = true
                _set_key_fade(btn_copy_ip, false)
                _hide_host_qr()
        else:
                lbl_host_ip.text = _local_ips[0]
                btn_copy_ip.disabled = false
                _set_key_fade(btn_copy_ip, true)
        # A room that is already open must re-stamp its QR if the address
        # changed (Wi-Fi reconnected while hosting).
        if _room_open:
                _show_host_qr()

func _on_copy_ip_pressed() -> void:
        if _local_ips.is_empty():
                return
        DisplayServer.clipboard_set(_local_ips[0])
        btn_copy_ip.text = "COPIED!"
        Feel.sfx("correct")
        Feel.haptic("light")
        get_tree().create_timer(1.1).timeout.connect(func():
                if is_instance_valid(btn_copy_ip) and btn_copy_ip.is_inside_tree():
                        btn_copy_ip.text = "COPY")

func _on_create_room_pressed() -> void:
        var err := NetworkSession.create_host(GameConfig.DEFAULT_PORT)
        if err == OK:
                _room_open = true
                btn_create_room.disabled = true
                _create_title.text = "ROOM OPEN!"
                _create_caption.text = "your friend's JOIN tab now lists your game"
                _set_key_fade(btn_create_room, false)
                _launch_caption.text = "waiting for your friend..."
                _set_host_status("Room open! Your friend taps your game in their list - or you read the code above.", _ok_color())
                # v21: shout the beacon so the friend's phone finds this room,
                # and stamp the QR square with the current game code.
                if discovery != null:
                        discovery.start_advertising(GameConfig.DEFAULT_PORT)
                _show_host_qr()
                Feel.sfx("correct")
                Feel.haptic("success")
        else:
                _set_host_status("Couldn't open the room. Check your connection and try again.", _err_color())
                Feel.sfx("wrong")

func _on_peer_connected(_peer_id: int) -> void:
        if not NetworkSession.is_host():
                return
        _set_chip(lbl_chip_p2, "FRIEND JOINED!", NeuKit.COBALT)
        avatar_p2.set("glyph_color", NeuKit.COBALT)
        _set_host_status("Your friend is here - START THE DUEL!", _ok_color())
        btn_launch_match.disabled = false
        _set_key_fade(btn_launch_match, true)
        _launch_caption.text = "you're both in - go!"
        _launch_title.accent_base = NeuKit.MINT
        NeuKit.set_accent(btn_launch_match, NeuKit.MINT)
        # Room is full: stop shouting the beacon and tuck the QR away -
        # nobody else needs either.
        if discovery != null:
                discovery.stop_advertising()
        _hide_host_qr()
        Feel.sfx("correct")
        Feel.haptic("success")

func _on_peer_disconnected(_peer_id: int) -> void:
        if not NetworkSession.is_host():
                return
        _set_chip(lbl_chip_p2, "WAITING...", NeuKit.SLATE)
        avatar_p2.set("glyph_color", NeuKit.SLATE)
        _set_host_status("Your friend left - the room is still open.", _neutral_color())
        btn_launch_match.disabled = true
        _set_key_fade(btn_launch_match, false)
        _launch_caption.text = "waiting for your friend..."
        _launch_title.accent_base = NeuKit.COBALT
        NeuKit.set_accent(btn_launch_match, NeuKit.COBALT)
        # The seat is free again - shout the beacon and re-show the QR.
        if _room_open and discovery != null:
                discovery.start_advertising(GameConfig.DEFAULT_PORT)
                _show_host_qr()

func _on_launch_match_pressed() -> void:
        if is_navigating:
                return
        is_navigating = true
        btn_launch_match.disabled = true
        btn_back.disabled = true
        # Queued start: the match (and its broadcast to the friend's phone) begins
        # only after GameScreen is ready, so the opening countdown is never missed.
        GameManager.queue_multiplayer_host_start(10)
        SceneRouter.goto_game()

# --- join flow ------------------------------------------------------------------------

## Typing the game code plays the next note of a tune (one keystroke = one
## note), so continuous typing "plays" Twinkle Twinkle. Backspace scrubs back;
## clearing the field rewinds the melody to its first note.
func _on_ip_gui_input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo:
                var key := event as InputEventKey
                if key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
                        Feel.melody_back()
                elif key.unicode != 0:
                        Feel.melody_pip()

func _on_ip_text_changed(new_text: String) -> void:
        if new_text.is_empty():
                Feel.melody_reset()

## v21: the PASTE key is the end of the QR journey. The friend scans the
## host's square with their camera app, copies the code it shows, taps this -
## and a recognised join code skips the typing well entirely and knocks on
## the host's door straight away. A plain pasted IP keeps the old behaviour.
func _on_paste_ip_pressed() -> void:
        var clip := DisplayServer.clipboard_get()
        var parsed := LanDiscoveryScript.parse_join_code(clip)
        if not parsed.is_empty():
                _set_join_status("Game code recognised - knocking on %s..." % str(parsed["ip"]), _ok_color())
                Feel.sfx("correct")
                Feel.haptic("light")
                _start_join(str(parsed["ip"]), int(parsed["port"]))
                return
        var trimmed := clip.strip_edges()
        if trimmed.is_empty():
                _set_join_status("Nothing copied yet - scan the host's QR square, copy the code, then tap this.", _neutral_color())
                return
        line_edit_ip.text = trimmed.substr(0, 15)
        _set_join_status("Code pasted - hit JOIN THE DUEL when you're ready.", _neutral_color())

func _on_connect_pressed() -> void:
        var ip := line_edit_ip.text.strip_edges()
        if ip.is_empty() or not _is_valid_ipv4(ip):
                _set_join_status("That doesn't look like a game code - check it with your friend.", _err_color())
                Feel.sfx("wrong")
                return
        _start_join(ip, GameConfig.DEFAULT_PORT)

## One door into a duel, used by both paths: a tap on a NEARBY GAMES row (v21)
## or a typed game code. Everything after the tap - watchdog, status line, UI
## locking - is shared, so both paths behave identically.
func _start_join(ip: String, port: int) -> void:
        _set_join_status("Knocking on the host's door...", _neutral_color())
        btn_connect.disabled = true
        _set_key_fade(btn_connect, false)
        _connect_caption.text = "connecting..."
        _arm_join_watchdog()
        var err := NetworkSession.join_host(ip, port)
        if err != OK:
                _cancel_join_watchdog()
                _set_join_status("Couldn't start connecting. Check the code and try again.", _err_color())
                btn_connect.disabled = false
                _set_key_fade(btn_connect, true)
                _connect_caption.text = "same Wi-Fi as the host"

## A wrong code or dead host used to hang "connecting..." until ENet's long
## internal timeout. This watchdog gives up after 10 seconds with a friendly
## message instead, so the player is never stuck.
func _arm_join_watchdog() -> void:
        _watchdog_token += 1
        var token := _watchdog_token
        get_tree().create_timer(10.0).timeout.connect(func():
                if token != _watchdog_token or is_navigating:
                        return
                if NetworkSession.is_connecting():
                        NetworkSession.disconnect_session()
                        _set_join_status("No answer from the room. Make sure both phones are on the same Wi-Fi, then try again.", _err_color())
                        btn_connect.disabled = false
                        _set_key_fade(btn_connect, true)
                        _connect_caption.text = "same Wi-Fi as the host"
                        Feel.sfx("wrong")
                        Feel.haptic("error"))

func _cancel_join_watchdog() -> void:
        _watchdog_token += 1

func _on_join_succeeded() -> void:
        _cancel_join_watchdog()
        # In the door - no need to keep listening for other games.
        if discovery != null:
                discovery.stop_scanning()
        _set_join_status("You're in! Waiting for the host to start the duel...", _ok_color())
        btn_connect.disabled = true
        _set_key_fade(btn_connect, false)
        _connect_title.text = "CONNECTED!"
        _connect_caption.text = "the host starts the duel"

func _on_join_failed() -> void:
        _set_join_status("Couldn't reach the room. Check the code and Wi-Fi, then try again.", _err_color())
        btn_connect.disabled = false
        _set_key_fade(btn_connect, true)
        _connect_caption.text = "same Wi-Fi as the host"
        Feel.sfx("wrong")
        Feel.haptic("error")

func _on_server_disconnected() -> void:
        if is_navigating:
                return
        _cancel_join_watchdog()
        _set_join_status("The host closed the room.", _err_color())
        btn_connect.disabled = false
        _set_key_fade(btn_connect, true)
        _connect_title.text = "JOIN THE DUEL"
        _connect_caption.text = "same Wi-Fi as the host"

# --- nearby games (v21 LAN discovery) -----------------------------------------------

## Rebuilt whenever LanDiscovery reports the set of visible games changed:
## one row per game (up to three), or one calm hint line while looking.
func _refresh_nearby_games() -> void:
        for child in nearby_list.get_children():
                child.free()
        if discovery == null:
                return
        if discovery.bind_failed():
                nearby_hint.text = "This Wi-Fi hides nearby games - type the game code below instead."
                nearby_hint.visible = true
                nearby_caption.text = "NEARBY GAMES"
                return
        if not discovery.is_scanning():
                nearby_hint.visible = false
                return
        var games: Array = discovery.games()
        if games.is_empty():
                nearby_hint.text = "Looking for games on this Wi-Fi... make sure your friend tapped CREATE ROOM."
                nearby_hint.visible = true
                nearby_caption.text = "NEARBY GAMES"
                return
        nearby_hint.visible = false
        var shown := 0
        for game in games:
                if shown >= LanDiscoveryScript.MAX_LISTED_GAMES:
                        break
                nearby_list.add_child(_make_nearby_row(str(game["ip"]), int(game["port"])))
                shown += 1
        if games.size() > shown:
                nearby_caption.text = "NEARBY GAMES (%d)" % games.size()
        else:
                nearby_caption.text = "NEARBY GAMES"

func _make_nearby_row(ip: String, port: int) -> Button:
        var row := Button.new()
        row.custom_minimum_size = Vector2(0, 84)
        row.focus_mode = Control.FOCUS_NONE
        row.text = ip
        SpotRushTypography.apply_as(row, SpotRushTypography.Role.BUTTON_LARGE)
        var caption := Label.new()
        caption.text = "tap to join this game"
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        SpotRushTypography.apply_as(caption, SpotRushTypography.Role.BODY)
        caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.90))
        caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        caption.offset_top = -31.0
        caption.offset_bottom = -5.0
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(caption)
        row.pressed.connect(func():
                Feel.haptic("light")
                _start_join(ip, port))
        return row

# --- navigation -----------------------------------------------------------------------

func _on_back_pressed() -> void:
        _leave_lobby()

func _exit_tree() -> void:
        BackNav.unregister(self)

## Android back / desktop Escape. Leaving with nothing open is just "up"
## navigation; leaving with a room open (or a friend connected) closes it on
## everyone, so that one is asked first (v19).
func handle_back() -> bool:
        if is_navigating or SceneRouter.is_transitioning:
                return true
        if _room_open or NetworkSession.is_connected_to_network():
                NeuDialog.ask("LEAVE THE ROOM?",
                                "Your room closes and your friend will need a new code to join.",
                                "LEAVE", "STAY", _leave_lobby)
                return true
        _leave_lobby()
        return true

## One door out of the lobby: drop the network session (host or joiner) and
## return to the menu.
func _leave_lobby() -> void:
        if is_navigating:
                return
        is_navigating = true
        btn_launch_match.disabled = true
        btn_back.disabled = true
        # Close the beacon shout and the listener with the screen (v21).
        if discovery != null:
                discovery.stop_advertising()
                discovery.stop_scanning()
        _hide_host_qr()
        NetworkSession.disconnect_session()
        SceneRouter.goto_main_menu()

# --- host QR card (v21) ------------------------------------------------------------------

## Builds the scannable square card and parks it under the game code well,
## hidden. Shown exactly while the room is open and a seat is free - the same
## lifecycle as the beacon shout, because they carry the same invitation.
func _build_qr_card() -> void:
        var panel_host := get_node_or_null("SafeArea/VBoxLobby/PanelHost")
        if panel_host == null:
                return
        _qr_card = PanelContainer.new()
        _qr_card.name = "QrCard"
        _qr_card.visible = false
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 8)
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        _qr_card.add_child(col)
        var caption := Label.new()
        caption.text = "FRIEND'S PHONE? SCAN THIS"
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        SpotRushTypography.apply_as(caption, SpotRushTypography.Role.BODY)
        caption.add_theme_color_override("font_color", NeuKit.SLATE)
        col.add_child(caption)
        _qr_rect = TextureRect.new()
        _qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _qr_rect.custom_minimum_size = Vector2(0, 240)
        _qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        col.add_child(_qr_rect)
        var hint := Label.new()
        hint.text = "Point their camera at this square, copy the code it shows,\nthen tap PASTE on their JOIN tab."
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        SpotRushTypography.apply_as(hint, SpotRushTypography.Role.BODY)
        hint.add_theme_color_override("font_color", NeuKit.SLATE)
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        col.add_child(hint)
        panel_host.add_child(_qr_card)
        panel_host.move_child(_qr_card, 1) # right under the game code well

func _show_host_qr() -> void:
        if _qr_card == null or _local_ips.is_empty():
                _hide_host_qr()
                return
        var code := LanDiscoveryScript.encode_join_code(_local_ips[0], GameConfig.DEFAULT_PORT)
        var tex := QrCodeScript.generate_texture(code, 6)
        if tex == null:
                _hide_host_qr()
                return
        _qr_rect.texture = tex
        _qr_card.visible = true

func _hide_host_qr() -> void:
        if _qr_card != null:
                _qr_card.visible = false
