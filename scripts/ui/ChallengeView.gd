extends Control

signal option_selected(option_val: Variant)
signal tap_item_clicked(index: int)

const ChallengeCanvasScript = preload("res://scripts/ui/ChallengeCanvas.gd")

@onready var challenge_canvas: Control = %ChallengeCanvas
@onready var options_container: HBoxContainer = %OptionsContainer
@onready var instruction_label: Label = %InstructionLabel
@onready var badge_label: Label = %BadgeLabel
@onready var btn_action_done: Button = %BtnActionDone

var current_challenge: ChallengeDefinition = null
var tapped_indices: Array[int] = []
var is_input_locked: bool = false

# Backwards compatibility accessor
var draw_canvas: Control:
	get:
		_ensure_nodes()
		return challenge_canvas

func _ready() -> void:
	_ensure_nodes()
	if challenge_canvas != null:
		if not challenge_canvas.item_tapped.is_connected(_on_canvas_item_tapped):
			challenge_canvas.item_tapped.connect(_on_canvas_item_tapped)
		if not challenge_canvas.side_tapped.is_connected(_on_canvas_side_tapped):
			challenge_canvas.side_tapped.connect(_on_canvas_side_tapped)
			
	if btn_action_done != null:
		if not btn_action_done.pressed.is_connected(_on_action_done_pressed):
			btn_action_done.pressed.connect(_on_action_done_pressed)
		btn_action_done.visible = false

func _ensure_nodes() -> void:
	if challenge_canvas == null and has_node("%ChallengeCanvas"):
		challenge_canvas = %ChallengeCanvas
	if instruction_label == null and has_node("%InstructionLabel"):
		instruction_label = %InstructionLabel
	if badge_label == null and has_node("%BadgeLabel"):
		badge_label = %BadgeLabel
	if options_container == null and has_node("%OptionsContainer"):
		options_container = %OptionsContainer
	if btn_action_done == null and has_node("%BtnActionDone"):
		btn_action_done = %BtnActionDone

func load_challenge(challenge: ChallengeDefinition) -> void:
	_ensure_nodes()
	current_challenge = challenge
	tapped_indices.clear()
	is_input_locked = false
	
	if instruction_label != null:
		instruction_label.text = challenge.instruction
	if badge_label != null:
		badge_label.text = _get_friendly_category_name(challenge.type)
		
	if challenge_canvas != null:
		challenge_canvas.set_challenge(challenge)
		
	_setup_options()

func lock_input() -> void:
	_ensure_nodes()
	is_input_locked = true
	if challenge_canvas != null:
		challenge_canvas.is_interactive = false
	if btn_action_done != null:
		btn_action_done.disabled = true
	if options_container != null:
		for child in options_container.get_children():
			if child is Button:
				child.disabled = true

func _setup_options() -> void:
	_ensure_nodes()
	if options_container == null:
		return
		
	for child in options_container.get_children():
		child.queue_free()
		
	if current_challenge == null:
		return
		
	if current_challenge.input_mode == "choice":
		if btn_action_done != null:
			btn_action_done.visible = false
			
		var opts = current_challenge.options
		for opt in opts:
			var btn = Button.new()
			btn.text = str(opt)
			btn.custom_minimum_size = Vector2(90, 64)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 22)
			
			var style_normal = StyleBoxFlat.new()
			var style_hover = StyleBoxFlat.new()
			var style_pressed = StyleBoxFlat.new()
			
			# Contextual button styling
			if str(opt).to_upper() == "YES":
				style_normal.bg_color = GameConfig.COLOR_MINT
				style_hover.bg_color = GameConfig.COLOR_MINT_HOVER
				style_pressed.bg_color = Color("85E2A9")
				btn.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)
			elif str(opt).to_upper() == "NO":
				style_normal.bg_color = GameConfig.COLOR_ACCENT_RED
				style_hover.bg_color = Color("FB7185")
				style_pressed.bg_color = Color("E11D48")
				btn.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
			elif str(opt).to_upper() == "LEFT":
				style_normal.bg_color = GameConfig.COLOR_SURFACE
				style_normal.border_width_left = 3
				style_normal.border_color = GameConfig.COLOR_MINT
				style_hover.bg_color = GameConfig.COLOR_SURFACE_LIGHT
				style_pressed.bg_color = GameConfig.COLOR_MINT
				btn.add_theme_color_override("font_color", GameConfig.COLOR_MINT)
			elif str(opt).to_upper() == "RIGHT":
				style_normal.bg_color = GameConfig.COLOR_SURFACE
				style_normal.border_width_right = 3
				style_normal.border_color = GameConfig.COLOR_ACCENT_YELLOW
				style_hover.bg_color = GameConfig.COLOR_SURFACE_LIGHT
				style_pressed.bg_color = GameConfig.COLOR_ACCENT_YELLOW
				btn.add_theme_color_override("font_color", GameConfig.COLOR_ACCENT_YELLOW)
			else:
				# Estimation numerical choices
				style_normal.bg_color = GameConfig.COLOR_SURFACE
				style_normal.border_width_bottom = 3
				style_normal.border_color = GameConfig.COLOR_MINT
				style_hover.bg_color = GameConfig.COLOR_SURFACE_LIGHT
				style_pressed.bg_color = GameConfig.COLOR_MINT
				btn.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
				
			style_normal.set_corner_radius_all(14)
			style_hover.set_corner_radius_all(14)
			style_pressed.set_corner_radius_all(14)
			
			btn.add_theme_stylebox_override("normal", style_normal)
			btn.add_theme_stylebox_override("hover", style_hover)
			btn.add_theme_stylebox_override("pressed", style_pressed)
			
			var opt_val = opt
			btn.pressed.connect(func(): _on_option_button_pressed(opt_val, btn))
			options_container.add_child(btn)
			
	elif current_challenge.input_mode == "tap_targets":
		if btn_action_done != null:
			btn_action_done.visible = true
			btn_action_done.disabled = false
			_update_action_done_label()
			
	elif current_challenge.input_mode == "withhold_response":
		if btn_action_done != null:
			btn_action_done.visible = true
			var should_withhold = current_challenge.visual_data.get("should_withhold", false)
			if should_withhold:
				btn_action_done.disabled = true
				btn_action_done.text = "⛔ INHIBIT ACTION — WAIT FOR TIMER"
				var style_inhibit = StyleBoxFlat.new()
				style_inhibit.bg_color = Color("381A1A")
				style_inhibit.border_width_left = 2
				style_inhibit.border_width_right = 2
				style_inhibit.border_color = Color("EF4444", 0.6)
				style_inhibit.set_corner_radius_all(14)
				btn_action_done.add_theme_stylebox_override("normal", style_inhibit)
				btn_action_done.add_theme_stylebox_override("disabled", style_inhibit)
				btn_action_done.add_theme_color_override("font_color", Color("FCA5A5"))
				btn_action_done.add_theme_color_override("font_disabled_color", Color("FCA5A5"))
			else:
				btn_action_done.disabled = false
				btn_action_done.text = "⚡ TAP FAST NOW!"
				var style_tap = StyleBoxFlat.new()
				style_tap.bg_color = GameConfig.COLOR_MINT
				style_tap.set_corner_radius_all(14)
				btn_action_done.add_theme_stylebox_override("normal", style_tap)
				btn_action_done.add_theme_stylebox_override("hover", style_tap)
				btn_action_done.add_theme_stylebox_override("pressed", style_tap)
				btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)

