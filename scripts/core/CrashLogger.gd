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
# RETRIEVING THE LOG after a crash (no root needed):
#   adb pull /sdcard/Android/data/com.spotrush.game/files/crash_logs
# (that path is OS.get_user_data_dir() on a normal Android install; if the
# device has no external storage it falls back to internal app storage and
# you'll need `adb shell run-as com.spotrush.game` instead - the path printed
# to logcat at boot, tag "godot", always says exactly where it went.)
#
# Call CrashLogger.breadcrumb("...") from anywhere worth noting right before
# a risky spot (network step, round transition, big allocation) to narrow
# down a specific crash further.

const MAX_KEPT_SESSIONS: int = 6
const HEARTBEAT_INTERVAL_SEC: float = 15.0

var log_dir: String = ""
var logcat_path: String = ""
var _logcat_helper_pid: int = -1
var _heartbeat_timer: Timer

func _ready() -> void:
	# Outlive scene changes and pausing - a crash can happen anywhere.
	process_mode = Node.PROCESS_MODE_ALWAYS

	log_dir = OS.get_user_data_dir().path_join("crash_logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	_prune_old_sessions()

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	logcat_path = log_dir.path_join("logcat_%s.txt" % stamp)

	if OS.get_name() == "Android":
		_start_logcat_tail()
	else:
		# Editor / desktop test runs: nothing to tail, but keep the rest of
		# the logger (breadcrumbs, godot.log) working so behavior matches.
		print("[CrashLogger] Platform '%s' - no logcat tail, engine log still active." % OS.get_name())

	breadcrumb("CrashLogger armed. pid=%d build=%s path=%s" % [
		OS.get_process_id(),
		("debug" if OS.is_debug_build() else "release"),
		logcat_path,
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
	var pid := OS.get_process_id()
	var cmd := "logcat -c; exec logcat -v threadtime --pid=%d > '%s' 2>&1" % [pid, logcat_path]
	_logcat_helper_pid = OS.create_process("/system/bin/sh", PackedStringArray(["-c", cmd]), false)
	if _logcat_helper_pid <= 0:
		push_error("[CrashLogger] Failed to start logcat tail helper process.")
	else:
		print("[CrashLogger] Logcat tail running (helper pid %d) -> %s" % [_logcat_helper_pid, logcat_path])

func _prune_old_sessions() -> void:
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return
	var files: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("logcat_"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() >= MAX_KEPT_SESSIONS:
		var oldest: String = files.pop_front()
		dir.remove(oldest)
