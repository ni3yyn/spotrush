extends Node

# v21 DAILY STREAK REMINDER - one gentle nudge, never a nag.
#
# The Daily Spot already carries a Duolingo-style streak (Records.gd) with a
# weekly shield. This module makes the phone speak up for it: when you leave
# the app with an unplayed daily and a live streak, one local notification is
# scheduled for today's (or tomorrow's) reminder hour - "a quick run keeps
# your N-day streak alive". Play the daily, and nothing is ever scheduled.
#
# Hard rules the logic follows:
#   * OFF by default. The player opts in from the settings screen.
#   * At most ONE notification pending, with a fixed id - scheduling again
#     overwrites, and any cancel wipes it. No stacks, no spam.
#   * A streak of 0 is never "at risk", so it never notifies.
#   * Played today -> nothing to protect -> nothing scheduled.
#   * Opening the app cancels the pending nudge (you are already here); the
#     next pause re-evaluates with fresh data.
#
# ANDROID REALITY: Godot 4 has no built-in local notifications, so the actual
# posting is done by the NotificationScheduler Android plugin - a prebuilt AAR
# that SHIPS IN THIS PROJECT (addons/NotificationSchedulerPlugin, enabled in
# project.godot). android_extras/NOTIFICATIONS.md documents the one remaining
# build step (copying the bundled ic_notification set into the gradle
# template) and the icon's license note. On desktop/editor builds - and if
# the addon folder is ever removed - every call here degrades to a logged
# no-op: the game runs identically, it just cannot knock on the notification
# shade. All the DECISION logic below is pure and static, and is verified
# headless by section 11 of ChallengeSystemSelfTest.

# The AAR's native Engine singleton (note: the PLUGIN class name, not the
# wrapper node type, which is called NotificationScheduler).
const BRIDGE_NAME := "NotificationSchedulerPlugin"
# Wrapper node script shipped with the addon - it binds the native singleton,
# converts NotificationData/NotificationChannel into raw dictionaries and
# re-emits permission/open events as GDScript signals.
const WRAPPER_SCRIPT := "res://addons/NotificationSchedulerPlugin/NotificationScheduler.gd"
const NOTIFICATION_ID := 1001
const CHANNEL_ID := "daily_streak"
const CHANNEL_NAME := "Daily streak reminders"
const CHANNEL_DESCRIPTION := "A daily nudge to keep your SpotRush streak alive"
const CHANNEL_IMPORTANCE_DEFAULT := 3
const DEFAULT_HOUR := 19
const REMINDER_ICON := "ic_default_notification"

# House pattern: Settings and Records are plain static classes, referenced
# through preloads (they are not global class names).
const Settings = preload("res://scripts/core/Settings.gd")
const Records = preload("res://scripts/core/Records.gd")

# The bundled plugin's GDScript model classes (loaded dynamically so the game
# still compiles if the addon folder is ever removed).
const PLUGIN_DATA_SCRIPT := "res://addons/NotificationSchedulerPlugin/model/NotificationData.gd"
const PLUGIN_CHANNEL_SCRIPT := "res://addons/NotificationSchedulerPlugin/model/NotificationChannel.gd"

var _plugin_data_script: Script = null
var _plugin_channel_script: Script = null
var _plugin_checked := false
var _bridge = null
var _bridge_ready := false
var _permission_granted := false
var _permission_denied := false

signal permission_state_changed(granted: bool, denied: bool)

func _ready() -> void:
        # Must keep working while the app is paused - pausing is exactly when
        # a reminder gets scheduled.
        process_mode = Node.PROCESS_MODE_ALWAYS
        var life := get_node_or_null("/root/AppLifecycle")
        if life != null:
                life.app_paused.connect(_on_app_paused)
                life.app_resumed.connect(_on_app_resumed)

# --- the pure decision core (unit-tested) -----------------------------------------------

## Decides what should be pending right before the app goes to background.
## `now` is a datetime dict (Time.get_datetime_dict_from_system() shape).
## Returns {"action": "schedule", "delay": int, "title", "content"} or
## {"action": "cancel"}.
static func decide(now: Dictionary, enabled: bool, streak: int, played_today: bool,
                hour: int = DEFAULT_HOUR) -> Dictionary:
        if not enabled or played_today or streak <= 0:
                return _cancelled()
        var delay := next_fire_delay(now, hour)
        if delay <= 0:
                return _cancelled()
        return {
                "action": "schedule",
                "delay": delay,
                "title": "SpotRush daily is waiting",
                "content": "A quick run keeps your %d-day streak alive." % streak,
        }

