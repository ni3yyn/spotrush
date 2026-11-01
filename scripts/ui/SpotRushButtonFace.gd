extends Label

## Plain text face for SpotRushButton. It mirrors Button.text and fits long
## labels to the available width while preserving the lobby-tab typography.
var _source_button: Button = null
var _last_source_text: String = ""
var _base_font_size: int = 21
var _last_size: Vector2 = Vector2(-1.0, -1.0)

func _ready() -> void:
	_source_button = get_parent() as Button
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_OFF
	clip_text = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_source_text()
	_fit_text()

func _process(_delta: float) -> void:
	if not is_instance_valid(_source_button):
		return
	if _source_button.text != _last_source_text:
		_sync_source_text()
	var enabled_alpha := 1.0 if not _source_button.disabled else 0.72
	if not is_equal_approx(modulate.a, enabled_alpha):
		modulate.a = enabled_alpha
	if size != _last_size:
		_fit_text()

func set_size_policy(base_size: int) -> void:
	_base_font_size = maxi(16, base_size)
	_fit_text()

func _sync_source_text() -> void:
	if not is_instance_valid(_source_button):
		return
	_last_source_text = _source_button.text
	text = _last_source_text.to_upper()
	_fit_text()

func _fit_text() -> void:
	_last_size = size
	var resolved_size := _base_font_size
	if size.x > 0.0 and not text.is_empty():
		var base_font: Font = get_theme_font("font")
		if base_font == null:
			base_font = ThemeDB.fallback_font
		if base_font != null:
			var available_width := maxf(32.0, size.x - 24.0)
			var measured := base_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, resolved_size).x
			if measured > available_width:
				resolved_size = maxi(16, int(floor(float(resolved_size) * available_width / measured)))
	add_theme_font_size_override("font_size", resolved_size)
