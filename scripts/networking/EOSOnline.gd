extends Node

## SpotRush online services for EOSG 2.3.1.
## Initialization is lazy: offline/LAN players never initialize EOS.

signal initialization_completed(success: bool)
signal online_error(message: String)
signal room_status_changed(status: String)

const GAME_ID: String = "spotrush-duel-v1"
const LOBBY_BUCKET: String = "SPOTRUSH_DUEL_V1"
const P2P_SOCKET_ID: String = "SPOTRUSHDUEL"
const PLAYER_DISPLAY_NAME: String = "SpotRush Player"
# EOS Lobby Search currently caps the max-results argument at 200.
const MAX_ROOM_RESULTS: int = 200
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH: int = 8

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        if AppLifecycle.has_signal("app_paused") and not AppLifecycle.app_paused.is_connected(_on_app_paused):
                AppLifecycle.app_paused.connect(_on_app_paused)
        if AppLifecycle.has_signal("app_resumed") and not AppLifecycle.app_resumed.is_connected(_on_app_resumed):
                AppLifecycle.app_resumed.connect(_on_app_resumed)

var last_error: String = ""
var _initialized: bool = false
var _initializing: bool = false
var _platform_ready: bool = false
var _platform_setup_failed: bool = false
var _current_lobby: Variant = null
var _current_room_code: String = ""
var _current_room_name: String = ""

var _h_platform: Node = null
var _h_auth: Node = null
var _h_lobbies: Node = null
var _h_p2p: Node = null
var _eos_runtime: Node = null

func is_initialized() -> bool:
        return _initialized

func has_current_lobby() -> bool:
        return _current_lobby != null and is_instance_valid(_current_lobby)

func get_current_room_code() -> String:
        return _current_room_code

func get_current_room_name() -> String:
        return _current_room_name

func ensure_ready_async() -> bool:
        if _initialized:
                return true
        if _initializing:
                await initialization_completed
                return _initialized

        _initializing = true
        last_error = ""
        var success: bool = await _initialize_async()
        _initialized = success
        _initializing = false
        initialization_completed.emit(success)
        if not success:
                online_error.emit(last_error)
        return success