## Seconds from `now` to the next occurrence of the local wall-clock `hour`
## (today if it has not passed yet, otherwise tomorrow). Both sides go through
## the same datetime arithmetic, so the DELTA is exact even though the engine
## treats the dict as UTC-shaped; a DST shift can bend real-world timing by an
## hour, which is well within "gentle nudge" tolerance.
static func next_fire_delay(now: Dictionary, hour: int) -> int:
        var target := now.duplicate()
        target["hour"] = clampi(hour, 0, 23)
        target["minute"] = 0
        target["second"] = 0
        var now_unix := Time.get_unix_time_from_datetime_dict(now)
        var target_unix := Time.get_unix_time_from_datetime_dict(target)
        if target_unix <= now_unix:
                target_unix += 86400
        return int(target_unix - now_unix)

static func _cancelled() -> Dictionary:
        return {"action": "cancel"}

# --- evaluation hooks --------------------------------------------------------------------

## Only schedule when the feature is enabled AND Android has explicitly granted
## POST_NOTIFICATIONS. In particular, an app-pause caused by the permission
## dialog must never try to post a notification before the user has answered.
func evaluate_now() -> void:
        if not Settings.reminder_enabled():
                cancel_reminder()
                return
        if not _has_notification_permission():
                print("[DailyReminder] Permission not granted; reminder was not scheduled.")
                return
        var decision := decide(
                Time.get_datetime_dict_from_system(),
                true,
                Records.daily_streak(),
                Records.daily_completed_today())
        apply_decision(decision)

func apply_decision(decision: Dictionary) -> void:
        if decision.is_empty():
                return
        if str(decision.get("action", "cancel")) == "schedule":
                schedule_reminder(int(decision.get("delay", 0)),
                                str(decision.get("title", "")),
                                str(decision.get("content", "")))
        else:
                cancel_reminder()

func _on_app_paused() -> void:
        # No lazy plugin initialization while disabled. A pause can also be the
        # OS permission sheet taking focus; _has_notification_permission()
        # blocks scheduling until the explicit grant signal/state is received.
        evaluate_now()

func _on_app_resumed() -> void:
        cancel_reminder()
        _sync_permission_state()

# --- native bridge (Notification Scheduler v6 / Godot 4.7) -------------------------------

## Construct the bridge only when the player opted in or explicitly asks for
## permission. The v6 native initialize() marks its singleton initialized
## synchronously; the completion signal is still connected for state updates.
func bridge():
        if not OS.has_feature("android"):
                return null
        if is_instance_valid(_bridge):
                return _bridge
        if not Engine.has_singleton(BRIDGE_NAME):
                push_warning("[DailyReminder] NotificationSchedulerPlugin native singleton is missing.")
                return null
        var wrapper_script: Script = load(WRAPPER_SCRIPT) if ResourceLoader.exists(WRAPPER_SCRIPT) else null
        if wrapper_script == null:
                push_error("[DailyReminder] v6 NotificationScheduler GDScript wrapper is missing.")
                return null
        _bridge = wrapper_script.new() as Node
        if _bridge == null:
                push_error("[DailyReminder] Could not instantiate NotificationScheduler wrapper.")
                return null
        _bridge.initialization_completed.connect(_on_bridge_initialization_completed)
        _bridge.post_notifications_permission_granted.connect(_on_permission_granted)
        _bridge.post_notifications_permission_denied.connect(_on_permission_denied)
        add_child(_bridge)
        _bridge.initialize()
        # In v6 the Java initialize() sets isInitialized before it returns.
        _bridge_ready = true
        _sync_permission_state()
        return _bridge

func _on_bridge_initialization_completed() -> void:
        _bridge_ready = true
        _sync_permission_state()

func _plugin_scripts() -> bool:
        if not _plugin_checked:
                _plugin_checked = true
                if ResourceLoader.exists(PLUGIN_DATA_SCRIPT):
                        _plugin_data_script = load(PLUGIN_DATA_SCRIPT)
                if ResourceLoader.exists(PLUGIN_CHANNEL_SCRIPT):
                        _plugin_channel_script = load(PLUGIN_CHANNEL_SCRIPT)
        return _plugin_data_script != null and _plugin_channel_script != null

