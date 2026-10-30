extends Node

# CrashLogger (debug aid, v2).
#
# "It crashes suddenly after some time" is the hardest kind of bug to catch
# because by the time you notice, the process is gone and so is any chance to
# grab `adb logcat` live. This autoload starts capturing the moment the app
# launches and is built so that as much of the trail as possible survives
# even when the engine itself dies mid-line:
#
#   1. At boot it spawns `logcat` as a SEPARATE OS process (via
#      OS.create_process, not a thread), detached into its own session with
#      `setsid` and piped straight to a file. Being a separate SESSION (not
#      just a separate process) matters: Android's crash/ANR/force-stop path
#      calls killProcessGroup() on the whole pgid of a dying app, which WOULD
#      take down a plain child process too - setsid moves the tail out of
#      that group so a native crash (segfault, OOM kill, JNI abort...) does
#      not take the logger down with it. A watchdog timer also checks the
#      helper is still alive and respawns it if it ever dies on its own
#      while the app keeps running.
#   2. Breadcrumbs are written to their OWN small text file via FileAccess,
#      with an explicit flush() after every single line - this does not rely
#      on Godot's engine-log buffering or on logcat at all, so it is the most
#      crash-proof piece here: whatever happened up to the very last line
#      before death is already on disk. Breadcrumbs now carry a lot more
#      context per line (see breadcrumb()) and fire from a lot more call
#      sites: every scene transition (both away from and into), every app
#      pause/resume/focus change, every heartbeat, and any one-off the rest
#      of the codebase logs (OTA events, match aborts, etc).
#   3. `file_logging/flush_after_each_print` is turned on in project.godot so
#      Godot's own engine log (godot.log) is also written line-by-line
#      instead of buffered, as a second copy of everything print()'d.
#
# RETRIEVING THE LOGS after a crash (no root needed):
#   adb pull /sdcard/Android/data/com.spotrush.game/files/crash_logs
# (that path is OS.get_user_data_dir() on a normal Android install; if the
# device has no external storage it falls back to internal app storage and
# you'll need `adb shell run-as com.spotrush.game` instead - the path printed
# to logcat at boot, tag "godot", always says exactly where it went.)
# Each session leaves two files side by side: logcat_<stamp>.txt (full
# system log tail) and breadcrumbs_<stamp>.txt (just our own trail, in order,
# and the one most likely to be intact right up to the crash).
#
# Call CrashLogger.breadcrumb("...") from anywhere worth noting right before
# a risky spot (network step, round transition, big allocation) to narrow
# down a specific crash further.

const MAX_KEPT_SESSIONS: int = 6
const HEARTBEAT_INTERVAL_SEC: float = 15.0
const WATCHDOG_INTERVAL_SEC: float = 20.0

var log_dir: String = ""
var logcat_path: String = ""
var breadcrumb_path: String = ""
var _logcat_helper_pid: int = -1
var _logcat_cmd: String = ""
var _breadcrumb_file: FileAccess = null
var _heartbeat_timer: Timer
var _watchdog_timer: Timer
var _session_start_usec: int = 0
var _crumb_count: int = 0

func _ready() -> void:
	# Outlive scene changes and pausing - a crash can happen anywhere.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_start_usec = Time.get_ticks_usec()

	log_dir = OS.get_user_data_dir().path_join("crash_logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	_prune_old_sessions()

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	logcat_path = log_dir.path_join("logcat_%s.txt" % stamp)
	breadcrumb_path = log_dir.path_join("breadcrumbs_%s.txt" % stamp)
	_breadcrumb_file = FileAccess.open(breadcrumb_path, FileAccess.WRITE)
	if _breadcrumb_file == null:
		push_error("[CrashLogger] Could not open breadcrumb file at %s (err %d)" % [breadcrumb_path, FileAccess.get_open_error()])

	if OS.get_name() == "Android":
		_start_logcat_tail()
	else:
		# Editor / desktop test runs: nothing to tail, but keep the rest of
		# the logger (breadcrumbs, godot.log) working so behavior matches.
		print("[CrashLogger] Platform '%s' - no logcat tail, breadcrumb file + engine log still active." % OS.get_name())

	breadcrumb("CrashLogger armed. pid=%d build=%s os=%s logcat=%s crumbs=%s" % [
		OS.get_process_id(),
		("debug" if OS.is_debug_build() else "release"),
		OS.get_name(),
		logcat_path,
		breadcrumb_path,
	])

	var scene_router := get_node_or_null("/root/SceneRouter")
	if scene_router:
		scene_router.transition_started.connect(_on_scene_transition_started)
		scene_router.transition_finished.connect(_on_scene_transition_finished)

	var app_lifecycle := get_node_or_null("/root/AppLifecycle")
	if app_lifecycle:
		app_lifecycle.app_paused.connect(func() -> void: breadcrumb("App lifecycle: PAUSED (background)"))
		app_lifecycle.app_resumed.connect(func() -> void: breadcrumb("App lifecycle: RESUMED (foreground)"))

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SEC
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_on_heartbeat)
	add_child(_heartbeat_timer)

	if OS.get_name() == "Android":
		_watchdog_timer = Timer.new()
		_watchdog_timer.wait_time = WATCHDOG_INTERVAL_SEC
		_watchdog_timer.autostart = true
		_watchdog_timer.timeout.connect(_on_watchdog_tick)
		add_child(_watchdog_timer)

	get_tree().root.close_requested.connect(func() -> void: breadcrumb("App close requested."))

