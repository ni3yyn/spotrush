extends Node

# CrashLogger (debug aid, v1).
#
# "It crashes suddenly after some time" is the hardest kind of bug to catch
# because by the time you notice, the process is gone and so is any chance to
# grab `adb logcat` live. This autoload starts capturing the moment the app
# launches and keeps capturing even if the engine itself dies:
#
#   1. At boot it spawns `logcat` as a SEPARATE OS process (via
#      OS.create_process, not a thread) that pipes straight to a file. Being
#      a separate process, it is NOT killed when SpotRush's own process dies
#      (segfault, OOM kill, native crash, JNI abort...) - it keeps writing,
#      so the tail of the file usually contains the actual death, not just
#      silence.
#   2. It drops a timestamped "[CRUMB]" breadcrumb every 15s (fps, memory)
#      and on every scene transition, via plain print() - which goes to both
#      Godot's own engine log (see [logging] in project.godot) and to the
#      logcat tail above. That lets you line up "what was happening" with
#      "when it died" even with no stack trace.
#
# RETRIEVING THE LOG after a crash:
#   adb pull /sdcard/Android/data/com.spotrush.game/files/crash_logs
# (that path is OS.get_user_data_dir() on a normal Android install; if the
# device has no external storage it falls back to internal app storage and
# you'll need `adb shell run-as com.spotrush.game` instead - the path printed
# to logcat at boot, tag "godot", always says exactly where it went.)
#
# NO-CABLE RETRIEVAL: Android/data/<package> is private-to-the-app storage -
# since Android 11 (scoped storage), the OS itself refuses every other app,
# including file managers like zFile, access to it, no matter what storage
# permission you grant them. adb can still reach it because it runs as a
# special shell identity, not a normal app.
#
# So this logger ALSO mirrors the same tail live into the public Download
# folder (Download/SpotRushLogs), which an ordinary file manager CAN browse,
# once you've granted the one manual permission that makes a direct write to
# a public folder legal on Android 11+:
#   Android Settings -> Apps -> SpotRush -> Permissions -> "All files access"
#   (or Settings -> Apps -> Special app access -> All files access) -> Allow.
# This needs a one-time manual toggle because MANAGE_EXTERNAL_STORAGE cannot
# be requested through a normal in-app permission dialog. Until it's granted,
# the private copy above still works exactly as before - the public mirror
# just silently fails to write and there's nothing to see in zFile yet.
#
# Call CrashLogger.breadcrumb("...") from anywhere worth noting right before
# a risky spot (network step, round transition, big allocation) to narrow
# down a specific crash further.
#
# THIRD RETRIEVAL ROUTE - paste upload (debug_upload_latest_log): the private
# and public-mirror copies above both still require getting a file OFF the
# phone somehow. This one skips that step entirely - it POSTs the current
# session's log text straight to dpaste.org (a plain-text paste host, no
# account/API key needed) over the network the app already has permission
# for (`internet`, already true in export_presets.cfg), then puts the
# resulting URL on the device clipboard so you can paste it directly into
# Chrome/any browser on the SAME phone, no PC, no cable, no file manager at
# all. Debug-build only (see OS.is_debug_build() guard below), same pattern
# as DailyReminder's debug_fire_test_notification. Sends log contents to a
# third-party site - don't wire this up to a release build or call it on
# anything you wouldn't want to leave the device.

const MAX_KEPT_SESSIONS: int = 6
const HEARTBEAT_INTERVAL_SEC: float = 15.0
const PUBLIC_LOG_DIR_NAME := "SpotRushLogs"
const FALLBACK_DOWNLOADS_PATH := "/storage/emulated/0/Download"
const PASTE_API_URL := "https://dpaste.org/api/"
const PASTE_EXPIRY_DAYS := "7"
const MAX_UPLOAD_CHARS := 200000

var log_dir: String = ""
var logcat_path: String = ""
var public_log_dir: String = ""
var public_logcat_path: String = ""
var _logcat_helper_pid: int = -1
var _heartbeat_timer: Timer
var _upload_http: HTTPRequest = null

## Emitted when a debug_upload_latest_log() call finishes. `ok` is whether it
## succeeded; `message` is the paste URL on success, a short error otherwise.
signal log_upload_completed(ok: bool, message: String)

func _ready() -> void:
	# Outlive scene changes and pausing - a crash can happen anywhere.
	process_mode = Node.PROCESS_MODE_ALWAYS

	log_dir = OS.get_user_data_dir().path_join("crash_logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	_prune_old_sessions(log_dir, "logcat_")

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	logcat_path = log_dir.path_join("logcat_%s.txt" % stamp)

	if OS.get_name() == "Android":
		# Public mirror so the log is reachable from an ordinary file manager
		# (zFile etc.) without adb - see the no-cable note above. Harmless to
		# attempt even without the "All files access" grant: the mkdir/tee in
		# _start_logcat_tail() just no-ops into that one destination.
		var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if downloads.is_empty():
			downloads = FALLBACK_DOWNLOADS_PATH
		public_log_dir = downloads.path_join(PUBLIC_LOG_DIR_NAME)
		public_logcat_path = public_log_dir.path_join("logcat_%s.txt" % stamp)
		if DirAccess.make_dir_recursive_absolute(public_log_dir) == OK:
			_prune_old_sessions(public_log_dir, "logcat_")
		_start_logcat_tail()
	else:
		# Editor / desktop test runs: nothing to tail, but keep the rest of
		# the logger (breadcrumbs, godot.log) working so behavior matches.
		print("[CrashLogger] Platform '%s' - no logcat tail, engine log still active." % OS.get_name())

	breadcrumb("CrashLogger armed. pid=%d build=%s path=%s public_path=%s" % [
		OS.get_process_id(),
		("debug" if OS.is_debug_build() else "release"),
		logcat_path,
		(public_logcat_path if not public_logcat_path.is_empty() else "(n/a)"),
	])

	var scene_router := get_node_or_null("/root/SceneRouter")
	if scene_router:
		scene_router.transition_started.connect(_on_scene_transition_started)

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SEC
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_on_heartbeat)
	add_child(_heartbeat_timer)

	get_tree().root.close_requested.connect(func() -> void: breadcrumb("App close requested."))

