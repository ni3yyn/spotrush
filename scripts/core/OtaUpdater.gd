extends Node

# Over-the-air content/script updater (v1).
#
# Godot has no "eas update"-style hosted service built in - this is the DIY
# version of the mechanism the engine DOES support: a .pck built from the
# project, downloaded at runtime, and hot-mounted over the base game via
# ProjectSettings.load_resource_pack(). The "send" half (building + hosting
# the .pck you point this at) is scripts/dev/publish_ota.sh - see its header
# for the full explanation, there is no special upload command, you host the
# file anywhere that serves static files over HTTPS.
#
# WHAT THIS CAN AND CAN'T FIX REMOTELY:
#   Can:    GDScript logic, scenes, balance/data resources, art, audio,
#           translations - anything that ships inside res://.
#   Cannot: the engine binary itself, or native Android code/.aar/.so -
#           those only change with a new APK through the store.
#
# IMPORTANT - Godot caches loaded resources by path (ResourceLoader). Mounting
# a patch pack makes the NEW files visible for anything not already loaded
# this session, but anything already instanced (every autoload singleton -
# GameManager, SceneRouter, this script itself - plus any scene already on
# screen) keeps running the OLD code already in memory until the app fully
# restarts. There is no reliable in-place "hot swap everything" in Godot, so
# this does NOT try to silently reload the scene tree and pretend the patch
# is fully live - it asks the player to restart, which is the only
# correctly-guaranteed way to apply it.
#
# SAFETY:
#   - Only ever call check_for_update() from the main menu, never mid-match.
#   - Verifies the SHA-256 the manifest declares before touching anything;
#     a mismatch discards the download and changes nothing.
#   - Any failure (no network, bad manifest, bad checksum, bad pack) just
#     leaves the base game running untouched and emits update_failed - never
#     throws, never blocks startup.

signal update_available(version: String)
signal update_applied(version: String)
signal update_failed(reason: String)

## Fill this in before shipping - with scripts/dev/publish_ota.sh publishing
## to a GitHub Release, it's:
##   "https://github.com/<owner>/<repo>/releases/latest/download/manifest.json"
## That URL never changes between versions (GitHub always redirects
## "latest/download/<name>" to the newest release's matching asset) - only
## set this once. Repo must be PUBLIC: release assets have no auth, and
## there's no safe way to embed a GitHub token in an APK for a private one.
## Left empty, check_for_update() is a silent no-op.
const MANIFEST_URL: String = "https://github.com/ni3yyn/spotrush/releases/latest/download/manifest.json"

const STATE_PATH: String = "user://ota_state.json"
const DOWNLOAD_DIR: String = "user://ota_downloads"

var current_version: String = "0"
var _pending_manifest: Dictionary = {}
var _state: Dictionary = {}

func _init() -> void:
	# Must happen in _init(), and this autoload must be FIRST in the list
	# (see project.godot) - every other autoload's script is compiled the
	# moment the engine reaches it in the list, so the patch pack has to be
	# mounted before any of them load, not merely before this node's own
	# _ready(). _ready() is already too late.
	_load_state()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOWNLOAD_DIR))
	_remount_applied_pack()

func _ready() -> void:
	pass

## Re-mounts the patch pack that a previous session already downloaded and
## verified, so the code it contains is actually what the OTHER autoloads
## load on this boot. Without this, download_and_apply() only ever affects
## the process that downloaded it - the very next launch (the one the
## "RESTART" button triggers) would otherwise boot straight back to the
## base APK's code with no sign anything is wrong.
func _remount_applied_pack() -> void:
	if current_version == "0":
		return # nothing has ever been applied
	var expected_sha: String = str(_state.get("sha256", ""))
	var dest: String = str(_state.get("pck_path", ""))
	if dest.is_empty() or not FileAccess.file_exists(dest):
		push_warning("[OtaUpdater] state says v%s is applied but its pack is missing - staying on base build" % current_version)
		return
	if expected_sha.is_empty() or FileAccess.get_sha256(dest) != expected_sha:
		push_warning("[OtaUpdater] applied pack for v%s failed re-verification - staying on base build" % current_version)
		return
	if not ProjectSettings.load_resource_pack(dest, true):
		push_warning("[OtaUpdater] failed to remount pack for v%s - staying on base build" % current_version)

