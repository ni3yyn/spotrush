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
const REMINDER_ICON := "ic_notification"

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
var _bridge: Node = null
var _bridge_ready := false

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

## Reads today's streak state and schedules/cancels accordingly. Called when
## the app pauses and when the player flips the setting.
func evaluate_now() -> void:
        var decision := decide(
                Time.get_datetime_dict_from_system(),
                Settings.reminder_enabled(),
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
        evaluate_now()

func _on_app_resumed() -> void:
        # The player is here; the pending nudge would be noise. If they leave
        # without playing, the next pause schedules a fresh one.
        cancel_reminder()

# --- native bridge (bundled plugin) -------------------------------------------------------

## The plugin's wrapper node (NotificationScheduler), or null on desktop/editor
## builds and if the AAR failed to load. Created lazily and kept as a child of
## this autoload, so it lives as long as the game does.
func bridge():
        if not OS.has_feature("android"):
                return null
        if not Engine.has_singleton(BRIDGE_NAME):
                return null
        if _bridge == null:
                var wrapper_script: Script = load(WRAPPER_SCRIPT) if ResourceLoader.exists(WRAPPER_SCRIPT) else null
                if wrapper_script == null:
                        return null
                _bridge = wrapper_script.new()
                _bridge.initialization_completed.connect(_on_bridge_initialization_completed, CONNECT_ONE_SHOT)
                add_child(_bridge)
                _bridge.initialize()
        return _bridge

func _on_bridge_initialization_completed() -> void:
        _bridge_ready = true

func _plugin_scripts() -> bool:
        if not _plugin_checked:
                _plugin_checked = true
                if ResourceLoader.exists(PLUGIN_DATA_SCRIPT):
                        _plugin_data_script = load(PLUGIN_DATA_SCRIPT)
                if ResourceLoader.exists(PLUGIN_CHANNEL_SCRIPT):
                        _plugin_channel_script = load(PLUGIN_CHANNEL_SCRIPT)
        return _plugin_data_script != null

## Android 13+ gates notifications behind a runtime permission. Asked once,
## from the settings toggle the player just turned on (the polite moment).
func request_permission() -> void:
        var native = bridge()
        if native == null:
                push_warning("[DailyReminder] Android notification bridge is unavailable; permission was not requested.")
                return
        # The native plugin initializes asynchronously. Calling its permission
        # methods immediately after initialize() can hit an uninitialized
        # singleton, which is especially likely when the setting is enabled
        # from the settings screen. Wait for the plugin's ready signal first.
        if not _bridge_ready:
                await native.initialization_completed
                if not is_instance_valid(native):
                        return
        if not native.has_post_notifications_permission():
                native.request_post_notifications_permission()

func schedule_reminder(delay_seconds: int, title: String, content: String) -> void:
        if delay_seconds <= 0:
                return
        var native = bridge()
        if native == null or not _plugin_scripts():
                print("[DailyReminder] (no native bridge) would notify in %ds: %s - %s"
                                % [delay_seconds, title, content])
                return
        _ensure_channel(native)
        var data = _plugin_data_script.new()
        data.set_id(NOTIFICATION_ID) \
                .set_channel_id(CHANNEL_ID) \
                .set_title(title) \
                .set_content(content) \
                .set_small_icon_name(REMINDER_ICON) \
                .set_delay(delay_seconds)
        native.schedule(data)

## Safe to call any time; a cancel with nothing pending is a no-op.
func cancel_reminder() -> void:
        var native = bridge()
        if native == null:
                return
        native.cancel(NOTIFICATION_ID)

func _ensure_channel(native) -> void:
        if _plugin_channel_script == null:
                return
        var channel = _plugin_channel_script.new()
        channel.set_id(CHANNEL_ID) \
                .set_name(CHANNEL_NAME) \
                .set_description(CHANNEL_DESCRIPTION) \
                .set_importance(CHANNEL_IMPORTANCE_DEFAULT)
        # The wrapper converts the model into the raw dictionary the AAR expects.
        native.create_notification_channel(channel)
