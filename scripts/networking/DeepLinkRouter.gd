extends Node

## Handles SpotRush LAN and EOS room invitations on Android and keeps the invite
## available across the boot-screen scene transition.

signal invitation_received(invitation: Dictionary)

const LAN_DISCOVERY_SCRIPT = preload("res://scripts/networking/LanDiscovery.gd")
const LOBBY_SCENE_PATH: String = "res://scenes/multiplayer/LocalLobby.tscn"
const URI_PREFIX: String = "spotrush://join"
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH: int = 8

var _pending_invitation: Dictionary = {}
var _boot_transition_finished: bool = false
var _last_received_uri: String = ""

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        if AppLifecycle.has_signal("app_resumed"):
                AppLifecycle.app_resumed.connect(_read_android_intent)
        if SceneRouter.has_signal("transition_finished"):
                SceneRouter.transition_finished.connect(_on_scene_transition_finished)
        call_deferred("_read_android_intent")

## The invite survives the boot scene and is consumed by LocalLobby exactly once.
func consume_pending_invitation() -> Dictionary:
        var invitation: Dictionary = _pending_invitation.duplicate(true)
        _pending_invitation.clear()
        return invitation

## Public for clipboard paste and tests as well as the Android intent receiver.
func receive_link(uri: String) -> bool:
        if uri == _last_received_uri:
                return false
        var invitation: Dictionary = parse_invitation(uri)
        if invitation.is_empty():
                return false
        _last_received_uri = uri
        _pending_invitation = invitation
        invitation_received.emit(invitation.duplicate(true))
        if _boot_transition_finished:
                call_deferred("_route_to_lobby_if_needed")
        return true

func make_lan_link(ip: String, port: int) -> String:
        if not LAN_DISCOVERY_SCRIPT.is_valid_ipv4(ip) or port < 1 or port > 65535:
                return ""
        return "%s?ip=%s&port=%d" % [URI_PREFIX, ip, port]

func make_room_code_link(room_code: String) -> String:
        var clean_code: String = room_code.strip_edges().to_upper()
        if not _is_valid_room_code(clean_code):
                return ""
        return "%s?code=%s" % [URI_PREFIX, clean_code]

func parse_invitation(uri: String) -> Dictionary:
        var clean_uri: String = uri.strip_edges()
        if not clean_uri.to_lower().begins_with(URI_PREFIX):
                return {}
        var query_start: int = clean_uri.find("?")
        if query_start != URI_PREFIX.length() or query_start >= clean_uri.length() - 1:
                return {}
        if clean_uri.substr(0, query_start).to_lower() != URI_PREFIX:
                return {}

        var query_text: String = clean_uri.substr(query_start + 1)
        var parameters: Dictionary = {}
        for item in query_text.split("&", false):
                var pair: PackedStringArray = item.split("=", false, 1)
                if pair.size() == 2:
                        parameters[pair[0].to_lower()] = pair[1].uri_decode()

        if parameters.has("code"):
                var code: String = str(parameters["code"]).strip_edges().to_upper()
                if _is_valid_room_code(code):
                        return {"type": "online", "code": code}
                return {}

        if parameters.has("ip") and parameters.has("port"):
                var ip: String = str(parameters["ip"]).strip_edges()
                var port_text: String = str(parameters["port"]).strip_edges()
                if not LAN_DISCOVERY_SCRIPT.is_valid_ipv4(ip):
                        return {}
                if not port_text.is_valid_int():
                        return {}
                var port: int = int(port_text)
                if port < 1 or port > 65535:
                        return {}
                return {"type": "lan", "ip": ip, "port": port}
        return {}

func _is_valid_room_code(code: String) -> bool:
        if code.length() != ROOM_CODE_LENGTH:
                return false
        for character in code:
                if not ROOM_CODE_ALPHABET.contains(str(character)):
                        return false
        return true

func _read_android_intent() -> void:
        if OS.get_name() != "Android":
                return
        var android_runtime: Object = Engine.get_singleton("AndroidRuntime")
        if android_runtime == null or not android_runtime.has_method("getActivity"):
                return
        var activity: Object = android_runtime.call("getActivity")
        if activity == null or not activity.has_method("getIntent"):
                return
        var intent: Object = activity.call("getIntent")
        if intent == null or not intent.has_method("getDataString"):
                return
        var invitation_uri: String = str(intent.call("getDataString"))
        if not invitation_uri.is_empty():
                receive_link(invitation_uri)

func _on_scene_transition_finished() -> void:
        _boot_transition_finished = true
        if not _pending_invitation.is_empty():
                call_deferred("_route_to_lobby_if_needed")

func _route_to_lobby_if_needed() -> void:
        if _pending_invitation.is_empty() or SceneRouter.is_transitioning:
                return
        var current_scene: Node = get_tree().current_scene
        if current_scene != null and current_scene.scene_file_path == LOBBY_SCENE_PATH:
                return
        SceneRouter.goto_lobby()