## CrashLogger is declared AFTER this autoload (it has to stay that way - see
## the _init()/project.godot note above for why OtaUpdater has to go first),
## so it can't be referenced by its global identifier from here: GDScript
## resolves autoload identifiers in list order, and a script earlier in the
## list can't see one declared later. get_node_or_null() against the live
## tree sidesteps that entirely - by the time these calls actually run
## (check_for_update()/download_and_apply(), both only ever called from the
## main menu, long after every autoload is up), CrashLogger is there.
func _log(text: String) -> void:
	var logger := get_node_or_null("/root/CrashLogger")
	if logger != null:
		logger.breadcrumb(text)
	else:
		print("[OtaUpdater] %s" % text)

## Fetches the manifest and emits update_available if it names a version
## different from the one already applied. Safe to call repeatedly; quietly
## does nothing with no MANIFEST_URL or no network.
func check_for_update() -> void:
	if MANIFEST_URL.is_empty():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_manifest_response.bind(http), CONNECT_ONE_SHOT)
	var err := http.request(MANIFEST_URL)
	if err != OK:
		update_failed.emit("manifest request failed to start (%d)" % err)
		http.queue_free()

func _on_manifest_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_failed.emit("manifest fetch failed (result=%d code=%d)" % [result, code])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("version") or not parsed.has("pck_url") or not parsed.has("sha256"):
		update_failed.emit("manifest malformed")
		return
	_pending_manifest = parsed
	var remote_version := str(parsed["version"])
	if remote_version != current_version:
		_log("OTA update available: %s -> %s" % [current_version, remote_version])
		update_available.emit(remote_version)

## Downloads the pending manifest's pack, verifies it, and mounts it. Emits
## update_applied(version) on success (still needs a restart to fully take -
## see header) or update_failed(reason) leaving everything untouched.
func download_and_apply() -> void:
	if _pending_manifest.is_empty():
		update_failed.emit("no pending manifest - call check_for_update() first")
		return
	var http := HTTPRequest.new()
	add_child(http)
	var dest: String = DOWNLOAD_DIR.path_join("update_%s.pck" % str(_pending_manifest["version"]))
	http.download_file = dest
	http.request_completed.connect(_on_download_response.bind(http, dest), CONNECT_ONE_SHOT)
	var err := http.request(str(_pending_manifest["pck_url"]))
	if err != OK:
		update_failed.emit("download failed to start (%d)" % err)
		http.queue_free()

func _on_download_response(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, dest: String) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_failed.emit("download failed (result=%d code=%d)" % [result, code])
		return

	var expected_sha: String = str(_pending_manifest.get("sha256", "")).to_lower()
	var actual_sha: String = FileAccess.get_sha256(dest)
	if expected_sha.is_empty() or actual_sha != expected_sha:
		update_failed.emit("checksum mismatch - discarding download")
		DirAccess.remove_absolute(dest)
		return

	if not ProjectSettings.load_resource_pack(dest, true):
		update_failed.emit("load_resource_pack failed for %s" % dest)
		return

	current_version = str(_pending_manifest["version"])
	_save_state(dest, actual_sha)
	_log("OTA update applied: now on %s (restart needed to fully take)" % current_version)
	update_applied.emit(current_version)

func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("version"):
		_state = parsed
		current_version = str(parsed["version"])

func _save_state(pck_path: String, sha256: String) -> void:
	_state = {"version": current_version, "pck_path": pck_path, "sha256": sha256}
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(_state))