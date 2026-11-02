extends Node

signal connection_succeeded
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal packet_received(sender_id: int, msg_type: String, payload: Dictionary)

## Kept generic so ENet and EOSG can share the same MultiplayerAPI/RPC layer.
var peer: MultiplayerPeer = null
var is_active_host: bool = false
var connected_peers: Array[int] = []
var transport_kind: StringName = &"none"

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
		_tune_transport(peer)

		multiplayer.multiplayer_peer = peer
		is_active_host = true
		transport_kind = &"enet"
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
		_tune_transport(peer)

		multiplayer.multiplayer_peer = peer
		is_active_host = false
		transport_kind = &"enet"
		connected_peers.clear()
		return OK

## Creates an EOSG P2P host without changing the RPC/gameplay layer.
## EOSG must be installed and enabled before this method can succeed.
func create_eos_host(socket_id: String = "SPOTRUSHDUEL") -> Error:
		disconnect_session()
		if not ClassDB.class_exists("EOSGMultiplayerPeer"):
				push_warning("EOSGMultiplayerPeer is unavailable. Install and enable EOSG 2.3.1 first.")
				return ERR_UNAVAILABLE
		if not ClassDB.can_instantiate("EOSGMultiplayerPeer"):
				push_error("EOSGMultiplayerPeer is registered but cannot be instantiated.")
				return ERR_CANT_CREATE

		var candidate: Object = ClassDB.instantiate("EOSGMultiplayerPeer")
		if candidate == null or not candidate is MultiplayerPeer:
				push_error("EOSGMultiplayerPeer did not create a Godot MultiplayerPeer.")
				return ERR_CANT_CREATE
		if not candidate.has_method("create_server"):
				push_error("Installed EOSG peer does not expose create_server().")
				return ERR_METHOD_NOT_FOUND

		var create_result: Variant = candidate.call("create_server", socket_id)
		var err: Error = create_result
		if err != OK:
				push_error("EOS P2P host creation failed: %d" % err)
				return err

		peer = candidate as MultiplayerPeer
		multiplayer.multiplayer_peer = peer
		is_active_host = true
		transport_kind = &"eos_p2p"
		connected_peers.clear()
		return OK

## Connects to the EOS Product User ID obtained from the joined public lobby.
## Lobby discovery/authentication must complete before this method is called.
func join_eos_host(socket_id: String, host_product_user_id: String) -> Error:
		disconnect_session()
		var clean_socket_id: String = socket_id.strip_edges()
		var clean_host_id: String = host_product_user_id.strip_edges()
		if clean_socket_id.is_empty() or clean_host_id.is_empty():
				push_warning("EOS P2P join requires a socket ID and host Product User ID.")
				return ERR_INVALID_PARAMETER
		if not ClassDB.class_exists("EOSGMultiplayerPeer"):
				push_warning("EOSGMultiplayerPeer is unavailable. Install and enable EOSG 2.3.1 first.")
				return ERR_UNAVAILABLE
		if not ClassDB.can_instantiate("EOSGMultiplayerPeer"):
				push_error("EOSGMultiplayerPeer is registered but cannot be instantiated.")
				return ERR_CANT_CREATE

		var candidate: Object = ClassDB.instantiate("EOSGMultiplayerPeer")
		if candidate == null or not candidate is MultiplayerPeer:
				push_error("EOSGMultiplayerPeer did not create a Godot MultiplayerPeer.")
				return ERR_CANT_CREATE
		if not candidate.has_method("create_client"):
				push_error("Installed EOSG peer does not expose create_client().")
				return ERR_METHOD_NOT_FOUND

		var create_result: Variant = candidate.call("create_client", clean_socket_id, clean_host_id)
		var err: Error = create_result
		if err != OK:
				push_error("EOS P2P client creation failed: %d" % err)
				return err

		peer = candidate as MultiplayerPeer
		multiplayer.multiplayer_peer = peer
		is_active_host = false
		transport_kind = &"eos_p2p"
		connected_peers.clear()
		return OK

func has_eos_p2p_support() -> bool:
		return ClassDB.class_exists("EOSGMultiplayerPeer") and ClassDB.can_instantiate("EOSGMultiplayerPeer")

## Transport tuning applied right after the ENet host/client is created, before
## any peer connects. Range-coder compression shrinks every packet (challenge
## payloads, score syncs, round starts) which matters on congested phone
## hotspots: faster round starts, snappier answer round-trips, no behaviour
## change for the 2-player duel.
func _tune_transport(new_peer: MultiplayerPeer) -> void:
		# EOSG owns its packet framing and transport. Keep the existing range-
		# coder tuning strictly on ENet so no ENet-only API touches an EOS peer.
		if not new_peer is ENetMultiplayerPeer:
				return
		var enet_peer: ENetMultiplayerPeer = new_peer as ENetMultiplayerPeer
		var host_conn: ENetConnection = enet_peer.get_host()
		if host_conn != null:
				host_conn.compress(ENetConnection.COMPRESS_RANGE_CODER)