func _initialize_async() -> bool:
        if not NetworkSession.has_eos_p2p_support():
                last_error = "EOSGMultiplayerPeer is unavailable. Check that EOSG 2.3.1 and the platform binary are installed."
                push_warning(last_error)
                return false

        _h_platform = get_node_or_null("/root/HPlatform")
        if _h_platform != null and _h_platform.has_signal("log_msg"):
                var sdk_log_callback: Callable = Callable(self, "_on_eos_sdk_log")
                if not _h_platform.is_connected("log_msg", sdk_log_callback):
                        _h_platform.connect("log_msg", sdk_log_callback)
        _h_auth = get_node_or_null("/root/HAuth")
        _h_lobbies = get_node_or_null("/root/HLobbies")
        _h_p2p = get_node_or_null("/root/HP2P")
        _eos_runtime = get_node_or_null("/root/EOSGRuntime")
        if _h_platform == null or _h_auth == null or _h_lobbies == null or _h_p2p == null or _eos_runtime == null:
                last_error = "EOSG autoloads are missing. Enable the Epic Online Services Godot plugin and restart the editor."
                push_warning(last_error)
                return false

        var config_script: Script = load("res://scripts/networking/EOSLocalConfig.gd") as Script
        if config_script == null:
                last_error = "EOSLocalConfig.gd is missing. Copy EOSLocalConfig.gd.example and add your locally stored Client Secret."
                return false
        var config: Object = config_script.new()
        var product_id: String = str(config.get("product_id")).strip_edges()
        var sandbox_id: String = str(config.get("sandbox_id")).strip_edges()
        var deployment_id: String = str(config.get("deployment_id")).strip_edges()
        var client_id: String = str(config.get("client_id")).strip_edges()
        var client_secret: String = str(config.get("client_secret")).strip_edges()
        var encryption_key: String = str(config.get("encryption_key")).strip_edges()
        if product_id.is_empty() or sandbox_id.is_empty() or deployment_id.is_empty() or client_id.is_empty():
                last_error = "EOS Product, Sandbox, Deployment, and Client IDs must be set in EOSLocalConfig.gd."
                return false
        if client_secret.is_empty() or client_secret.begins_with("PASTE_"):
                last_error = "EOS Client Secret is missing. Run tools/set_eos_client_secret.ps1 and enter it locally; rotate the previously exposed value before public release."
                return false
        if encryption_key.length() != 64 or not encryption_key.is_valid_hex_number(false):
                last_error = "EOS Encryption Key must contain exactly 64 hexadecimal characters. Set it in EOSLocalConfig.gd."
                return false

        var credentials_script: Script = load("res://addons/epic-online-services-godot/heos/hcredentials.gd") as Script
        if credentials_script == null:
                last_error = "EOSG HCredentials was not found. Check addons/epic-online-services-godot and its version."
                return false
        var credentials: Object = credentials_script.new()
        var eos_product_name: String = "SpotRush"
        # Godot registers application/config/version with an empty default.
        # get_setting(name, default) returns that existing empty value rather
        # than the supplied default, so explicitly fall back for EOS.
        var eos_product_version: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
        if eos_product_version.is_empty():
                eos_product_version = "1.0.0"
        credentials.set("product_name", eos_product_name)
        credentials.set("product_version", eos_product_version)
        print("[EOS] SDK initialize identity: product='%s', version='%s'" % [eos_product_name, eos_product_version])
        credentials.set("product_id", product_id)
        credentials.set("sandbox_id", sandbox_id)
        credentials.set("deployment_id", deployment_id)
        credentials.set("client_id", client_id)
        credentials.set("client_secret", client_secret)
        credentials.set("encryption_key", encryption_key)
        # EOSG passes this 256-bit key to EOS Platform CreateOptions. It is
        # separate from the OTA signing key and must remain stable for this product.

        if _platform_setup_failed:
                last_error = "EOS platform initialization previously failed after SDK setup began. Restart SpotRush after correcting the EOS configuration before retrying."
                return false
        var eos_cache_directory: String = str(_h_platform.get("cache_directory"))
        if not eos_cache_directory.is_empty() and not DirAccess.dir_exists_absolute(eos_cache_directory):
                var cache_error: Error = DirAccess.make_dir_recursive_absolute(eos_cache_directory)
                if cache_error != OK and not DirAccess.dir_exists_absolute(eos_cache_directory):
                        last_error = "SpotRush couldn't create the EOS cache directory (error %d)." % cache_error
                        return false
        if not _platform_ready:
                var setup_result: bool = bool(await _h_platform.call("setup_eos_async", credentials))
                if not setup_result:
                        # EOSG 2.3.1's helper initializes the SDK before creating
                        # the platform. Repeating setup after a partial failure can
                        # hit EOS Result.AlreadyConfigured and cannot recover safely
                        # in the same process. Require an app restart instead.
                        _platform_setup_failed = true
                        var setup_stage: String = str(_h_platform.get("last_setup_stage"))
                        var setup_detail: String = str(_h_platform.get("last_setup_error"))
                        if setup_detail.is_empty():
                                setup_detail = "HPlatform.setup_eos_async() returned false without a diagnostic detail."
                        last_error = "EOS setup failed at '%s': %s" % [setup_stage, setup_detail]
                        push_error(last_error)
                        return false
                _platform_ready = true

        var application_status: EOS.Platform.ApplicationStatus = EOS.Platform.ApplicationStatus.BackgroundSuspended if AppLifecycle.is_background else EOS.Platform.ApplicationStatus.Foreground
        var application_status_result: EOS.Result = EOS.Platform.PlatformInterface.set_application_status(application_status)
        if not EOS.is_success(application_status_result):
                push_warning("EOS application status update failed: %s" % EOS.result_str(application_status_result))
        var network_status_result: EOS.Result = EOS.Platform.PlatformInterface.set_network_status(EOS.Platform.NetworkStatus.Online)
        if not EOS.is_success(network_status_result):
                push_warning("EOS network status update failed: %s" % EOS.result_str(network_status_result))

        # Create a Device ID once per installation. EOSG's login_anonymous_async()
        # deletes and recreates this ID on every call, so it is deliberately not
        # used here: that would rotate the anonymous player identity each launch.
        var device_options: EOS.Connect.CreateDeviceIdOptions = EOS.Connect.CreateDeviceIdOptions.new()
        device_options.device_model = "%s %s" % [OS.get_name(), OS.get_model_name()]
        EOS.Connect.ConnectInterface.create_device_id(device_options)
        var device_result: Dictionary = await IEOS.connect_interface_create_device_id_callback
        var device_result_code: int = int(device_result.get("result_code", EOS.Result.InvalidState))
        if not EOS.is_success(device_result) and device_result_code != EOS.Result.DuplicateNotAllowed:
                last_error = "EOS could not create or access this installation's Device ID: %s." % EOS.result_str(device_result_code)
                return false

        var login_options: EOS.Connect.LoginOptions = _make_device_login_options()
        var login_ok: bool = bool(await _h_auth.call("login_game_services_async", login_options))
        if not login_ok:
                last_error = "Anonymous EOS Connect login failed. Check that the Client Policy permits Connect login and Device ID credentials."
                return false

        # EOSG 2.3.1's first-time CreateUser path can populate HAuth.product_user_id
        # without updating EOSGRuntime.local_product_user_id. The native P2P peer
        # reads the runtime value, so test that exact value and perform one normal
        # login again when the new-account path did not populate it.
        if str(_eos_runtime.get("local_product_user_id")).is_empty():
                var followup_options: EOS.Connect.LoginOptions = _make_device_login_options()
                var followup_ok: bool = bool(await _h_auth.call("login_game_services_async", followup_options))
                if not followup_ok:
                        last_error = "Anonymous login created a player, but the EOSG first-login P2P initialization workaround failed."
                        return false

        var product_user_id: String = str(_h_auth.get("product_user_id"))
        if product_user_id.is_empty():
                last_error = "EOS Connect completed without returning a Product User ID."
                return false
        if str(_eos_runtime.get("local_product_user_id")).is_empty():
                # Defensive fallback after the second login callback.
                _eos_runtime.set("local_product_user_id", product_user_id)

        var relay_result: EOS.Result = _h_p2p.call("set_relay_control", EOS.P2P.RelayControl.AllowRelays)
        if not EOS.is_success(relay_result):
                last_error = "EOS relay fallback could not be enabled. Check P2P permissions in the Client Policy."
                return false

        _h_lobbies.set("max_search_results", MAX_ROOM_RESULTS)
        return true

