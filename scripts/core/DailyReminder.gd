extends Node

## Daily Spot reminder service.
##
## Responsibilities are deliberately split:
## - The bundled Android plugin requests POST_NOTIFICATIONS and reports the result.
## - NotificationSchedulerPlugin only creates the channel and schedules local alarms.
## - Settings + Records decide whether a daily reminder is actually due.
## - A test notification uses its own ID, so it can never replace/cancel the daily reminder.

const BRIDGE_NAME := "NotificationSchedulerPlugin"
const WRAPPER_SCRIPT := "res://addons/NotificationSchedulerPlugin/NotificationScheduler.gd"
const NOTIFICATION_DATA_SCRIPT := "res://addons/NotificationSchedulerPlugin/model/NotificationData.gd"
const NOTIFICATION_CHANNEL_SCRIPT := "res://addons/NotificationSchedulerPlugin/model/NotificationChannel.gd"

const REMINDER_NOTIFICATION_ID := 1001
const TEST_NOTIFICATION_ID := 1002
const CHANNEL_ID := "daily_spot_reminders_v2"
const CHANNEL_NAME := "Daily Spot reminders"
const CHANNEL_DESCRIPTION := "A single optional reminder when today's Daily Spot is unfinished."
const CHANNEL_IMPORTANCE_DEFAULT := 3
const DEFAULT_HOUR := 19
const TEST_DELAY_SECONDS := 5
const REMINDER_ICON := "ic_default_notification"

const Settings = preload("res://scripts/core/Settings.gd")
const Records = preload("res://scripts/core/Records.gd")

signal permission_state_changed(granted: bool, denied: bool)
signal status_changed

var _bridge: Variant = null
var _bridge_ready := false
var _plugin_data_script: Script = null
var _plugin_channel_script: Script = null
var _plugin_scripts_checked := false
var _channel_ensured := false
var _permission_granted := false
var _permission_denied := false
var _permission_request_in_flight := false
var _pending_permission_action := "" # reminder | test
var _pending_test_notification := false
var _status_message := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var life := get_node_or_null("/root/AppLifecycle")
	if life != null:
		if not life.app_paused.is_connected(_on_app_paused):
			life.app_paused.connect(_on_app_paused)
		if not life.app_resumed.is_connected(_on_app_resumed):
			life.app_resumed.connect(_on_app_resumed)
	if OS.has_feature("android"):
		call_deferred("_cancel_pending_reminder_on_launch")


func _cancel_pending_reminder_on_launch() -> void:
	# Clear any alarm created by the previous reminder implementation. A fresh
	# background transition will schedule the new rules if the feature is on.
	if _ensure_bridge_ready():
		_bridge.cancel(REMINDER_NOTIFICATION_ID)


# --- Pure scheduling rules ---------------------------------------------------------------

## Schedules one local reminder when the feature is enabled and today's Daily
## Spot has not been completed. A player with no streak can still start one.
static func decide(now: Dictionary, enabled: bool, streak: int, played_today: bool,
		hour: int = DEFAULT_HOUR) -> Dictionary:
	if not enabled or played_today:
		return {"action": "cancel"}
	var delay := next_fire_delay(now, hour)
	if delay <= 0:
		return {"action": "cancel"}
	var content := "Play today's Daily Spot and start building your streak."
	if streak > 0:
		content = "A quick Daily Spot run keeps your streak moving. Play now!"
	return {
		"action": "schedule",
		"delay": delay,
		"title": "Your Daily Spot is waiting",
		"content": content,
		"interval": 86400,
	}


## Seconds until the next local wall-clock occurrence of the selected hour.
## If today's time has passed (or is exactly now), schedule for tomorrow.
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


# --- Public settings actions -------------------------------------------------------------

