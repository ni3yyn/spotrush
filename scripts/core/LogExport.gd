extends RefCounted

# Static helpers for getting SpotRush's on-device diagnostic logs (see
# CrashLogger.gd) into a bug report: a clipboard copy for a quick paste, or a
# single zip file on disk for `adb pull` / email attachment. Pure file I/O,
# no autoload needed - safe to call from anywhere, any time.
#
# Why the two most recent SESSIONS of each log type, not just "the current
# one": the whole point of this screen is usually reached by crashing,
# relaunching, then going to Settings to grab the evidence. At that point the
# "current" session is the brand-new, nearly-empty one that just booted - the
# interesting content is in the PREVIOUS session's files. Pulling the latest
# two (clearly labelled) covers both that case and "something is going wrong
# right now, grab live state" without the player having to know which one
# they need.

const MAX_CLIPBOARD_CHARS := 120_000 # clipboard backends choke on multi-MB blobs; this is plenty of context
const SESSIONS_IN_REPORT := 2

## True if CrashLogger has a log directory to work with at all.
static func has_logs() -> bool:
	return not CrashLogger.log_dir.is_empty() and DirAccess.dir_exists_absolute(CrashLogger.log_dir)

## Every session file of one kind in the log dir, newest first (filenames are
## timestamp-sortable, see CrashLogger._ready()).
static func _session_files(prefix: String) -> Array[String]:
	var out: Array[String] = []
	if not has_logs():
		return out
	var dir := DirAccess.open(CrashLogger.log_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with(prefix):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	out.reverse()
	return out

static func _read_capped(path: String, max_chars: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	if text.length() > max_chars:
		text = "...[truncated - showing the last %d of %d characters]...\n" % [max_chars, text.length()] \
			+ text.substr(text.length() - max_chars)
	return text

## One readable block per recent session of `prefix`, newest first, each
## clearly labelled with its own filename and a per-section character cap so
## the whole report stays bounded regardless of how large any single log got.
static func _recent_sections(prefix: String, label: String, per_section_cap: int) -> String:
	var files := _session_files(prefix)
	if files.is_empty():
		return "--- %s: none found ---" % label
	var parts: Array[String] = []
	for i in mini(SESSIONS_IN_REPORT, files.size()):
		var file_name: String = files[i]
		var tag := "current session" if i == 0 else "previous session"
		parts.append("--- %s (%s, %s) ---" % [label, file_name, tag])
		parts.append(_read_capped(CrashLogger.log_dir.path_join(file_name), per_section_cap))
	return "\n".join(parts)

## Builds a single readable block covering the two most recent breadcrumb
## sessions and (on Android) the two most recent logcat tails, capped so
## clipboard managers don't choke, ready to paste straight into a bug report.
static func build_report_text() -> String:
	var per_section_cap := MAX_CLIPBOARD_CHARS / (2 * SESSIONS_IN_REPORT)
	var parts: Array[String] = []
	parts.append("SpotRush diagnostic log")
	parts.append("build=%s platform=%s pid=%d" % [
		("debug" if OS.is_debug_build() else "release"), OS.get_name(), OS.get_process_id(),
	])
	parts.append("generated %s" % Time.get_datetime_string_from_system(false, true))
	parts.append("")
	parts.append(_recent_sections("breadcrumbs_", "breadcrumbs", per_section_cap))
	parts.append("")
	parts.append(_recent_sections("logcat_", "logcat tail", per_section_cap))
	return "\n".join(parts)

## Copies build_report_text() to the system clipboard. Returns true on
## success, false only when there are no logs at all yet to copy.
static func copy_report_to_clipboard() -> bool:
	if not has_logs():
		return false
	DisplayServer.clipboard_set(build_report_text())
	return true

## Zips EVERY file currently kept in the log dir (CrashLogger prunes to the
## last MAX_KEPT_SESSIONS of each kind, so this is bounded) into one archive
## under user://exported_logs/, named with a timestamp so repeated exports
## don't collide. Returns the globalized absolute path on success, "" if
## there was nothing to zip or the zip could not be written.
static func export_zip() -> String:
	if not has_logs():
		return ""
	var dir := DirAccess.open(CrashLogger.log_dir)
	if dir == null:
		return ""
	var entries: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			entries.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	if entries.is_empty():
		return ""

	var export_dir := "user://exported_logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(export_dir))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var zip_path: String = export_dir.path_join("spotrush_logs_%s.zip" % stamp)

	var packer := ZIPPacker.new()
	var err := packer.open(zip_path)
	if err != OK:
		push_error("[LogExport] Could not open zip for writing (err %d): %s" % [err, zip_path])
		return ""
	for file_name in entries:
		var f := FileAccess.open(CrashLogger.log_dir.path_join(file_name), FileAccess.READ)
		if f == null:
			continue
		var bytes := f.get_buffer(f.get_length())
		f.close()
		packer.start_file(file_name)
		packer.write_file(bytes)
		packer.close_file()
	packer.close()
	return ProjectSettings.globalize_path(zip_path)