func _on_scene_transition_started() -> void:
	var current := get_tree().current_scene
	breadcrumb("Scene transition away from: %s" % (current.scene_file_path if current else "?"))

func _on_heartbeat() -> void:
	var mem_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	breadcrumb("heartbeat fps=%d mem=%.1fMB" % [Engine.get_frames_per_second(), mem_mb])

## Drop a timestamped marker into both the engine log and the logcat tail.
## Safe to call from anywhere, any time - it's just a print().
func breadcrumb(text: String) -> void:
	print("[CRUMB %s] %s" % [Time.get_time_string_from_system(), text])

func _start_logcat_tail() -> void:
	# -c clears the buffer first so this session's file isn't dominated by
	# whatever ran before this launch. -v threadtime gives timestamps + tid,
	# which matters for lining a death up against the breadcrumbs above.
	# --pid scopes it to us; unprivileged apps generally can't see other
	# processes' lines anyway (Android log UID isolation since API 16), this
	# just keeps the file from looking empty before that kicks in, and still
	# catches this process' own fatal-signal line from the system logger,
	# which is tagged under our own output.
	#
	# `tee` fans the same live tail out to the private path AND the public
	# Download mirror in one pass, so both stay in sync even through a native
	# crash (tee is the separate OS process surviving our death, same as
	# logcat itself). If the public path can't be opened (no "All files
	# access" grant yet, or public_logcat_path is empty on non-Android-style
	# storage), tee just prints one warning to its own stderr and keeps
	# writing the private copy fine - never fatal to this helper process.
	var pid := OS.get_process_id()
	var targets := "'%s'" % logcat_path
	if not public_logcat_path.is_empty():
		targets += " '%s'" % public_logcat_path
	var cmd := "logcat -c; exec logcat -v threadtime --pid=%d 2>&1 | tee %s > /dev/null" % [pid, targets]
	_logcat_helper_pid = OS.create_process("/system/bin/sh", PackedStringArray(["-c", cmd]), false)
	if _logcat_helper_pid <= 0:
		push_error("[CrashLogger] Failed to start logcat tail helper process.")
	else:
		print("[CrashLogger] Logcat tail running (helper pid %d) -> %s%s" % [
			_logcat_helper_pid,
			logcat_path,
			(" (+ %s)" % public_logcat_path if not public_logcat_path.is_empty() else ""),
		])

func _prune_old_sessions(dir_path: String, prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with(prefix):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() >= MAX_KEPT_SESSIONS:
		var oldest: String = files.pop_front()
		dir.remove(oldest)

## DEBUG ONLY - reads the current session's own logcat tail and POSTs it to
## dpaste.org, then puts the returned URL on the clipboard so it can be
## pasted into a browser on the same device. Refuses outright on a release
## build, same policy as DailyReminder.debug_fire_test_notification().
func debug_upload_latest_log() -> void:
	if not OS.is_debug_build():
		push_warning("[CrashLogger] debug_upload_latest_log ignored in a release build.")
		log_upload_completed.emit(false, "Disabled in release builds.")
		return
	if logcat_path.is_empty() or not FileAccess.file_exists(logcat_path):
		push_warning("[CrashLogger] No log file to upload yet (logcat_path=%s)." % logcat_path)
		log_upload_completed.emit(false, "No log file yet.")
		return
	var file := FileAccess.open(logcat_path, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		push_warning("[CrashLogger] Could not open log for upload, error %d." % err)
		log_upload_completed.emit(false, "Could not open log file (error %d)." % err)
		return
	var content := file.get_as_text()
	file.close()
	if content.is_empty():
		log_upload_completed.emit(false, "Log file is empty so far.")
		return
	# Keep the tail - a crash's cause is almost always near the end, and a
	# multi-hour session can otherwise exceed what the paste host accepts.
	if content.length() > MAX_UPLOAD_CHARS:
		content = "...[truncated, showing last %d chars]...\n" % MAX_UPLOAD_CHARS \
				+ content.substr(content.length() - MAX_UPLOAD_CHARS)

	if _upload_http == null:
		_upload_http = HTTPRequest.new()
		add_child(_upload_http)
		_upload_http.request_completed.connect(_on_upload_completed)

	var body := "content=%s&syntax=text&expiry_days=%s" % [content.uri_encode(), PASTE_EXPIRY_DAYS]
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var err := _upload_http.request(PASTE_API_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("[CrashLogger] Upload request failed to start, error %d." % err)
		log_upload_completed.emit(false, "Could not start upload (error %d)." % err)
	else:
		breadcrumb("Uploading crash log (%d chars) to dpaste.org..." % content.length())

func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var msg := "Upload failed (result=%d, http=%d)." % [result, response_code]
		push_warning("[CrashLogger] %s" % msg)
		log_upload_completed.emit(false, msg)
		return
	var url := body.get_string_from_utf8().strip_edges()
	if url.is_empty() or not url.begins_with("http"):
		var msg := "Upload host returned an unexpected response."
		push_warning("[CrashLogger] %s Body: %s" % [msg, body.get_string_from_utf8()])
		log_upload_completed.emit(false, msg)
		return
	DisplayServer.clipboard_set(url)
	breadcrumb("Crash log uploaded and copied to clipboard: %s" % url)
	log_upload_completed.emit(true, url)