func request_reminder_permission() -> void:
	if not OS.has_feature("android"):
		_set_status("Daily notifications are available in Android builds.")
		return
	if _ensure_bridge() == null:
		_set_status("The Android notification service is missing from this build.")
		return
	_pending_permission_action = "reminder"
	if not _bridge_ready:
		_set_status("Preparing Android notifications. Permission will be requested automatically.")
		return
	if _has_notification_permission():
		_pending_permission_action = ""
		_ensure_channel_ready()
		_set_status(_enabled_status())
		return
	_request_android_permission()


## A real test, available in release and debug Android builds. If permission
## is missing, the Android permission sheet is opened first and the test is
## automatically scheduled after the player grants it.
func request_test_notification() -> void:
	if not OS.has_feature("android"):
		_set_status("The notification test runs on an installed Android build.")
		return
	if _ensure_bridge() == null:
		_set_status("The Android notification service is unavailable in this APK.")
		return
	_pending_test_notification = true
	_pending_permission_action = "test"
	if not _bridge_ready:
		_set_status("Preparing the notification test. It will continue automatically.")
		return
	if _has_notification_permission():
		_pending_permission_action = ""
		_pending_test_notification = false
		_send_test_notification()
	else:
		_request_android_permission()


func reminder_disabled() -> void:
	if _pending_permission_action == "reminder":
		_pending_permission_action = ""
	cancel_reminder()
	_set_status("Daily Spot reminder is off.")


func reminder_time_updated() -> void:
	_set_status("Reminder time saved. It will be used the next time SpotRush schedules a reminder.")


func open_notification_settings() -> void:
	if not OS.has_feature("android"):
		return
	var native: Variant = _ensure_bridge()
	if native == null or not _bridge_ready:
		_set_status("Could not open Android notification settings.")
		return
	var result: Error = native.open_app_info_settings()
	if result != OK:
		_set_status("Android app settings could not be opened (error %d)." % result)
	else:
		_set_status("Enable SpotRush notifications in Android app settings, then return here.")


func permission_denied() -> bool:
	return _permission_denied


func permission_request_pending() -> bool:
	return _permission_request_in_flight


func action_pending() -> bool:
	return _permission_request_in_flight or not _pending_permission_action.is_empty() or _pending_test_notification


func permission_description() -> String:
	if not OS.has_feature("android"):
		return "Daily reminders and the test notification are available in the Android app."
	_ensure_bridge_ready()
	_sync_permission_state()
	if not _status_message.is_empty():
		return _status_message
	if _permission_request_in_flight:
		return "Waiting for Android notification permission…"
	if _permission_denied:
		return "Notifications are blocked. Allow them in Android app settings, then return to SpotRush."
	if _permission_granted:
		return _enabled_status()
	if Settings.reminder_enabled():
		return "Reminder is on. Android notification permission is still needed."
	return "Off by default. Turn it on to receive one reminder if today's Daily Spot is unfinished."


func _enabled_status() -> String:
	var hour := Settings.reminder_hour()
	var suffix := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	if Settings.reminder_enabled():
		return "Reminder on · %d:00 %s · skipped automatically after you play." % [display_hour, suffix]
	return "Notifications are allowed. Turn on the reminder whenever you need it."


# --- App lifecycle and scheduling --------------------------------------------------------

func evaluate_now() -> void:
	if not Settings.reminder_enabled():
		cancel_reminder()
		return
	if not _has_notification_permission():
		_set_status("Reminder is on, but Android notification permission is not granted.")
		return
	_ensure_channel_ready()
	var decision := decide(
		Time.get_datetime_dict_from_system(),
		true,
		Records.daily_streak(),
		Records.daily_completed_today(),
		Settings.reminder_hour())
	apply_decision(decision)


func apply_decision(decision: Dictionary) -> void:
	if decision.is_empty():
		return
	if str(decision.get("action", "cancel")) == "schedule":
		var ok := _schedule_local_notification(
			REMINDER_NOTIFICATION_ID,
			int(decision.get("delay", 0)),
			str(decision.get("title", "")),
			str(decision.get("content", "")),
			int(decision.get("interval", 0)))
		if ok:
			_set_status("Daily Spot reminder scheduled for your selected time.")
	else:
		cancel_reminder()


