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

# Some custom MultiplayerPeer transports can reach CONNECTION_CONNECTED
# without reliably delivering connected_to_server on every platform.
# Emit the public signal once, using the peer state as a guarded fallback.
var _connection_succeeded_emitted: bool = false

func _ready() -> void:
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
		if is_active_host or peer == null or _connection_succeeded_emitted:
				return
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				print("[NET] Client connection confirmed by peer state; emitting connection_succeeded fallback.")
				_emit_connection_succeeded_once()

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
		_connection_succeeded_emitted = false
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

func get_remote_peer_ids() -> Array[int]:
		var result: Array[int] = []
		if peer == null:
				return result
		# EOSG exposes the authoritative peer map. Prefer it on the EOS server
		# instead of depending only on the timing of the Godot peer_connected signal.
		if is_active_host and peer.has_method("get_all_peers"):
				var peer_map: Variant = peer.call("get_all_peers")
				if peer_map is Dictionary:
						for peer_key in peer_map.keys():
								var remote_id: int = int(peer_key)
								if remote_id > 1 and not result.has(remote_id):
										result.append(remote_id)
						result.sort()
						return result
		for peer_id in connected_peers:
				if peer_id > 1 and not result.has(peer_id):
						result.append(peer_id)
		result.sort()
		return result

func is_connected_to_network() -> bool:
		if peer == null:
				return false
		# A server-side EOSG peer is a listener, not a client connection.
		# Its own CONNECTION_CONNECTED status only means the server is listening;
		# get_all_peers() is EOSG's authoritative list of established remote peers.
		if is_active_host and multiplayer.is_server():
				return not get_remote_peer_ids().is_empty()
		return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

## True while a join attempt is still knocking (used by the lobby watchdog to
## give up on unreachable hosts instead of hanging on ENet's long timeout).
func is_connecting() -> bool:
		return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING

func get_local_id() -> int:
		return multiplayer.get_unique_id()

func send_packet(target_id: int, msg_type: String, payload: Dictionary = {}) -> void:
		if peer == null:
				push_warning("[NET] SEND SKIPPED type=%s: multiplayer peer is not active." % msg_type)
				return

		var packet: Dictionary = NetworkProtocol.create_packet(msg_type, payload)

		if is_host():
				var remote_ids: Array[int] = get_remote_peer_ids()
				if remote_ids.is_empty():
						push_warning("[NET] SEND SKIPPED type=%s: host has no connected player." % msg_type)
						return
				if target_id == 0:
						# EOSG server peers broadcast target 0 to every peer in their
						# native peer map; reliable RPC preserves packet ordering.
						_rpc_receive_packet.rpc(packet)
				else:
						if not remote_ids.has(target_id):
								push_warning("[NET] SEND SKIPPED type=%s: peer %d is not connected." % [msg_type, target_id])
								return
						_rpc_receive_packet.rpc_id(target_id, packet)
		else:
				if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
						push_warning("[NET] SEND SKIPPED type=%s: client is not connected (status=%d)." % [
								msg_type, peer.get_connection_status()
						])
						return
				# In EOSG client/server mode the host always owns peer ID 1.
				if target_id != 1 and target_id != 0:
						push_warning("[NET] Client attempted to send to non-server peer %d." % target_id)
						return
				_rpc_receive_packet.rpc_id(1, packet)

		print("[NET] SEND type=%s target=%s ver=%d" % [
				msg_type,
				"ALL" if target_id == 0 else str(target_id),
				NetworkProtocol.PROTOCOL_VERSION
		])

func send_to_server(msg_type: String, payload: Dictionary = {}) -> void:
		if is_host():
				push_warning("[NET] Host cannot send a client-to-server packet.")
				return
		send_packet(1, msg_type, payload)

func send_to_all(msg_type: String, payload: Dictionary = {}) -> void:
		if not is_host():
				push_warning("[NET] Only the host may broadcast authoritative game packets.")
				return
		send_packet(0, msg_type, payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_packet(packet: Dictionary) -> void:
		var sender_id: int = multiplayer.get_remote_sender_id()
		if not NetworkProtocol.is_valid_packet(packet):
				var received_version: Variant = packet.get("ver", "<missing>") if packet is Dictionary else "<not-dictionary>"
				var received_type: Variant = packet.get("type", "<missing>") if packet is Dictionary else "<not-dictionary>"
				push_warning("[NET] REJECT sender=%d type=%s received_ver=%s expected_ver=%d" % [
						sender_id, str(received_type), str(received_version), NetworkProtocol.PROTOCOL_VERSION
				])
				return

		var msg_type: String = packet.get("type", "")
		var payload: Dictionary = packet.get("data", {})
		if msg_type == NetworkProtocol.MSG_MATCH_START:
				print("[NET] RECEIVE type=%s sender=%d ver=%d" % [msg_type, sender_id, NetworkProtocol.PROTOCOL_VERSION])
		packet_received.emit(sender_id, msg_type, payload)

func _emit_connection_succeeded_once() -> void:
		if _connection_succeeded_emitted:
				return
		_connection_succeeded_emitted = true
		connection_succeeded.emit()


func _on_connected_to_server() -> void:
		print("[NET] connected_to_server signal received. local_id=%d status=%d" % [
				multiplayer.get_unique_id(),
				peer.get_connection_status() if peer != null else -1
		])
		_emit_connection_succeeded_once()

func _on_connection_failed() -> void:
		disconnect_session()
		connection_failed.emit()

func _on_peer_connected(peer_id: int) -> void:
		if not peer_id in connected_peers:
				connected_peers.append(peer_id)
		print("[NET] Peer connected id=%d local_id=%d host=%s peers=%s status=%d" % [
				peer_id,
				multiplayer.get_unique_id(),
				multiplayer.is_server(),
				str(connected_peers),
				peer.get_connection_status() if peer != null else -1
		])
		peer_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
		connected_peers.erase(peer_id)
		peer_disconnected.emit(peer_id)

func _on_server_disconnected() -> void:
		disconnect_session()
		server_disconnected.emit()
