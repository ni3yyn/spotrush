extends Node

signal connection_succeeded
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal packet_received(sender_id: int, msg_type: String, payload: Dictionary)

var peer: ENetMultiplayerPeer = null
var is_active_host: bool = false
var connected_peers: Array[int] = []

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_host(port: int = GameConfig.DEFAULT_PORT) -> Error:
	disconnect_session()
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, GameConfig.MAX_PLAYERS)
	if err != OK:
		push_error("Failed to start ENet server on port %d: %d" % [port, err])
		peer = null
		return err
		
	multiplayer.multiplayer_peer = peer
	is_active_host = true
	connected_peers.clear()
	return OK

func join_host(ip: String, port: int = GameConfig.DEFAULT_PORT) -> Error:
	disconnect_session()
	var clean_ip = ip.strip_edges()
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"
		
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(clean_ip, port)
	if err != OK:
		push_error("Failed to create ENet client to %s:%d: %d" % [clean_ip, port, err])
		peer = null
		return err
		
	multiplayer.multiplayer_peer = peer
	is_active_host = false
	connected_peers.clear()
	return OK

func disconnect_session() -> void:
	if peer != null:
		peer.close()
		peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_active_host = false
	connected_peers.clear()

func is_host() -> bool:
	return is_active_host and multiplayer.is_server()

func is_connected_to_network() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func get_local_id() -> int:
	return multiplayer.get_unique_id()

func send_packet(target_id: int, msg_type: String, payload: Dictionary = {}) -> void:
	if not is_connected_to_network():
		return
	var packet = NetworkProtocol.create_packet(msg_type, payload)
	if target_id == 0:
		_rpc_receive_packet.rpc(packet)
	else:
		_rpc_receive_packet.rpc_id(target_id, packet)

func send_to_server(msg_type: String, payload: Dictionary = {}) -> void:
	send_packet(1, msg_type, payload)

func send_to_all(msg_type: String, payload: Dictionary = {}) -> void:
	send_packet(0, msg_type, payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_packet(packet: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not NetworkProtocol.is_valid_packet(packet):
		push_warning("Rejected invalid packet from sender %d" % sender_id)
		return
		
	var msg_type: String = packet.get("type", "")
	var payload: Dictionary = packet.get("data", {})
	packet_received.emit(sender_id, msg_type, payload)

func _on_connected_to_server() -> void:
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	disconnect_session()
	connection_failed.emit()

func _on_peer_connected(peer_id: int) -> void:
	if not peer_id in connected_peers:
		connected_peers.append(peer_id)
	peer_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)

func _on_server_disconnected() -> void:
	disconnect_session()
	server_disconnected.emit()
