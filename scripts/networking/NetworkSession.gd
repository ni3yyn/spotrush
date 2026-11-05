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

# --- Large-packet fragmentation ---------------------------------------------
# EOS P2P (eos_p2p transport, used for online duel rooms) silently drops any
# single packet above roughly its underlying UDP-ish limit (~1-1.2KB); unlike
# ENet it does NOT fragment/reassemble oversized packets itself. A duel's
# countdown_start/round_start packets carry a full challenge payload (several
# KB once the token field/options/visual_data are variant-encoded) and were
# being queued fine on the sender but never arriving at all on the joining
# device - every other message (match_start, round_end, answer results) is
# small enough to fit in one packet and always got through. Packets at or
# under MAX_SINGLE_PACKET_BYTES still go out as a single RPC exactly as
# before; anything larger is split into MAX_SINGLE_PACKET_BYTES-sized chunks
# here and reassembled on the receiving end before packet_received fires, so
# every message type behaves the same regardless of payload size or transport.
const MAX_SINGLE_PACKET_BYTES: int = 768
var _next_chunk_msg_id: int = 0
# key "<sender_id>:<msg_id>" -> {"chunks": Array[PackedByteArray], "received": int}
var _chunk_reassembly: Dictionary = {}

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
		_chunk_reassembly.clear()
		_next_chunk_msg_id = 0

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
				return
		var packet = NetworkProtocol.create_packet(msg_type, payload)
		var packet_bytes: PackedByteArray = var_to_bytes(packet)
		if packet_bytes.size() <= MAX_SINGLE_PACKET_BYTES:
				CrashLogger.breadcrumb("[DUEL][NET] TX SEND type=%s target=%d bytes=%d single" % [msg_type, target_id, packet_bytes.size()])
				if target_id == 0:
						_rpc_receive_packet.rpc(packet)
				else:
						_rpc_receive_packet.rpc_id(target_id, packet)
				return

		# Oversized packet (e.g. a round_start/countdown_start carrying a full
		# challenge): split into chunks small enough for the transport to actually
		# deliver, and let the receiving side reassemble them below.
		var msg_id: int = _next_chunk_msg_id
		_next_chunk_msg_id += 1
		var chunk_count: int = int(ceil(float(packet_bytes.size()) / float(MAX_SINGLE_PACKET_BYTES)))
		CrashLogger.breadcrumb("[DUEL][NET] TX SEND type=%s target=%d bytes=%d chunked msg_id=%d chunks=%d" % [msg_type, target_id, packet_bytes.size(), msg_id, chunk_count])
		for i in range(chunk_count):
				var start: int = i * MAX_SINGLE_PACKET_BYTES
				var end: int = mini(start + MAX_SINGLE_PACKET_BYTES, packet_bytes.size())
				var chunk: PackedByteArray = packet_bytes.slice(start, end)
				if target_id == 0:
						_rpc_receive_chunk.rpc(msg_id, i, chunk_count, chunk)
				else:
						_rpc_receive_chunk.rpc_id(target_id, msg_id, i, chunk_count, chunk)

func send_to_server(msg_type: String, payload: Dictionary = {}) -> void:
		send_packet(1, msg_type, payload)

func send_to_all(msg_type: String, payload: Dictionary = {}) -> void:
		send_packet(0, msg_type, payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_packet(packet: Dictionary) -> void:
		var sender_id: int = multiplayer.get_remote_sender_id()
		CrashLogger.breadcrumb("[DUEL][NET] RX RECV type=%s sender=%d bytes=%d single" % [str(packet.get("type", "?")), sender_id, var_to_bytes(packet).size()])
		_deliver_packet(sender_id, packet)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_chunk(msg_id: int, chunk_index: int, chunk_count: int, chunk: PackedByteArray) -> void:
		var sender_id: int = multiplayer.get_remote_sender_id()
		if chunk_count <= 0 or chunk_index < 0 or chunk_index >= chunk_count:
				push_warning("Rejected malformed chunk from sender %d (msg %d, %d/%d)" % [sender_id, msg_id, chunk_index, chunk_count])
				return

		var key: String = "%d:%d" % [sender_id, msg_id]
		if not _chunk_reassembly.has(key):
				var chunks: Array = []
				chunks.resize(chunk_count)
				_chunk_reassembly[key] = {"chunks": chunks, "received": 0}
		var entry: Dictionary = _chunk_reassembly[key]
		var chunks: Array = entry["chunks"]
		if chunk_index >= chunks.size():
				push_warning("Rejected out-of-range chunk from sender %d (msg %d, %d/%d)" % [sender_id, msg_id, chunk_index, chunk_count])
				return
		if chunks[chunk_index] == null:
				entry["received"] = int(entry["received"]) + 1
		chunks[chunk_index] = chunk
		CrashLogger.breadcrumb("[DUEL][NET] RX CHUNK sender=%d msg_id=%d chunk=%d/%d bytes=%d received=%d/%d" % [sender_id, msg_id, chunk_index + 1, chunk_count, chunk.size(), int(entry["received"]), chunks.size()])

		if int(entry["received"]) < chunks.size():
				return

		_chunk_reassembly.erase(key)
		var full_bytes := PackedByteArray()
		for part in chunks:
				full_bytes.append_array(part as PackedByteArray)
		var packet: Variant = bytes_to_var(full_bytes)
		if not (packet is Dictionary):
				push_warning("Rejected unparsable reassembled packet from sender %d (msg %d)" % [sender_id, msg_id])
				return
		CrashLogger.breadcrumb("[DUEL][NET] RX REASSEMBLED sender=%d msg_id=%d type=%s bytes=%d chunks=%d" % [sender_id, msg_id, str(packet.get("type", "?")), full_bytes.size(), chunks.size()])
		_deliver_packet(sender_id, packet)

func _deliver_packet(sender_id: int, packet: Dictionary) -> void:
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
		# Drop any chunked message that was still being reassembled from this peer -
		# it can never complete now, and a stale buffer must not confuse a later
		# msg_id from a freshly reconnected peer with the same id.
		for key in _chunk_reassembly.keys().duplicate():
				if str(key).begins_with("%d:" % peer_id):
						_chunk_reassembly.erase(key)
		peer_disconnected.emit(peer_id)

func _on_server_disconnected() -> void:
		disconnect_session()
		server_disconnected.emit()
