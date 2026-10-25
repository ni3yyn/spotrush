extends Control

@onready var btn_back: Button = %BtnBack
@onready var tab_container: TabContainer = %TabContainer

# Host controls
@onready var lbl_host_ip: Label = %LblHostIP
@onready var lbl_host_status: Label = %LblHostStatus
@onready var lbl_peer_count: Label = %LblPeerCount
@onready var btn_start_host: Button = %BtnStartHost
@onready var btn_launch_match: Button = %BtnLaunchMatch

# Join controls
@onready var line_edit_ip: LineEdit = %LineEditIP
@onready var btn_connect: Button = %BtnConnect
@onready var lbl_join_status: Label = %LblJoinStatus

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	btn_start_host.pressed.connect(_on_start_host_pressed)
	btn_launch_match.pressed.connect(_on_launch_match_pressed)
	btn_connect.pressed.connect(_on_connect_pressed)
	
	NetworkSession.connection_succeeded.connect(_on_join_succeeded)
	NetworkSession.connection_failed.connect(_on_join_failed)
	NetworkSession.peer_connected.connect(_on_peer_connected)
	NetworkSession.peer_disconnected.connect(_on_peer_disconnected)
	NetworkSession.server_disconnected.connect(_on_server_disconnected)
	
	_display_local_ips()
	btn_launch_match.disabled = true
	lbl_join_status.text = "Enter Host IP and press Connect"

func _display_local_ips() -> void:
	var ips: Array = []
	for ip in IP.get_local_addresses():
		# Filter out loopback and ipv6 for mobile clarity
		if not ip.contains(":") and ip != "127.0.0.1":
			ips.append(ip)
			
	if ips.is_empty():
		lbl_host_ip.text = "Local IP: 127.0.0.1 (Connect via Wi-Fi/Hotspot)"
	else:
		lbl_host_ip.text = "Host IP: " + " / ".join(ips)

func _on_start_host_pressed() -> void:
	var err = NetworkSession.create_host(GameConfig.DEFAULT_PORT)
	if err == OK:
		lbl_host_status.text = "Server listening on Port %d" % GameConfig.DEFAULT_PORT
		lbl_peer_count.text = "Players Connected: 1 (Host ready)"
		btn_start_host.disabled = true
		btn_launch_match.disabled = false # Allows host to start match once ready
	else:
		lbl_host_status.text = "Failed to start server (Error %d)" % err

func _on_connect_pressed() -> void:
	var ip = line_edit_ip.text.strip_edges()
	if ip.is_empty():
		lbl_join_status.text = "Please enter a valid IP address!"
		return
		
	lbl_join_status.text = "Connecting to %s..." % ip
	btn_connect.disabled = true
	var err = NetworkSession.join_host(ip, GameConfig.DEFAULT_PORT)
	if err != OK:
		lbl_join_status.text = "Connection failed to start (Error %d)" % err
		btn_connect.disabled = false

func _on_peer_connected(peer_id: int) -> void:
	if NetworkSession.is_host():
		lbl_peer_count.text = "Players Connected: 2 (Ready to play!)"
		btn_launch_match.disabled = false
		lbl_host_status.text = "Peer %d connected! You can start the match." % peer_id

func _on_peer_disconnected(peer_id: int) -> void:
	if NetworkSession.is_host():
		lbl_peer_count.text = "Players Connected: 1 (Waiting for Player 2)"
		lbl_host_status.text = "Peer %d disconnected" % peer_id

func _on_join_succeeded() -> void:
	lbl_join_status.text = "Connected! Waiting for Host to start match..."
	btn_connect.disabled = true

func _on_join_failed() -> void:
	lbl_join_status.text = "Connection failed. Verify Hotspot and IP address."
	btn_connect.disabled = false

func _on_server_disconnected() -> void:
	lbl_join_status.text = "Host disconnected."
	btn_connect.disabled = false

func _on_launch_match_pressed() -> void:
	GameManager.start_multiplayer_host_match(10)
	SceneRouter.goto_game()

func _on_back_pressed() -> void:
	NetworkSession.disconnect_session()
	SceneRouter.goto_main_menu()