func _sync_permission_state() -> void:
        var granted := false
        if is_instance_valid(_bridge) and _bridge_ready:
                granted = _bridge.has_post_notifications_permission()
        elif OS.has_feature("android"):
                granted = OS.get_granted_permissions().has("android.permission.POST_NOTIFICATIONS")
        var changed := granted != _permission_granted
        _permission_granted = granted
        if granted:
                _permission_denied = false
        if changed:
                permission_state_changed.emit(_permission_granted, _permission_denied)

func _has_notification_permission() -> bool:
        if not OS.has_feature("android"):
                return false
        _sync_permission_state()
        return _permission_granted

func permission_description() -> String:
        if not Settings.reminder_enabled():
                return "Turn this on to protect an active daily streak."
        _sync_permission_state()
        if _permission_granted:
                return "Notifications are allowed. One reminder can be scheduled when you leave the app."
        if _permission_denied:
                return "Permission denied. Allow notifications in Android app settings to use this reminder."
        return "Android will ask whether SpotRush can send notifications."

## This calls the v6 plugin's ActivityCompat.requestPermissions(), which opens
## Android's real Allow / Don't allow dialog and emits a grant/deny signal.
## The OS API is a fallback only when the native plugin is unavailable.
func request_permission() -> void:
        if not OS.has_feature("android"):
                _permission_denied = true
                permission_state_changed.emit(false, true)
                return
        var native := bridge()
        if native == null:
                push_warning("[DailyReminder] Falling back to Godot's Android permission request.")
                OS.request_permission("android.permission.POST_NOTIFICATIONS")
                await get_tree().process_frame
                _sync_permission_state()
                if not _permission_granted:
                        _permission_denied = true
                        permission_state_changed.emit(false, true)
                return
        if native.has_post_notifications_permission():
                _permission_granted = true
                _permission_denied = false
                permission_state_changed.emit(true, false)
                # Already granted: safe to evaluate immediately. If a dialog is
                # shown, scheduling remains deferred until the next app pause.
                evaluate_now()
                return
        var result: Error = native.request_post_notifications_permission()
        if result != OK:
                push_warning("[DailyReminder] v6 permission request returned error %d; using Godot fallback." % result)
                OS.request_permission("android.permission.POST_NOTIFICATIONS")

func _on_permission_granted(_permission_name: String) -> void:
        _permission_granted = true
        _permission_denied = false
        permission_state_changed.emit(true, false)
        print("[DailyReminder] Android POST_NOTIFICATIONS permission granted.")

func _on_permission_denied(_permission_name: String) -> void:
        _permission_granted = false
        _permission_denied = true
        cancel_reminder()
        permission_state_changed.emit(false, true)
        print("[DailyReminder] Android POST_NOTIFICATIONS permission denied.")

func schedule_reminder(delay_seconds: int, title: String, content: String) -> void:
        if delay_seconds <= 0 or not Settings.reminder_enabled():
                return
        if not _has_notification_permission():
                push_warning("[DailyReminder] Refusing to schedule without POST_NOTIFICATIONS permission.")
                return
        var native := bridge()
        if native == null or not _bridge_ready or not _plugin_scripts():
                push_error("[DailyReminder] Cannot schedule: v6 Android notification bridge/models unavailable.")
                return
        _ensure_channel(native)
        var data = _plugin_data_script.new()
        data.set_id(NOTIFICATION_ID) \
                .set_channel_id(CHANNEL_ID) \
                .set_title(title) \
                .set_content(content) \
                .set_small_icon_name(REMINDER_ICON) \
                .set_delay(delay_seconds)
        var result: Error = native.schedule(data)
        if result != OK:
                push_warning("[DailyReminder] Native schedule returned error %d." % result)
        else:
                print("[DailyReminder] Streak reminder scheduled in %d seconds." % delay_seconds)

## Do not initialize the native plugin just to cancel an empty queue.
func cancel_reminder() -> void:
        if not is_instance_valid(_bridge) or not _bridge_ready:
                return
        var result: Error = _bridge.cancel(NOTIFICATION_ID)
        if result != OK:
                push_warning("[DailyReminder] Native cancel returned error %d." % result)

func _ensure_channel(native) -> void:
        if _plugin_channel_script == null:
                return
        var channel = _plugin_channel_script.new()
        channel.set_id(CHANNEL_ID) \
                .set_name(CHANNEL_NAME) \
                .set_description(CHANNEL_DESCRIPTION) \
                .set_importance(CHANNEL_IMPORTANCE_DEFAULT)
        var result: Error = native.create_notification_channel(channel)
        if result != OK and result != ERR_ALREADY_EXISTS:
                push_warning("[DailyReminder] Notification channel creation returned error %d." % result)
