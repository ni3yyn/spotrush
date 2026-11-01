class_name PracticeCoach
extends Control

## Reusable first-time practice sheet. It intentionally lives outside Settings
## and uses the same soft neumorphic material as the rest of SpotRush.

signal choice_made(primary: bool)

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const Feel = preload("res://scripts/core/Feel.gd")

var _scrim: ColorRect
var _card: PanelContainer
var _card_style: NeuStyle
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
	_scrim = ColorRect.new()
	_scrim.color = Color(NeuKit.SURFACE.r, NeuKit.SURFACE.g, NeuKit.SURFACE.b, 0.96)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_style = NeuKit.raised(30.0, 12.0, 26.0)
	_card_style.content_margin_left = 24.0
	_card_style.content_margin_right = 24.0
	_card_style.content_margin_top = 24.0
	_card_style.content_margin_bottom = 24.0
	_card.add_theme_stylebox_override("panel", _card_style)
	center.add_child(_card)

	var margin := MarginContainer.new()
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	_title = NeuText.new()
	_title.custom_minimum_size = Vector2(0.0, 42.0)
	_title.font_size = 31
	_title.bold = true
	_title.color = NeuKit.INK
	_title.look = NeuText.Look.DEBOSS
	_title.align = HORIZONTAL_ALIGNMENT_CENTER
	SpotRushTypography.apply_as(_title, SpotRushTypography.Role.SCREEN_TITLE)
	column.add_child(_title)

	_message = NeuText.new()
	_message.custom_minimum_size = Vector2(0.0, 76.0)
	_message.font_size = 21
	_message.bold = false
	_message.color = NeuKit.SLATE
	_message.look = NeuText.Look.DEBOSS
	_message.align = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap = true
	_message.line_spacing = 6.0
	SpotRushTypography.apply_as(_message, SpotRushTypography.Role.BODY)
	column.add_child(_message)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	_secondary_button = _make_button("SKIP FOR NOW", false)
	_secondary_label = _secondary_button.get_child(0) as NeuText
	_secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_button.pressed.connect(_on_secondary_pressed)
	row.add_child(_secondary_button)

	_primary_button = _make_button("PRACTICE NOW", true)
	_primary_label = _primary_button.get_child(0) as NeuText
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.pressed.connect(_on_primary_pressed)
	row.add_child(_primary_button)

	_reflow()

func _make_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 64.0)
	button.focus_mode = Control.FOCUS_NONE
	var style: NeuStyle = NeuKit.style_button(button, "primary" if primary else "raised", 22.0)
	if primary:
		NeuKit.set_accent(button, NeuKit.COBALT)
	var label := NeuText.new()
	label.text = caption
	label.font_size = 17
	label.bold = true
	label.color = Color.WHITE if primary else NeuKit.INK
	label.look = NeuText.Look.ON_ACCENT if primary else NeuText.Look.DEBOSS
	label.accent_base = NeuKit.COBALT
	label.tracking = 0.7
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	label.bind_style(style)
	return button

func _reflow() -> void:
	if _card == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_card.custom_minimum_size = Vector2(maxf(260.0, minf(viewport_size.x - 44.0, 520.0)), 0.0)

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
	_card.pivot_offset = _card.size * 0.5
	if Feel.reduced():
		_scrim.modulate.a = 1.0
		_card.modulate.a = 1.0
		_card.scale = Vector2.ONE
		_card_style.depth = 0.85
	else:
		_scrim.modulate.a = 0.0
		_card.modulate.a = 0.0
		_card.scale = Vector2(0.955, 0.955)
		_card_style.depth = -0.18
		_kill_tween()
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_scrim, "modulate:a", 1.0, 0.20)
		_tween.tween_property(_card, "modulate:a", 1.0, 0.22)
		_tween.tween_property(_card, "scale", Vector2.ONE, 0.26)
		_tween.tween_property(_card_style, "depth", 0.85, 0.26)
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
		_card.modulate.a = 1.0
		_scrim.modulate.a = 1.0
		_card.scale = Vector2.ONE
		_card_style.depth = 0.85
		return
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_card, "scale", Vector2(0.975, 0.975), 0.15)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.15)
	_tween.tween_property(_scrim, "modulate:a", 0.0, 0.17)
	_tween.tween_property(_card_style, "depth", -0.18, 0.15)
	await _tween.finished
	visible = false
	_card.modulate.a = 1.0
	_scrim.modulate.a = 1.0
	_card.scale = Vector2.ONE
	_card_style.depth = 0.85

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
