class_name PracticeCoach
extends Control

## Full-screen, text-first practice guidance. The game backdrop remains visible;
## there is no scrim, modal card, or cramped button row.

signal choice_made(primary: bool)

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _content: VBoxContainer
var _title: NeuText
var _message: NeuText
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
	_content = VBoxContainer.new()
	_content.name = "TutorialContent"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 28.0
	_content.offset_top = 36.0
	_content.offset_right = -28.0
	_content.offset_bottom = -36.0
	_content.add_theme_constant_override("separation", 22)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_content)

	_title = NeuText.new()
	_title.name = "TutorialTitle"
	_title.custom_minimum_size = Vector2(0.0, 78.0)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.font_size = 56
	_title.bold = true
	_title.color = NeuKit.INK
	_title.look = NeuText.Look.EMBOSS
	_title.align = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap = true
	_content.add_child(_title)

	_message = NeuText.new()
	_message.name = "TutorialInstructions"
	_message.custom_minimum_size = Vector2(0.0, 250.0)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_message.font_size = 34
	_message.bold = false
	_message.color = NeuKit.SLATE
	_message.look = NeuText.Look.EMBOSS
	_message.align = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap = true
	_message.line_spacing = 9.0
	_content.add_child(_message)

	var button_stack := VBoxContainer.new()
	button_stack.name = "TutorialActions"
	button_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_stack.add_theme_constant_override("separation", 16)
	_content.add_child(button_stack)

	_primary_button = _make_button("PRACTICE NOW", true, 92.0)
	_primary_label = _primary_button.get_child(0) as NeuText
	_primary_button.pressed.connect(_on_primary_pressed)
	button_stack.add_child(_primary_button)

	_secondary_button = _make_button("SKIP FOR NOW", false, 84.0)
	_secondary_label = _secondary_button.get_child(0) as NeuText
	_secondary_button.pressed.connect(_on_secondary_pressed)
	button_stack.add_child(_secondary_button)

	_reflow()

func _make_button(caption: String, primary: bool, height: float) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	var style: NeuStyle = NeuKit.style_button(button, "raised", 24.0)
	if primary:
		NeuKit.set_accent(button, NeuKit.MINT)
	var label := NeuText.new()
	label.text = caption
	label.font_size = 34
	label.bold = true
	label.color = NeuKit.INK
	label.look = NeuText.Look.EMBOSS
	label.accent_base = NeuKit.MINT
	label.tracking = 0.5
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	label.bind_style(style)
	return button

func _reflow() -> void:
	if _content == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.y < 760.0
	_content.offset_left = 24.0
	_content.offset_right = -24.0
	_content.offset_top = 22.0 if compact else 36.0
	_content.offset_bottom = -22.0 if compact else -36.0
	_content.add_theme_constant_override("separation", 16 if compact else 22)
	_title.font_size = 52 if compact else 56
	_message.font_size = 30 if _message.text.length() > 175 or compact else 34
	_message.custom_minimum_size.y = 220.0 if compact else 250.0
	_primary_button.custom_minimum_size.y = 84.0 if compact else 92.0
	_secondary_button.custom_minimum_size.y = 78.0 if compact else 84.0

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
		_content.modulate.a = 1.0
		_content.scale = Vector2.ONE
	else:
		_content.modulate.a = 0.0
		_content.scale = Vector2(0.965, 0.965)
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_content, "modulate:a", 1.0, 0.24)
		_tween.tween_property(_content, "scale", Vector2.ONE, 0.30)
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
		_content.modulate.a = 1.0
		_content.scale = Vector2.ONE
		return
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_content, "scale", Vector2(0.98, 0.98), 0.15)
	_tween.tween_property(_content, "modulate:a", 0.0, 0.15)
	await _tween.finished
	visible = false
	_content.modulate.a = 1.0
	_content.scale = Vector2.ONE

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