func _update_action_done_label() -> void:
	if btn_action_done == null or current_challenge == null:
		return
	var target_count = current_challenge.visual_data.get("target_count", 0)
	if target_count > 0:
		btn_action_done.text = "CONFIRM SELECTIONS (%d / %d TARGETS)" % [tapped_indices.size(), target_count]
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(14)
		if tapped_indices.size() >= target_count:
			style.bg_color = GameConfig.COLOR_MINT
			btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)
		else:
			style.bg_color = GameConfig.COLOR_SURFACE_LIGHT
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_color = GameConfig.COLOR_MINT
			btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
		btn_action_done.add_theme_stylebox_override("normal", style)
	else:
		btn_action_done.text = "CONFIRM SELECTIONS"

func _on_option_button_pressed(val: Variant, btn: Button = null) -> void:
	if is_input_locked:
		return
	lock_input()
	
	if btn != null:
		var tw = create_tween()
		tw.set_trans(Tween.TRANS_QUAD)
		tw.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08)
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08)
		
	option_selected.emit(val)

func _on_action_done_pressed() -> void:
	if is_input_locked:
		return
	lock_input()
	
	if current_challenge.input_mode == "tap_targets":
		option_selected.emit(tapped_indices)
	elif current_challenge.input_mode == "withhold_response":
		option_selected.emit("TAP")

func _on_canvas_item_tapped(index: int, _item: Dictionary) -> void:
	if is_input_locked or current_challenge == null:
		return
		
	if not index in tapped_indices:
		tapped_indices.append(index)
		tap_item_clicked.emit(index)
		_update_action_done_label()
		
		# Auto-confirm when all expected targets have been discovered
		var target_count = current_challenge.visual_data.get("target_count", 0)
		if target_count > 0 and tapped_indices.size() >= target_count:
			# Short delay for visual satisfaction of the last checkmark
			var tw = create_tween()
			tw.tween_interval(0.18)
			tw.tween_callback(func(): _on_action_done_pressed())

func _on_canvas_side_tapped(side_name: String) -> void:
	if is_input_locked or current_challenge == null:
		return
		
	if current_challenge.input_mode == "choice":
		_on_option_button_pressed(side_name)
	elif current_challenge.input_mode == "withhold_response":
		_on_action_done_pressed()

func _get_friendly_category_name(type: String) -> String:
	match type:
		GameConfig.TYPE_ESTIMATION_COUNT: return "ALMOST RIGHT • ESTIMATION"
		GameConfig.TYPE_COMPARISON_SIDES: return "WHICH SIDE • COMPARISON"
		GameConfig.TYPE_COLOR_TARGET: return "TARGET RUSH • COLOR"
		GameConfig.TYPE_SHAPE_TARGET: return "SHAPE HUNTER • GEOMETRY"
		GameConfig.TYPE_DONT_TAP: return "DON'T TAP • INHIBITION"
		GameConfig.TYPE_COMBINED_CONDITIONAL: return "BRAIN TWIST • CONDITIONAL"
		_: return type.replace("_", " ").to_upper()