func _on_app_paused() -> void:
	if _permission_request_in_flight:
		return
	evaluate_now()


func _on_app_resumed() -> void:
	# The player is back in the game, so a pending daily nudge is no longer useful.
	# The test uses ID 1002 and is intentionally not touched here.
	cancel_reminder()
	_sync_permission_state()


# --- Android bridge and permissions ------------------------------------------------------

func _ensure_bridge() -> Variant:
	if not OS.has_feature("android"):
		return null
	if is_instance_valid(_bridge):
		return _bridge
	if not Engine.has_singleton(BRIDGE_NAME):
		push_error("[DailyReminder] Missing native singleton: %s" % BRIDGE_NAME)
		return null
	if not ResourceLoader.exists(WRAPPER_SCRIPT):
		push_error("[DailyReminder] Missing NotificationScheduler GDScript wrapper.")
		return null
	var wrapper_script := load(WRAPPER_SCRIPT) as Script
	if wrapper_script == null:
		push_error("[DailyReminder] Could not load notification wrapper script.")
		return null
	var bridge_node := wrapper_script.new() as Node
	if bridge_node == null:
		push_error("[DailyReminder] Could not instantiate notification wrapper.")
		return null
	_bridge = bridge_node
	_bridge.initialization_completed.connect(_on_bridge_initialization_completed)
	_bridge.post_notifications_permission_granted.connect(_on_permission_granted)
	_bridge.post_notifications_permission_denied.connect(_on_permission_denied)
	add_child(bridge_node)
	_bridge.initialize()
	return _bridge


func _ensure_bridge_ready() -> bool:
	var native: Variant = _ensure_bridge()
	return native != null and _bridge_ready


func _on_bridge_initialization_completed() -> void:
	_bridge_ready = true
	_sync_permission_state()
	_ensure_channel_ready()
	if not _pending_permission_action.is_empty():
		if _has_notification_permission():
			_on_permission_granted("android.permission.POST_NOTIFICATIONS")
		else:
			_request_android_permission()


func _request_android_permission() -> void:
	if _permission_request_in_flight:
		return
	if not _ensure_bridge_ready():
		# Keep the pending action. _on_bridge_initialization_completed retries it.
		_set_status("Preparing Android notifications before requesting permission.")
		return
	if _has_notification_permission():
		_handle_permission_result(true)
		return
	_permission_request_in_flight = true
	_permission_denied = false
	_set_status("Android will ask whether SpotRush can send notifications.")
	# Use the bundled plugin's request code: its native callback emits the
	# permission_granted / permission_denied signals consumed by this wrapper.
	var result: Error = _bridge.request_post_notifications_permission()
	if result != OK:
		_permission_request_in_flight = false
		_set_status("Android could not open the notification permission prompt (error %d)." % result)


func _on_permission_granted(_permission_name: String) -> void:
	_handle_permission_result(true)


func _on_permission_denied(_permission_name: String) -> void:
	_handle_permission_result(false)


func _handle_permission_result(granted: bool) -> void:
	_permission_request_in_flight = false
	_pending_permission_action = ""
	_permission_granted = granted
	_permission_denied = not granted
	permission_state_changed.emit(_permission_granted, _permission_denied)
	status_changed.emit()
	if granted:
		_ensure_channel_ready()
		_set_status("Notifications allowed. Your Daily Spot reminder is ready.")
		if _pending_test_notification:
			_pending_test_notification = false
			_send_test_notification()
	else:
		_pending_test_notification = false
		cancel_reminder()
		_set_status("Permission denied. Enable notifications in Android app settings to continue.")


