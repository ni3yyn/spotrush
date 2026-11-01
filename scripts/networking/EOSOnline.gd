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
var _eos_scope_fingerprint: String = "unknown"

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

        _eos_scope_fingerprint = (product_id + "|" + sandbox_id + "|" + deployment_id).sha256_text().substr(0, 12)
        print("[EOS ROOM] EOS scope fingerprint=%s platform=%s" % [_eos_scope_fingerprint, OS.get_name()])

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

        # HLobby.update_async can log and skip an individual AddAttribute error
        # while the final UpdateLobby request still succeeds. Verify the exact
        # public fields from refreshed lobby details before displaying a code.
        var published_code: String = _get_lobby_attribute(_current_lobby, "sr_code").strip_edges().to_upper()
        var published_game: String = _get_lobby_attribute(_current_lobby, "sr_game")
        var published_status: String = _get_lobby_attribute(_current_lobby, "sr_status")
        print("[EOS ROOM] Host publish env=%s bucket=%s game=%s status=%s code_attribute=%s lobby_update=true" % [
                _eos_scope_fingerprint,
                str(_current_lobby.get("bucket_id")),
                published_game,
                published_status,
                published_code
        ])
        if published_code != _current_room_code or published_game != GAME_ID or published_status != "open":
                await leave_current_lobby_async()
                NetworkSession.disconnect_session()
                last_error = "EOS created the room, but did not retain its public room-code attributes. Please try again."
                return {"ok": false, "error": last_error}

        last_error = ""
        room_status_changed.emit("open")
        return {"ok": true, "code": _current_room_code, "name": _current_room_name}

func search_public_rooms_async(query_text: String = "") -> Array[Dictionary]:
        var rooms: Array[Dictionary] = []
        var ready: bool = await ensure_ready_async()
        if not ready:
                return rooms

        var clean_query: String = query_text.strip_edges().to_upper()
        var bucket_results: Variant = null

        print("[EOS ROOM] Search start env=%s bucket=%s query=%s" % [
                _eos_scope_fingerprint,
                LOBBY_BUCKET,
                clean_query if not clean_query.is_empty() else "<all>"
        ])

        # Epic documents a short indexing delay for newly created public rooms.
        # Retry beyond that window before falling back to a broad public search.
        for attempt in range(4):
                bucket_results = await _h_lobbies.call(
                        "search_by_attribute_async",
                        {
                                "key": EOS.Lobby.SEARCH_BUCKET_ID,
                                "value": LOBBY_BUCKET,
                                "comparison": EOS.ComparisonOp.Equal
                        }
                )
                if bucket_results == null or not (bucket_results is Array):
                        last_error = "EOS Lobby search failed. Check Lobby permissions and that both devices use the same EOS deployment."
                        print("[EOS ROOM] Bucket search failed on attempt %d: %s" % [attempt + 1, last_error])
                        return rooms

                print("[EOS ROOM] Bucket search attempt %d returned %d lobby result(s)." % [attempt + 1, bucket_results.size()])
                rooms = _rooms_from_search_results(bucket_results, clean_query, false)
                if not rooms.is_empty():
                        last_error = ""
                        return rooms
                if attempt < 3:
                        await get_tree().create_timer(1.0).timeout

        # Fallback: search all public lobbies in this EOS deployment and match
        # the generated 8-character code. This also distinguishes an empty
        # bucket from a room whose bucket metadata was not indexed as expected.
        var search_options: EOS.Lobby.CreateLobbySearchOptions = EOS.Lobby.CreateLobbySearchOptions.new()
        search_options.max_results = MAX_ROOM_RESULTS
        var search_handle: Variant = _h_lobbies.call("create_search", search_options)
        if search_handle == null:
                last_error = "EOS could not create a public lobby search. Check the EOS Lobby service configuration."
                return rooms

        var all_results: Variant = await _h_lobbies.call("search_async", search_handle)
        if all_results == null or not (all_results is Array):
                last_error = "EOS could not complete the public lobby search. Check that both devices use the same EOS deployment."
                return rooms

        print("[EOS ROOM] Unfiltered public search returned %d lobby result(s)." % all_results.size())
        rooms = _rooms_from_search_results(all_results, clean_query, true)
        if rooms.is_empty():
                last_error = "No open room matches that code. Compare the EOS environment fingerprints in both devices' logs; they must match."
                print("[EOS ROOM] No match env=%s code=%s bucket_results=%d all_results=%d" % [
                        _eos_scope_fingerprint,
                        clean_query,
                        bucket_results.size(),
                        all_results.size()
                ])
        else:
                last_error = ""
                print("[EOS ROOM] Exact room code found through unfiltered fallback.")
        return rooms


func _rooms_from_search_results(search_results: Array, clean_query: String, allow_exact_code_fallback: bool) -> Array[Dictionary]:
        var rooms: Array[Dictionary] = []
        var exact_code_query: bool = _is_valid_room_code(clean_query)

        for lobby in search_results:
                if lobby == null or not is_instance_valid(lobby):
                        continue

                var bucket_id: String = str(lobby.get("bucket_id"))
                var game_id: String = _get_lobby_attribute(lobby, "sr_game")
                var room_status: String = _get_lobby_attribute(lobby, "sr_status").to_lower()
                var room_code: String = _get_lobby_attribute(lobby, "sr_code").strip_edges().to_upper()
                var room_name: String = _get_lobby_attribute(lobby, "sr_name")
                var bucket_matches: bool = bucket_id == LOBBY_BUCKET
                var game_matches: bool = game_id == GAME_ID
                var code_matches: bool = exact_code_query and room_code == clean_query

                # Normally keep discovery within SpotRush's bucket and game ID.
                # In the exact-code fallback, the generated code is also a lookup
                # key, so it can recover a room with stale bucket metadata.
                if not (bucket_matches and game_matches) and not (allow_exact_code_fallback and code_matches):
                        continue
                if exact_code_query and not code_matches:
                        continue
                if not exact_code_query and not clean_query.is_empty():
                        var searchable_name: String = room_name.to_lower()
                        var searchable_code: String = room_code.to_lower()
                        if not searchable_name.contains(clean_query.to_lower()) and not searchable_code.contains(clean_query.to_lower()):
                                continue
                if not room_status.is_empty() and room_status != "open":
                        continue

                var available_slots: int = int(lobby.get("available_slots"))
                if available_slots < 1:
                        continue
                var lobby_id: String = str(lobby.get("lobby_id"))
                if has_current_lobby() and lobby_id == str(_current_lobby.get("lobby_id")):
                        continue

                print("[EOS ROOM] Candidate accepted bucket=%s game=%s status=%s code=%s slots=%d" % [
                        bucket_id, game_id, room_status, room_code, available_slots
                ])
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
        last_error = ""
        var rooms: Array[Dictionary] = await search_public_rooms_async(clean_code)
        if rooms.is_empty():
                if last_error.is_empty():
                        last_error = "No open room matches that code. Check the code and confirm both players are using the same EOS deployment."
                return false
        for room in rooms:
                if str(room.get("room_code", "")) == clean_code:
                        return await join_public_lobby_async(room.get("lobby"))
        last_error = "No open room matches that code. Check the code and confirm both players are using the same EOS deployment."
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