func _on_eos_sdk_log(message: Variant) -> void:
        # EOSG LogMessage implements _to_string() with category, level, and text.
        # Never print credentials or EOSLocalConfig contents.
        print("[EOS SDK] %s" % str(message))

func _make_device_login_options() -> EOS.Connect.LoginOptions:
        var options: EOS.Connect.LoginOptions = EOS.Connect.LoginOptions.new()
        options.credentials = EOS.Connect.Credentials.new()
        options.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
        options.credentials.token = null
        options.user_login_info = EOS.Connect.UserLoginInfo.new()
        options.user_login_info.display_name = PLAYER_DISPLAY_NAME
        return options

func create_public_room_async() -> Dictionary:
        var ready: bool = await ensure_ready_async()
        if not ready:
                return {"ok": false, "error": last_error}
        if has_current_lobby():
                last_error = "You already have an online room open."
                return {"ok": false, "error": last_error}

        var peer_error: Error = NetworkSession.create_eos_host(P2P_SOCKET_ID)
        if peer_error != OK:
                last_error = "Couldn't start the EOS P2P host (error %d)." % peer_error
                return {"ok": false, "error": last_error}

        var options: EOS.Lobby.CreateLobbyOptions = EOS.Lobby.CreateLobbyOptions.new()
        options.local_user_id = str(_h_auth.get("product_user_id"))
        options.bucket_id = LOBBY_BUCKET
        options.max_lobby_members = 2
        options.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
        options.allow_invites = false
        options.enable_join_by_id = false
        options.presence_enabled = false
        options.disable_host_migration = true
        options.rejoin_after_kick_requires_invite = false

        var created_lobby: Variant = await _h_lobbies.call("create_lobby_async", options)
        if created_lobby == null:
                NetworkSession.disconnect_session()
                last_error = "EOS couldn't publish the room. Check that Lobbies and public lobby creation are allowed by the Client Policy."
                return {"ok": false, "error": last_error}

        _current_lobby = created_lobby
        _current_room_code = _generate_room_code()
        _current_room_name = "SpotRush Duel %s" % _current_room_code
        _current_lobby.call("add_attribute", "sr_game", GAME_ID)
        _current_lobby.call("add_attribute", "sr_name", _current_room_name)
        _current_lobby.call("add_attribute", "sr_code", _current_room_code)
        _current_lobby.call("add_attribute", "sr_status", "open")
        var updated: bool = bool(await _current_lobby.call("update_async"))
        if not updated:
                await leave_current_lobby_async()
                NetworkSession.disconnect_session()
                last_error = "The room was created but its public listing could not be published."
                return {"ok": false, "error": last_error}

        last_error = ""
        room_status_changed.emit("open")
        return {"ok": true, "code": _current_room_code, "name": _current_room_name}

