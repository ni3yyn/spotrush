class_name PracticeCoach
extends Control

## Full-screen, text-first practice guidance. The game backdrop remains visible;
## there is no scrim or modal card. Lesson content has distinct editorial roles:
## title -> context eyebrow -> live challenge instruction -> explanation -> actions.

signal choice_made(primary: bool)

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const SpotRushButton = preload("res://scripts/ui/SpotRushButton.gd")

var _content: VBoxContainer
var _title: NeuText
var _eyebrow: NeuText
var _instruction: NeuText
var _message: NeuText
var _primary_button: Button
var _secondary_button: Button
var _waiting_for_choice: bool = false
var _last_choice: bool = false
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if not resized.is_connected(_reflow):
		resized.connect(_reflow)
	if not get_viewport().size_changed.is_connected(_reflow):
		get_viewport().size_changed.connect(_reflow)
	visible = false

func _build() -> void:
	_content = VBoxContainer.new()
	_content.name = "TutorialContent"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 34.0
	_content.offset_top = 30.0
	_content.offset_right = -34.0
	_content.offset_bottom = -30.0
	_content.add_theme_constant_override("separation", 16)
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_content)

	_title = _new_text("TutorialTitle", 52, NeuKit.INK, true, NeuText.Look.EMBOSS)
	_title.custom_minimum_size = Vector2(0.0, 88.0)
	_content.add_child(_title)

	_eyebrow = _new_text("TutorialEyebrow", 24, NeuKit.COBALT, true, NeuText.Look.DEBOSS)
	_eyebrow.custom_minimum_size = Vector2(0.0, 34.0)
	_eyebrow.tracking = 2.0
	_eyebrow.visible = false
	_content.add_child(_eyebrow)

	_instruction = _new_text("TutorialInstruction", 38, NeuKit.INK, true, NeuText.Look.EMBOSS)
	_instruction.custom_minimum_size = Vector2(0.0, 88.0)
	_instruction.visible = false
	_content.add_child(_instruction)

	_message = _new_text("TutorialExplanation", 28, NeuKit.SLATE, false, NeuText.Look.EMBOSS)
	_message.custom_minimum_size = Vector2(0.0, 108.0)
	_message.line_spacing = 7.0
	_content.add_child(_message)

	var button_stack := VBoxContainer.new()
	button_stack.name = "TutorialActions"
	button_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_stack.add_theme_constant_override("separation", 12)
	_content.add_child(button_stack)

	_primary_button = _make_button("PRACTICE NOW", 88.0)
	_primary_button.pressed.connect(_on_primary_pressed)
	button_stack.add_child(_primary_button)

	_secondary_button = _make_button("SKIP FOR NOW", 88.0)
	_secondary_button.pressed.connect(_on_secondary_pressed)
	button_stack.add_child(_secondary_button)

	_reflow()

func _new_text(node_name: String, px: int, tint: Color, is_bold: bool, text_look: int) -> NeuText:
	var label := NeuText.new()
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.font_size = px
	label.bold = is_bold
	label.color = tint
	label.look = text_look
	label.align = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_button(caption: String, height: float) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	SpotRushButton.configure(button, caption, {
		"font_size": 30,
		"radius": 22.0,
	})
	return button

func _reflow() -> void:
	if _content == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.y < 760.0
	var side_margin: float = clampf(viewport_size.x * 0.055, 22.0, 48.0)
	_content.offset_left = side_margin
	_content.offset_right = -side_margin
	_content.offset_top = 22.0 if compact else 34.0
	_content.offset_bottom = -22.0 if compact else -34.0
	_content.add_theme_constant_override("separation", 12 if compact else 18)
	_title.font_size = 42 if compact else 48
	_eyebrow.font_size = 22 if compact else 24
	_instruction.font_size = 34 if compact else 40
	_message.font_size = 26 if compact else 28
	_title.custom_minimum_size.y = 78.0 if compact else 88.0
	_instruction.custom_minimum_size.y = 82.0 if compact else 96.0
	_message.custom_minimum_size.y = 96.0 if compact else 108.0
	_primary_button.custom_minimum_size.y = 82.0 if compact else 90.0
	_secondary_button.custom_minimum_size.y = 82.0 if compact else 90.0

func present(title_text: String, message_text: String, primary_text: String,
		secondary_text: String = "SKIP FOR NOW") -> bool:
	_eyebrow.visible = false
	_instruction.visible = false
	_message.visible = true
	_message.text = message_text
	return await _present_common(title_text, primary_text, secondary_text)

## First-time lessons keep the actual instruction visually separate from the
## supporting explanation. This also prevents format placeholders from leaking
## into the screen when a family-specific challenge rule changes.
func _contains_unresolved_token(value: String) -> bool:
	return value.contains("%s") or value.contains("%d") or value.contains("%f") or value.contains("%02d")

func present_lesson(title_text: String, instruction_text: String, explanation_text: String,
		primary_text: String, secondary_text: String = "SKIP FOR NOW") -> bool:
	_eyebrow.text = "FIRST-TIME PRACTICE"
	_eyebrow.visible = true
	var safe_instruction := instruction_text.strip_edges()
	if _contains_unresolved_token(safe_instruction):
		safe_instruction = "READ THE RULE, THEN MAKE YOUR CHOICE."
	_instruction.text = safe_instruction
	_instruction.visible = not safe_instruction.is_empty()
	var safe_explanation := explanation_text
	if _contains_unresolved_token(safe_explanation):
		safe_explanation = "Try one unscored example. The real round starts after you finish."
	_message.text = safe_explanation
	_message.visible = not safe_explanation.is_empty()
	return await _present_common(title_text, primary_text, secondary_text)

func _present_common(title_text: String, primary_text: String, secondary_text: String) -> bool:
	_title.text = title_text
	_primary_button.text = primary_text
	_secondary_button.visible = not secondary_text.is_empty()
	if _secondary_button.visible:
		_secondary_button.text = secondary_text
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
