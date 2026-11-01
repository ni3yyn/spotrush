class_name PracticeCoach
extends Control

## First-time practice guidance presented directly on the game surface.
## The choices remain explicit, but there is no modal card or opaque scrim.

signal choice_made(primary: bool)

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _content: VBoxContainer
var _title: NeuText
var _message: NeuText
var _action_column: VBoxContainer
var _primary_button: Button
var _secondary_button: Button
var _primary_label: NeuText
var _secondary_label: NeuText
var _waiting_for_choice: bool = false
var _last_choice: bool = false
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false

func _build() -> void:
	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	_content = VBoxContainer.new()
	_content.name = "TutorialContent"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 22)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_content)

	_title = NeuText.new()
	_title.name = "TutorialTitle"
	_title.custom_minimum_size = Vector2(0.0, 76.0)
	_title.font_size = 44
	_title.bold = true
	_title.color = NeuKit.INK
	_title.look = NeuText.Look.EMBOSS
	_title.align = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap = true
	SpotRushTypography.apply_as(_title, SpotRushTypography.Role.DISPLAY)
	_content.add_child(_title)

	_message = NeuText.new()
	_message.name = "TutorialMessage"
	_message.custom_minimum_size = Vector2(0.0, 180.0)
	_message.font_size = 30
	_message.bold = false
	_message.color = Color("35415A")
	_message.look = NeuText.Look.EMBOSS
	_message.align = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap = true
	_message.line_spacing = 8.0
	_content.add_child(_message)

	_action_column = VBoxContainer.new()
	_action_column.name = "TutorialActions"
	_action_column.add_theme_constant_override("separation", 14)
	_action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_action_column)

	_primary_button = _make_button("PRACTICE NOW", true)
	_primary_label = _primary_button.get_child(0) as NeuText
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(_on_primary_pressed)
	_action_column.add_child(_primary_button)

	_secondary_button = _make_button("SKIP FOR NOW", false)
	_secondary_label = _secondary_button.get_child(0) as NeuText
	_secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_button.pressed.connect(_on_secondary_pressed)
	_action_column.add_child(_secondary_button)

	_reflow()

func _make_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 78.0)
	button.focus_mode = Control.FOCUS_NONE
	var style: NeuStyle = NeuKit.style_button(button, "primary" if primary else "raised", 22.0)
	if primary:
		NeuKit.set_accent(button, NeuKit.COBALT)
	var label := NeuText.new()
	label.text = caption
	label.font_size = 22
	label.bold = true
	label.color = Color.WHITE if primary else NeuKit.INK
	label.look = NeuText.Look.ON_ACCENT if primary else NeuText.Look.EMBOSS
	label.accent_base = NeuKit.COBALT
	label.tracking = 0.7
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	label.bind_style(style)
	return button

func _reflow() -> void:
	if _content == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var horizontal_margin: int = 26 if viewport_size.x < 440.0 else 42
	var margin := get_node_or_null("ContentMargin") as MarginContainer
	if margin != null:
		margin.add_theme_constant_override("margin_left", horizontal_margin)
		margin.add_theme_constant_override("margin_right", horizontal_margin)
	_content.custom_minimum_size = Vector2(maxf(240.0, viewport_size.x - float(horizontal_margin * 2)), 0.0)

func present(title_text: String, message_text: String, primary_text: String,
		secondary_text: String = "SKIP FOR NOW") -> bool:
	_title.text = title_text
	_message.text = message_text
	_primary_label.text = primary_text
	_secondary_button.visible = not secondary_text.is_empty()
	if _secondary_button.visible:
		_secondary_label.text = secondary_text
	_waiting_for_choice = true
	_last_choice = false
	visible = true
	_reflow()
	await get_tree().process_frame
	_content.pivot_offset = _content.size * 0.5
	_kill_tween()
	if Feel.reduced():
		_content.modulate = Color.WHITE
		_content.scale = Vector2.ONE
	else:
		_content.modulate.a = 0.0
		_content.scale = Vector2(0.96, 0.96)
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_content, "modulate:a", 1.0, 0.22)
		_tween.tween_property(_content, "scale", Vector2.ONE, 0.30)
		await _tween.finished
	if _waiting_for_choice:
		await choice_made
	var selected_primary: bool = _last_choice
	await _dismiss()
	return selected_primary

func _on_primary_pressed() -> void:
	_resolve_choice(true)

func _on_secondary_pressed() -> void:
	_resolve_choice(false)

func _resolve_choice(primary: bool) -> void:
	if not _waiting_for_choice:
		return
	_waiting_for_choice = false
	_last_choice = primary
	choice_made.emit(primary)

func cancel() -> void:
	_resolve_choice(false)

func _dismiss() -> void:
	if Feel.reduced():
		visible = false
		_content.modulate = Color.WHITE
		_content.scale = Vector2.ONE
		return
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_content, "scale", Vector2(0.98, 0.98), 0.12)
	_tween.tween_property(_content, "modulate:a", 0.0, 0.14)
	await _tween.finished
	visible = false
	_content.modulate = Color.WHITE
	_content.scale = Vector2.ONE

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
