extends RefCounted

## Stores first-time challenge practice completion separately from player settings.
## This keeps tutorial progress independent of settings and OTA configuration.

const SAVE_PATH: String = "user://spotrush_tutorial_progress.cfg"
const SECTION: String = "challenge_practice"
const KEY_COMPLETED: String = "completed_families"

static func has_completed(family_type: String) -> bool:
	if family_type.is_empty():
		return false
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	var completed: Array = config.get_value(SECTION, KEY_COMPLETED, [])
	return family_type in completed

static func mark_completed(family_type: String) -> void:
	if family_type.is_empty():
		return
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	var completed: Array = config.get_value(SECTION, KEY_COMPLETED, [])
	if not family_type in completed:
		completed.append(family_type)
	config.set_value(SECTION, KEY_COMPLETED, completed)
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save challenge practice progress: %s" % error_string(error))