func search_public_rooms_async(query_text: String = "") -> Array[Dictionary]:
        var rooms: Array[Dictionary] = []
        var ready: bool = await ensure_ready_async()
        if not ready:
                return rooms

        var clean_query: String = query_text.strip_edges().to_lower()
        var search_attributes: Array[Dictionary] = [
                {"key": EOS.Lobby.SEARCH_BUCKET_ID, "value": LOBBY_BUCKET, "comparison": EOS.ComparisonOp.Equal},
                {"key": "sr_game", "value": GAME_ID, "comparison": EOS.ComparisonOp.Equal},
                {"key": "sr_status", "value": "open", "comparison": EOS.ComparisonOp.Equal}
        ]

        # Epic's documented string lobby-search operators are Equal, NotEqual,
        # AnyOf and NotAnyOf. Do not use the EOSG enum's generic Contains value
        # here: it is not a supported string operator in the Lobby service.
        # Exact room codes are filtered server-side. Partial code/name searches
        # are filtered locally from the service's maximum 200 open SpotRush rooms.
        var exact_code_query: bool = _is_valid_room_code(clean_query.to_upper())
        if exact_code_query:
                search_attributes.append({
                        "key": "sr_code",
                        "value": clean_query.to_upper(),
                        "comparison": EOS.ComparisonOp.Equal
                })

        var search_result: Variant = await _h_lobbies.call("search_by_attribute_async", search_attributes)
        if search_result == null or not (search_result is Array):
                last_error = "EOS room search failed. Check that Lobbies are enabled for this deployment and Client Policy."
                return rooms

        for lobby in search_result:
                if lobby == null or not is_instance_valid(lobby):
                        continue
                if _get_lobby_attribute(lobby, "sr_game") != GAME_ID:
                        continue
                if _get_lobby_attribute(lobby, "sr_status") != "open":
                        continue

                var room_code: String = _get_lobby_attribute(lobby, "sr_code").to_upper()
                var room_name: String = _get_lobby_attribute(lobby, "sr_name")
                if exact_code_query and room_code != clean_query.to_upper():
                        continue
                if not clean_query.is_empty() and not exact_code_query:
                        var searchable_name: String = room_name.to_lower()
                        var searchable_code: String = room_code.to_lower()
                        if not searchable_name.contains(clean_query) and not searchable_code.contains(clean_query):
                                continue

                var available_slots: int = int(lobby.get("available_slots"))
                if available_slots < 1:
                        continue
                var lobby_id: String = str(lobby.get("lobby_id"))
                if has_current_lobby() and lobby_id == str(_current_lobby.get("lobby_id")):
                        continue

                rooms.append({
                        "lobby": lobby,
                        "lobby_id": lobby_id,
                        "room_name": room_name,
                        "room_code": room_code,
                        "available_slots": available_slots,
                        "max_members": int(lobby.get("max_members"))
                })

        rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
                return str(a.get("room_name", "")).to_lower() < str(b.get("room_name", "")).to_lower()
        )
        last_error = ""
        return rooms

