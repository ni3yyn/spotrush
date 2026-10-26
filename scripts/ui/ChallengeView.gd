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

var auto_confirm_tween: Tween = null

func lock_input() -> void:
	_ensure_nodes()
	is_input_locked = true
	if auto_confirm_tween != null and auto_confirm_tween.is_valid():
		auto_confirm_tween.kill()
	if challenge_canvas != null:
		challenge_canvas.is_interactive = false
	if btn_action_done != null:
		btn_action_done.disabled = true
	if options_container != null:
		for child in options_container.get_children():
			if child is Button:
				child.disabled = true

var _cached_styles: Dictionary = {}

func _get_cached_style(key: String, bg_col: Color, border_side: String = "", border_col: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	if not _cached_styles.has(key):
		var sb = StyleBoxFlat.new()
		sb.bg_color = bg_col
		sb.set_corner_radius_all(14)
		if border_side == "left":
			sb.border_width_left = border_w
			sb.border_color = border_col
		elif border_side == "right":
			sb.border_width_right = border_w
			sb.border_color = border_col
		elif border_side == "bottom":
			sb.border_width_bottom = border_w
			sb.border_color = border_col
		elif border_side == "all":
			sb.border_width_left = border_w
			sb.border_width_right = border_w
			sb.border_width_top = border_w
			sb.border_width_bottom = border_w
			sb.border_color = border_col
		_cached_styles[key] = sb
	return _cached_styles[key]

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
			
			# Contextual button styling with cached StyleBoxFlat reuse
			var style_normal: StyleBoxFlat
			var style_hover: StyleBoxFlat
			var style_pressed: StyleBoxFlat
			
			if str(opt).to_upper() == "YES":
				style_normal = _get_cached_style("yes_norm", GameConfig.COLOR_MINT)
				style_hover = _get_cached_style("yes_hov", GameConfig.COLOR_MINT_HOVER)
				style_pressed = _get_cached_style("yes_press", Color("85E2A9"))
				btn.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)
			elif str(opt).to_upper() == "NO":
				style_normal = _get_cached_style("no_norm", GameConfig.COLOR_ACCENT_RED)
				style_hover = _get_cached_style("no_hov", Color("FB7185"))
				style_pressed = _get_cached_style("no_press", Color("E11D48"))
				btn.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
			elif str(opt).to_upper() == "LEFT":
				style_normal = _get_cached_style("left_norm", GameConfig.COLOR_SURFACE, "left", GameConfig.COLOR_MINT, 3)
				style_hover = _get_cached_style("left_hov", GameConfig.COLOR_SURFACE_LIGHT)
				style_pressed = _get_cached_style("left_press", GameConfig.COLOR_MINT)
				btn.add_theme_color_override("font_color", GameConfig.COLOR_MINT)
			elif str(opt).to_upper() == "RIGHT":
				style_normal = _get_cached_style("right_norm", GameConfig.COLOR_SURFACE, "right", GameConfig.COLOR_ACCENT_YELLOW, 3)
				style_hover = _get_cached_style("right_hov", GameConfig.COLOR_SURFACE_LIGHT)
				style_pressed = _get_cached_style("right_press", GameConfig.COLOR_ACCENT_YELLOW)
				btn.add_theme_color_override("font_color", GameConfig.COLOR_ACCENT_YELLOW)
			else:
				# Estimation numerical choices
				style_normal = _get_cached_style("num_norm", GameConfig.COLOR_SURFACE, "bottom", GameConfig.COLOR_MINT, 3)
				style_hover = _get_cached_style("num_hov", GameConfig.COLOR_SURFACE_LIGHT)
				style_pressed = _get_cached_style("num_press", GameConfig.COLOR_MINT)
				btn.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
				
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
			btn_action_done.disabled = false
			var should_withhold = current_challenge.visual_data.get("should_withhold", false)
			if should_withhold:
				btn_action_done.text = "⛔ HOLD RESTRAINT — DO NOT TAP!"
				var style_inhibit = _get_cached_style("inhibit", Color("2A1616"), "all", Color("EF4444", 0.8), 2)
				btn_action_done.add_theme_stylebox_override("normal", style_inhibit)
				btn_action_done.add_theme_stylebox_override("hover", style_inhibit)
				btn_action_done.add_theme_stylebox_override("pressed", style_inhibit)
				btn_action_done.add_theme_color_override("font_color", Color("FCA5A5"))
			else:
				btn_action_done.text = "⚡ ALL CLEAR — TAP FAST NOW!"
				var style_tap = _get_cached_style("tap_clear", GameConfig.COLOR_MINT)
				btn_action_done.add_theme_stylebox_override("normal", style_tap)
				btn_action_done.add_theme_stylebox_override("hover", style_tap)
				btn_action_done.add_theme_stylebox_override("pressed", style_tap)
				btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)

func _update_action_done_label() -> void:
	if btn_action_done == null or current_challenge == null:
		return
	var target_count = current_challenge.visual_data.get("target_count", 0)
	if target_count > 0:
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(14)
		if tapped_indices.size() >= target_count:
			btn_action_done.text = "✓ CONFIRM ALL %d TARGETS" % target_count
			style.bg_color = GameConfig.COLOR_MINT
			btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)
		else:
			btn_action_done.text = "CONFIRM SELECTIONS (%d / %d TARGETS)" % [tapped_indices.size(), target_count]
			style.bg_color = GameConfig.COLOR_SURFACE_LIGHT
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_color = GameConfig.COLOR_MINT
			btn_action_done.add_theme_color_override("font_color", GameConfig.COLOR_TEXT_LIGHT)
		btn_action_done.add_theme_stylebox_override("normal", style)
		btn_action_done.add_theme_stylebox_override("hover", style)
	else:
		btn_action_done.text = "CONFIRM SELECTIONS"

func _on_option_button_pressed(val: Variant, btn: Button = null) -> void:
	if is_input_locked:
		return
	lock_input()
	
	if btn != null:
		var tw = create_tween()
		tw.set_trans(Tween.TRANS_QUAD)
		tw.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.07)
		
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
			if auto_confirm_tween != null and auto_confirm_tween.is_valid():
				auto_confirm_tween.kill()
			auto_confirm_tween = create_tween()
			auto_confirm_tween.tween_interval(0.15)
			auto_confirm_tween.tween_callback(func():
				if not is_input_locked:
					_on_action_done_pressed()
			)

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
