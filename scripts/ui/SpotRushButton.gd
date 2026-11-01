extends RefCounted

## Reusable button treatment based on the HOST A GAME / JOIN A FRIEND tabs
## in LocalLobby: neutral raised neumorphic surface, rounded 22px corners,
## bold centered type, cobalt selected state and slate idle state.
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const SpotRushButtonFaceScript = preload("res://scripts/ui/SpotRushButtonFace.gd")
const FACE_NAME: StringName = &"SpotRushButtonFace"

const DEFAULT_RADIUS: float = 22.0
const DEFAULT_TEXT_COLOR: Color = NeuKit.COBALT
const IDLE_TEXT_COLOR: Color = NeuKit.SLATE

static func apply(button: Button, options: Dictionary = {}) -> void:
	if not is_instance_valid(button):
		return

	var radius := float(options.get("radius", DEFAULT_RADIUS))
	var style: NeuStyle
	if button.has_meta("neu_style"):
		style = button.get_meta("neu_style") as NeuStyle
	else:
		style = NeuKit.style_button(button, "raised", radius)

	# Match the lobby tabs exactly: the button body stays a neutral raised key;
	# selection is communicated by the inset depth and cobalt/slate text.
	style.surface = NeuKit.SURFACE
	style.light = NeuKit.LIGHT
	style.dark = NeuKit.DARK
	style.colored = false
	style.glow = Color(0.0, 0.0, 0.0, 0.0)
	style.gradient = 0.55
	style.rim = 0.7
	style.shadow_steps_override = 0
	style.corner_radius = radius
	style.distance = 6.0
	style.blur = 14.0
	style.depth = 1.0
	style.depth_rest = 1.0
	style.depth_hover = 1.2
	style.depth_press = -0.9
	style.content_margin_left = 10.0
	style.content_margin_right = float(options.get("text_padding_right", 10.0))
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.emit_changed()
	NeuKit.attach_motion(button, style)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, style)

	var disabled_style := NeuKit.disabled_look(radius)
	disabled_style.distance = 3.0
	disabled_style.blur = 7.0
	disabled_style.depth = 0.35
	disabled_style.depth_rest = 0.35
	disabled_style.depth_hover = 0.35
	disabled_style.depth_press = 0.15
	button.add_theme_stylebox_override("disabled", disabled_style)

	var font_size := int(options.get("font_size", _default_font_size(button)))
	button.add_theme_font_override("font", NeuKit.bold_font(button))
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("h_separation", 10)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("spotrush_button", true)

	# Keep Button.text as the public source of truth, while the shared label face
	# provides width fitting without changing the simple lobby-tab typography.
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key, Color(1.0, 1.0, 1.0, 0.0))
	var face := _get_face(button)
	face.add_theme_font_override("font", NeuKit.bold_font(button))
	face.offset_right = -float(options.get("text_padding_right", 0.0))
	face.set_size_policy(font_size)

	var text_color: Color = options.get("text_color", options.get("font_color", options.get("accent_color", IDLE_TEXT_COLOR)))
	_set_text_color(button, text_color)

static func configure(button: Button, title: String, options: Dictionary = {}) -> void:
	if not is_instance_valid(button):
		return
	button.text = title.to_upper()
	apply(button, options)

static func set_selected(button: Button, selected: bool) -> void:
	if not is_instance_valid(button):
		return
	if not button.has_meta("spotrush_button"):
		apply(button)
	NeuKit.set_selected(button, selected)
	_set_text_color(button, DEFAULT_TEXT_COLOR if selected else IDLE_TEXT_COLOR)

## Kept as a small compatibility helper for existing call sites. Accent changes
## the label ink only; button bodies all retain the same neutral material.
static func set_accent(button: Button, accent: Color) -> void:
	if not is_instance_valid(button):
		return
	if not button.has_meta("spotrush_button"):
		apply(button)
	_set_text_color(button, accent)

static func _set_text_color(button: Button, color: Color) -> void:
	var face := _get_face(button)
	face.add_theme_color_override("font_color", color)

static func _get_face(button: Button) -> Label:
	var face := button.get_node_or_null(NodePath(String(FACE_NAME))) as Label
	if face != null:
		return face
	face = SpotRushButtonFaceScript.new() as Label
	face.name = FACE_NAME
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(face)
	return face

static func _default_font_size(button: Button) -> int:
	var existing := button.get_theme_font_size("font_size")
	if existing > 16:
		return existing
	var height := maxf(button.custom_minimum_size.y, button.size.y)
	if height >= 90.0:
		return 30
	if height >= 78.0:
		return 28
	if height >= 68.0:
		return 24
	if height >= 56.0:
		return 21
	if height >= 48.0:
		return 20
	return 18