func _sync_permission_state() -> void:
	if not OS.has_feature("android"):
		return
	if not is_instance_valid(_bridge) or not _bridge_ready:
		return
	var granted := bool(_bridge.has_post_notifications_permission())
	var changed := granted != _permission_granted
	_permission_granted = granted
	if granted:
		_permission_denied = false
	elif changed and not _permission_request_in_flight:
		# A previously granted permission was revoked in Android settings.
		_permission_denied = true
	if changed:
		_status_message = ""
		permission_state_changed.emit(_permission_granted, _permission_denied)
		status_changed.emit()


func _has_notification_permission() -> bool:
	if not _ensure_bridge_ready():
		return false
	_sync_permission_state()
	return _permission_granted


# --- Notification channel and scheduling ------------------------------------------------

func _plugin_scripts_ready() -> bool:
	if not _plugin_scripts_checked:
		_plugin_scripts_checked = true
		if ResourceLoader.exists(NOTIFICATION_DATA_SCRIPT):
			_plugin_data_script = load(NOTIFICATION_DATA_SCRIPT)
		if ResourceLoader.exists(NOTIFICATION_CHANNEL_SCRIPT):
			_plugin_channel_script = load(NOTIFICATION_CHANNEL_SCRIPT)
	return _plugin_data_script != null and _plugin_channel_script != null


func _ensure_channel_ready() -> void:
	if _channel_ensured or not _permission_granted:
		return
	if not _ensure_bridge_ready() or not _plugin_scripts_ready():
		return
	var channel = _plugin_channel_script.new()
	channel.set_id(CHANNEL_ID) \
		.set_name(CHANNEL_NAME) \
		.set_description(CHANNEL_DESCRIPTION) \
		.set_importance(CHANNEL_IMPORTANCE_DEFAULT) \
		.set_badge_enabled(true)
	var result: Error = _bridge.create_notification_channel(channel)
	if result == OK or result == ERR_ALREADY_EXISTS:
		_channel_ensured = true
	else:
		push_warning("[DailyReminder] Channel creation returned error %d." % result)


func _schedule_local_notification(notification_id: int, delay_seconds: int,
		title: String, content: String, interval_seconds: int = 0) -> bool:
	if delay_seconds <= 0:
		return false
	if not _has_notification_permission():
		_set_status("Notifications are not allowed on this device.")
		return false
	if not _plugin_scripts_ready():
		_set_status("Notification data models are missing from this build.")
		return false
	_ensure_channel_ready()
	if not _channel_ensured:
		_set_status("The Android notification channel could not be created.")
		return false
	var data = _plugin_data_script.new()
	data.set_id(notification_id) \
		.set_channel_id(CHANNEL_ID) \
		.set_title(title) \
		.set_content(content) \
		.set_small_icon_name(REMINDER_ICON) \
		.set_delay(delay_seconds)
	if interval_seconds > 0:
		data.set_interval(interval_seconds)
	var result: Error = _bridge.schedule(data)
	if result != OK:
		_set_status("Android could not schedule the notification (error %d)." % result)
		return false
	print("[DailyReminder] Scheduled notification id=%d delay=%ds." % [notification_id, delay_seconds])
	return true


func _send_test_notification() -> void:
	if not _has_notification_permission():
		_set_status("Test not sent: notification permission is not granted.")
		return
	var ok := _schedule_local_notification(
		TEST_NOTIFICATION_ID,
		TEST_DELAY_SECONDS,
		"SpotRush test notification",
		"Notifications are working. Your Daily Spot reminder is ready.")
	if ok:
		_set_status("Test notification scheduled. It should arrive in about 5 seconds.")


func cancel_reminder() -> void:
	if not OS.has_feature("android"):
		return
	var native: Variant = _ensure_bridge()
	if native == null or not _bridge_ready:
		return
	var result: Error = native.cancel(REMINDER_NOTIFICATION_ID)
	if result != OK:
		push_warning("[DailyReminder] Reminder cancellation returned error %d." % result)


func _set_status(message: String) -> void:
	_status_message = message
	print("[DailyReminder] %s" % message)
	status_changed.emit()
