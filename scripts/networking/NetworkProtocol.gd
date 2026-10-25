class_name NetworkProtocol
extends RefCounted

const PORT: int = 7000
const PROTOCOL_VERSION: int = 1

# Message type constants
const MSG_PLAYER_JOINED: String = "player_joined"
const MSG_PLAYER_READY: String = "player_ready"
const MSG_MATCH_START: String = "match_start"
const MSG_ROUND_START: String = "round_start"
const MSG_SUBMIT_ANSWER: String = "submit_answer"
const MSG_ANSWER_RESULT: String = "answer_result"
const MSG_SCORE_UPDATE: String = "score_update"
const MSG_ROUND_END: String = "round_end"
const MSG_MATCH_END: String = "match_end"
const MSG_REMATCH_REQUEST: String = "rematch_request"
const MSG_PLAYER_DISCONNECTED: String = "player_disconnected"

static func create_packet(msg_type: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"ver": PROTOCOL_VERSION,
		"type": msg_type,
		"time": Time.get_ticks_msec(),
		"data": payload
	}

static func is_valid_packet(packet: Variant) -> bool:
	if not (packet is Dictionary):
		return false
	if not packet.has("ver") or packet["ver"] != PROTOCOL_VERSION:
		return false
	if not packet.has("type") or not (packet["type"] is String):
		return false
	if not packet.has("data") or not (packet["data"] is Dictionary):
		return false
	return true