func _on_scene_transition_started() -> void:
	var current := get_tree().current_scene
	breadcrumb("Scene transition AWAY from: %s" % (current.scene_file_path if current else "?"))

func _on_scene_transition_finished() -> void:
	var current := get_tree().current_scene
	breadcrumb("Scene transition INTO: %s" % (current.scene_file_path if current else "?"))

func _on_heartbeat() -> void:
	breadcrumb(_system_snapshot("heartbeat"))

func _on_watchdog_tick() -> void:
	if _logcat_helper_pid <= 0:
		return
	if OS.is_process_running(_logcat_helper_pid):
		return
	breadcrumb("WATCHDOG: logcat tail helper (pid %d) is gone but app is still alive - respawning." % _logcat_helper_pid)
	_start_logcat_tail()

## Drop a timestamped, numbered marker with a live system snapshot into the
## breadcrumb file (flushed immediately), the engine log, and (implicitly,
## since it is a print()) the logcat tail. Safe to call from anywhere, any
## time.
func breadcrumb(text: String) -> void:
	_crumb_count += 1
	var line := "[CRUMB #%d %s +%.1fs] %s" % [
		_crumb_count,
		Time.get_time_string_from_system(),
		float(Time.get_ticks_usec() - _session_start_usec) / 1_000_000.0,
		text,
	]
	print(line)
	if _breadcrumb_file != null:
		_breadcrumb_file.store_line(line)
		_breadcrumb_file.flush()

## Common fields worth having on every automatic breadcrumb: fps, memory
## (current + peak), current scene, calling thread, and live/orphan object
## counts, so a crash a few seconds later can be matched against "what the
## device looked like at the time" without needing a repro.
func _system_snapshot(label: String) -> String:
	var mem_static_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var mem_peak_mb := float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)
	var current := get_tree().current_scene
	var scene_name := current.scene_file_path if current else "?"
	var parts := PackedStringArray([
		label,
		"fps=%d" % Engine.get_frames_per_second(),
		"mem=%.1fMB" % mem_static_mb,
		"mem_peak=%.1fMB" % mem_peak_mb,
		"scene=%s" % scene_name,
		"thread=%d" % OS.get_thread_caller_id(),
		"objects=%d" % Performance.get_monitor(Performance.OBJECT_COUNT),
		"orphans=%d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	])
	return " ".join(parts)

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
	# `setsid` in front of the real tail command is the important part: it
	# detaches the helper into a brand new session/process group BEFORE it
	# execs logcat, so it is no longer a member of SpotRush's own process
	# group. Android's ActivityManager kills a crashing/ANR'd/force-stopped
	# app by sending the whole process group a SIGKILL (killProcessGroup) -
	# without setsid, a plain child inherits that same group and dies at the
	# exact same instant as the app, which defeats the entire point of
	# tailing from a second process. With it, the tail keeps running and
	# keeps writing for as long as the OS lets logcat itself run.
	var pid := OS.get_process_id()
	_logcat_cmd = "logcat -c; exec setsid logcat -v threadtime --pid=%d >> '%s' 2>&1" % [pid, logcat_path]
	_logcat_helper_pid = OS.create_process("/system/bin/sh", PackedStringArray(["-c", _logcat_cmd]), false)
	if _logcat_helper_pid <= 0:
		push_error("[CrashLogger] Failed to start logcat tail helper process.")
	else:
		print("[CrashLogger] Logcat tail running, detached via setsid (helper pid %d) -> %s" % [_logcat_helper_pid, logcat_path])

func _prune_old_sessions() -> void:
	_prune_prefixed("logcat_")
	_prune_prefixed("breadcrumbs_")

func _prune_prefixed(prefix: String) -> void:
	var dir := DirAccess.open(log_dir)
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

func _exit_tree() -> void:
	if _breadcrumb_file != null:
		_breadcrumb_file.flush()
		_breadcrumb_file.close()
		_breadcrumb_file = null