func join_public_lobby_async(lobby: Variant) -> bool:
        var ready: bool = await ensure_ready_async()
        if not ready:
                return false
        if lobby == null or not is_instance_valid(lobby):
                last_error = "This room is no longer available. Refresh the room list."
                return false
        if has_current_lobby():
                await leave_current_lobby_async()

        var joined_lobby: Variant = await _h_lobbies.call("join_async", lobby)
        if joined_lobby == null:
                last_error = "The room could not be joined. It may have filled up or closed."
                return false

        _current_lobby = joined_lobby
        _current_room_code = _get_lobby_attribute(joined_lobby, "sr_code")
        _current_room_name = _get_lobby_attribute(joined_lobby, "sr_name")
        var host_product_user_id: String = str(joined_lobby.get("owner_product_user_id"))
        var peer_error: Error = NetworkSession.join_eos_host(P2P_SOCKET_ID, host_product_user_id)
        if peer_error != OK:
                await leave_current_lobby_async()
                last_error = "Joined the room listing, but the P2P connection could not start (error %d)." % peer_error
                return false

        last_error = ""
        return true

func join_room_code_async(room_code: String) -> bool:
        var clean_code: String = room_code.strip_edges().to_upper()
        if not _is_valid_room_code(clean_code):
                last_error = "Room codes must contain exactly 8 letters or numbers."
                return false
        var rooms: Array[Dictionary] = await search_public_rooms_async(clean_code)
        for room in rooms:
                if str(room.get("room_code", "")) == clean_code:
                        return await join_public_lobby_async(room.get("lobby"))
        last_error = "No open room matches that code. Check it and try again."
        return false

func update_current_room_status_async(status: String) -> bool:
        if not has_current_lobby() or not bool(_current_lobby.call("is_owner")):
                return false
        var clean_status: String = status.strip_edges().to_lower()
        if clean_status not in ["open", "full", "playing"]:
                return false
        _current_lobby.call("add_attribute", "sr_status", clean_status)
        var updated: bool = bool(await _current_lobby.call("update_async"))
        if updated:
                room_status_changed.emit(clean_status)
        return updated

func leave_current_lobby_async() -> bool:
        if not has_current_lobby():
                _current_lobby = null
                _current_room_code = ""
                _current_room_name = ""
                return true

        var lobby_to_leave: Variant = _current_lobby
        var was_owner: bool = bool(lobby_to_leave.call("is_owner"))
        var leave_ok: bool = false
        if was_owner:
                leave_ok = bool(await lobby_to_leave.call("destroy_async"))
        else:
                leave_ok = bool(await lobby_to_leave.call("leave_async"))
        _current_lobby = null
        _current_room_code = ""
        _current_room_name = ""
        return leave_ok

func _get_lobby_attribute(lobby: Variant, key: String) -> String:
        var attribute: Variant = lobby.call("get_attribute", key)
        if attribute is Dictionary:
                return str(attribute.get("value", ""))
        return ""

func _generate_room_code() -> String:
        var rng: RandomNumberGenerator = RandomNumberGenerator.new()
        rng.randomize()
        var code: String = ""
        for _index in range(ROOM_CODE_LENGTH):
                code += ROOM_CODE_ALPHABET[rng.randi_range(0, ROOM_CODE_ALPHABET.length() - 1)]
        return code

func _is_valid_room_code(code: String) -> bool:
        if code.length() != ROOM_CODE_LENGTH:
                return false
        for character in code:
                if not ROOM_CODE_ALPHABET.contains(str(character)):
                        return false
        return true

func _on_app_paused() -> void:
        if not _initialized:
                return
        var result: EOS.Result = EOS.Platform.PlatformInterface.set_application_status(EOS.Platform.ApplicationStatus.BackgroundSuspended)
        if not EOS.is_success(result):
                push_warning("EOS could not enter background-suspended state: %s" % EOS.result_str(result))

func _on_app_resumed() -> void:
        if not _initialized:
                return
        var application_result: EOS.Result = EOS.Platform.PlatformInterface.set_application_status(EOS.Platform.ApplicationStatus.Foreground)
        if not EOS.is_success(application_result):
                push_warning("EOS could not return to foreground state: %s" % EOS.result_str(application_result))
        var network_result: EOS.Result = EOS.Platform.PlatformInterface.set_network_status(EOS.Platform.NetworkStatus.Online)
        if not EOS.is_success(network_result):
                push_warning("EOS network status could not be restored: %s" % EOS.result_str(network_result))