func disconnect_session() -> void:
		if peer != null:
				peer.close()
				peer = null
		if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer = null
		is_active_host = false
		transport_kind = &"none"
		connected_peers.clear()

func is_host() -> bool:
		return is_active_host and multiplayer.is_server()

func is_connected_to_network() -> bool:
		return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

## True while a join attempt is still knocking (used by the lobby watchdog to
## give up on unreachable hosts instead of hanging on ENet's long timeout).
func is_connecting() -> bool:
		return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING

func get_local_id() -> int:
		return multiplayer.get_unique_id()

func send_packet(target_id: int, msg_type: String, payload: Dictionary = {}) -> void:
		if not is_connected_to_network():
				if _is_duel_message(msg_type):
					_duel_trace("TX BLOCKED type=%s target=%d transport=%s active=%s peer=%s status=%s" % [
						msg_type, target_id, str(transport_kind), str(is_active_host),
						str(peer != null), str(peer.get_connection_status() if peer != null else -1)
					])
				return
		var packet = NetworkProtocol.create_packet(msg_type, payload)
		if target_id == 0:
				_rpc_receive_packet.rpc(packet)
		else:
				_rpc_receive_packet.rpc_id(target_id, packet)
		if _is_duel_message(msg_type):
				_duel_trace("TX QUEUED type=%s target=%d local=%d transport=%s bytes=%d %s" % [
					msg_type, target_id, get_local_id(), str(transport_kind),
					JSON.stringify(packet).to_utf8_buffer().size(), _duel_payload_summary(msg_type, payload)
				])

func _is_duel_message(msg_type: String) -> bool:
		return msg_type in [
				NetworkProtocol.MSG_MATCH_START,
				NetworkProtocol.MSG_COUNTDOWN_START,
				NetworkProtocol.MSG_ROUND_START,
				NetworkProtocol.MSG_ROUND_END,
				NetworkProtocol.MSG_MATCH_END
		]

func _duel_payload_summary(msg_type: String, payload: Dictionary) -> String:
		if msg_type == NetworkProtocol.MSG_MATCH_START:
				return "rounds=%s players=%s" % [str(payload.get("total_rounds", "?")), str(payload.get("player_ids", []))]
		if msg_type in [NetworkProtocol.MSG_COUNTDOWN_START, NetworkProtocol.MSG_ROUND_START]:
				var challenge: Variant = payload.get("challenge", {})
				var challenge_dict: Dictionary = {}
				if challenge is Dictionary:
						challenge_dict = challenge
				var raw_json: String = str(payload.get("challenge_json", ""))
				return "round=%s/%s duration=%s instruction_chars=%d challenge_id=%s type=%s keys=%s json_bytes=%d" % [
					str(payload.get("round_num", "?")), str(payload.get("total_rounds", "?")),
					str(payload.get("duration", "?")), str(payload.get("instruction", "")).length(),
					str(challenge_dict.get("id", "")), str(challenge_dict.get("type", "")),
					str(challenge_dict.keys()), raw_json.to_utf8_buffer().size()
				]
		return "keys=%s" % str(payload.keys())

func _duel_trace(message: String) -> void:
		var line := "[DUEL][NET] " + message
		var logger := get_node_or_null("/root/CrashLogger")
		if logger != null and logger.has_method("breadcrumb"):
				logger.call("breadcrumb", line)
		else:
				print(line)

func send_to_server(msg_type: String, payload: Dictionary = {}) -> void:
		send_packet(1, msg_type, payload)

func send_to_all(msg_type: String, payload: Dictionary = {}) -> void:
		send_packet(0, msg_type, payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_packet(packet: Dictionary) -> void:
		var sender_id: int = multiplayer.get_remote_sender_id()
		if not NetworkProtocol.is_valid_packet(packet):
				if packet is Dictionary and _is_duel_message(str(packet.get("type", ""))):
					_duel_trace("RX REJECTED sender=%d local=%d transport=%s invalid_packet=%s" % [sender_id, get_local_id(), str(transport_kind), str(packet)])
				push_warning("Rejected invalid packet from sender %d" % sender_id)
				return
				
		var msg_type: String = packet.get("type", "")
		var payload: Dictionary = packet.get("data", {})
		if _is_duel_message(msg_type):
				_duel_trace("RX RECEIVED sender=%d local=%d transport=%s type=%s packet_bytes=%d %s" % [
					sender_id, get_local_id(), str(transport_kind), msg_type,
					JSON.stringify(packet).to_utf8_buffer().size(), _duel_payload_summary(msg_type, payload)
				])
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
