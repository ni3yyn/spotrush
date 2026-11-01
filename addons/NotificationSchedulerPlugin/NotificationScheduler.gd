#
# © 2024-present https://github.com/cengiz-pz
#

@tool
@icon("icon.png")
class_name NotificationScheduler extends Node

signal initialization_completed

signal post_notifications_permission_granted(permission_name: String)
signal post_notifications_permission_denied(permission_name: String)
signal battery_optimizations_permission_granted(permission_name: String)
signal battery_optimizations_permission_denied(permission_name: String)
signal schedule_exact_alarm_permission_granted(permission_name: String)
signal schedule_exact_alarm_permission_denied(permission_name: String)

signal notification_opened(notification_data: NotificationData)
signal notification_dismissed(notification_data: NotificationData)

const PLUGIN_SINGLETON_NAME: String = "NotificationSchedulerPlugin"
const DEFAULT_NOTIFICATION_ID: int = -1
const DEFAULT_ICON_NAME: String = "ic_default_notification"

var _plugin_singleton: Object = null


func _connect_signal_if_present(a_signal_name: String, a_callable: Callable) -> void:
	if _plugin_singleton.has_signal(a_signal_name):
		if not _plugin_singleton.is_connected(a_signal_name, a_callable):
			_plugin_singleton.connect(a_signal_name, a_callable)


func _connect_signals() -> void:
	_connect_signal_if_present("initialization_completed", _on_initialization_completed)
	_connect_signal_if_present("notification_opened", _on_notification_opened)
	_connect_signal_if_present("notification_dismissed", _on_notification_dismissed)
	_connect_signal_if_present(
		"post_notifications_permission_granted", _on_post_notifications_permission_granted)
	_connect_signal_if_present(
		"post_notifications_permission_denied", _on_post_notifications_permission_denied)
	_connect_signal_if_present(
		"battery_optimizations_permission_granted", _on_battery_optimizations_permission_granted)
	_connect_signal_if_present(
		"battery_optimizations_permission_denied", _on_battery_optimizations_permission_denied)
	_connect_signal_if_present(
		"schedule_exact_alarm_permission_granted", _on_schedule_exact_alarm_permission_granted)
	_connect_signal_if_present(
		"schedule_exact_alarm_permission_denied", _on_schedule_exact_alarm_permission_denied)


func initialize() -> void:
	if _plugin_singleton != null:
		return

	if Engine.has_singleton(PLUGIN_SINGLETON_NAME):
		_plugin_singleton = Engine.get_singleton(PLUGIN_SINGLETON_NAME)
		_connect_signals()
		_plugin_singleton.initialize()
	elif not OS.has_feature("editor_hint"):
		GmpLogger.log_error("%s singleton not found. The Android v6.0 AAR may be missing." % PLUGIN_SINGLETON_NAME)


func create_notification_channel(a_notification_channel: NotificationChannel) -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.create_notification_channel(a_notification_channel.get_raw_data())
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func schedule(a_notification_data: NotificationData) -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.schedule(a_notification_data.get_raw_data())
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func cancel(a_notification_id: int) -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.cancel(a_notification_id)
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func set_badge_count(a_count: int) -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.set_badge_count(a_count)
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func get_notification_id(a_default_value: int = DEFAULT_NOTIFICATION_ID) -> int:
	if _plugin_singleton == null:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
		return a_default_value
	return _plugin_singleton.get_notification_id(a_default_value)


func has_post_notifications_permission() -> bool:
	if _plugin_singleton == null:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
		return false
	return _plugin_singleton.has_post_notifications_permission()


func request_post_notifications_permission() -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.request_post_notifications_permission()
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func has_battery_optimizations_permission() -> bool:
	if _plugin_singleton == null:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
		return false
	return _plugin_singleton.has_battery_optimizations_permission()


func request_battery_optimizations_permission() -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.request_battery_optimizations_permission()
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func has_schedule_exact_alarm_permission() -> bool:
	if _plugin_singleton == null:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
		return false
	return _plugin_singleton.has_schedule_exact_alarm_permission()


func request_schedule_exact_alarm_permission() -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.request_schedule_exact_alarm_permission()
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func open_app_info_settings() -> Error:
	var result: Error = ERR_UNCONFIGURED
	if _plugin_singleton != null:
		result = _plugin_singleton.open_app_info_settings()
	else:
		GmpLogger.log_error("%s singleton not initialized!" % PLUGIN_SINGLETON_NAME)
	return result


func _on_initialization_completed() -> void:
	initialization_completed.emit()


func _on_notification_opened(a_notification_data: Dictionary) -> void:
	notification_opened.emit(NotificationData.new(a_notification_data))


func _on_notification_dismissed(a_notification_data: Dictionary) -> void:
	notification_dismissed.emit(NotificationData.new(a_notification_data))


func _on_post_notifications_permission_granted(a_permission_name: String) -> void:
	post_notifications_permission_granted.emit(a_permission_name)


func _on_post_notifications_permission_denied(a_permission_name: String) -> void:
	post_notifications_permission_denied.emit(a_permission_name)


func _on_battery_optimizations_permission_granted(a_permission_name: String) -> void:
	battery_optimizations_permission_granted.emit(a_permission_name)


func _on_battery_optimizations_permission_denied(a_permission_name: String) -> void:
	battery_optimizations_permission_denied.emit(a_permission_name)


func _on_schedule_exact_alarm_permission_granted(a_permission_name: String) -> void:
	schedule_exact_alarm_permission_granted.emit(a_permission_name)


func _on_schedule_exact_alarm_permission_denied(a_permission_name: String) -> void:
	schedule_exact_alarm_permission_denied.emit(a_permission_name)
