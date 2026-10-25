extends Control

signal option_selected(option_val: Variant)
signal tap_item_clicked(index: int)

@onready var draw_canvas: Control = %DrawCanvas
@onready var options_container: HBoxContainer = %OptionsContainer
@onready var instruction_label: Label = %InstructionLabel
@onready var badge_label: Label = %BadgeLabel
@onready var btn_action_done: Button = %BtnActionDone

var current_challenge: ChallengeDefinition = null
var tapped_indices: Array[int] = []
var is_input_locked: bool = false

func _ready() -> void:
	draw_canvas.draw.connect(_on_canvas_draw)
	draw_canvas.gui_input.connect(_on_canvas_gui_input)
	btn_action_done.pressed.connect(_on_action_done_pressed)
	btn_action_done.visible = false

func load_challenge(challenge: ChallengeDefinition) -> void:
	current_challenge = challenge
	tapped_indices.clear()
	is_input_locked = false
	
	instruction_label.text = challenge.instruction
	badge_label.text = challenge.type.replace("_", " ").to_upper()
	
	_setup_options()
	draw_canvas.queue_redraw()

func lock_input() -> void:
	is_input_locked = true
	btn_action_done.disabled = true
	for child in options_container.get_children():
		if child is Button:
			child.disabled = true

func _setup_options() -> void:
	for child in options_container.get_children():
		child.queue_free()
		
	if current_challenge == null:
		return
		
	if current_challenge.input_mode == "choice":
		btn_action_done.visible = false
		for opt in current_challenge.options:
			var btn = Button.new()
			btn.text = str(opt)
			btn.custom_minimum_size = Vector2(100, 64)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.theme_override_font_sizes["font_size"] = 22
			
			var style = StyleBoxFlat.new()
			style.bg_color = GameConfig.COLOR_MINT
			style.set_corner_radius_all(14)
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_color_override("font_color", GameConfig.COLOR_DEEP_GREEN)
			
			var opt_val = opt
			btn.pressed.connect(func(): _on_option_button_pressed(opt_val))
			options_container.add_child(btn)
			
	elif current_challenge.input_mode == "tap_targets":
		btn_action_done.visible = true
		btn_action_done.disabled = false
		btn_action_done.text = "CONFIRM SELECTIONS"
		
	elif current_challenge.input_mode == "withhold_response":
		btn_action_done.visible = true
		btn_action_done.disabled = false
		btn_action_done.text = "TAP HERE IF REQUIRED"

func _on_option_button_pressed(val: Variant) -> void:
	if is_input_locked:
		return
	lock_input()
	option_selected.emit(val)

func _on_action_done_pressed() -> void:
	if is_input_locked:
		return
	lock_input()
	if current_challenge.input_mode == "tap_targets":
		option_selected.emit(tapped_indices)
	elif current_challenge.input_mode == "withhold_response":
		option_selected.emit("TAP")

func _on_canvas_gui_input(event: InputEvent) -> void:
	if is_input_locked or current_challenge == null:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click_at(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_click_at(event.position)

func _handle_click_at(pos: Vector2) -> void:
	if current_challenge.input_mode != "tap_targets":
		if current_challenge.input_mode == "withhold_response":
			_on_action_done_pressed()
		return
		
	var items: Array = current_challenge.visual_data.get("items", [])
	var canvas_size: Vector2 = draw_canvas.size
	
	# Check from last to first (topmost)
	for i in range(items.size() - 1, -1, -1):
		var it = items[i]
		var item_pos = Vector2(it["x"] * canvas_size.x, it["y"] * canvas_size.y)
		var item_rad = float(it.get("size", 24.0)) * 0.9
		if pos.distance_to(item_pos) <= item_rad:
			if not i in tapped_indices:
				tapped_indices.append(i)
				tap_item_clicked.emit(i)
				draw_canvas.queue_redraw()
				
				# Check if all targets have been tapped
				var target_count = current_challenge.visual_data.get("target_count", 0)
				if target_count > 0 and tapped_indices.size() >= target_count:
					_on_action_done_pressed()
			break

func _on_canvas_draw() -> void:
	if current_challenge == null:
		return
		
	var canvas_size = draw_canvas.size
	var is_split = current_challenge.visual_data.get("split_view", false)
	
	if is_split:
		# Draw dividing line
		var mid_x = canvas_size.x * 0.5
		draw_line(Vector2(mid_x, 10), Vector2(mid_x, canvas_size.y - 10), Color(1, 1, 1, 0.2), 3.0)
		
		# Draw left items
		for it in current_challenge.visual_data.get("left_items", []):
			_draw_single_item(it, canvas_size, false)
			
		# Draw right items
		for it in current_challenge.visual_data.get("right_items", []):
			_draw_single_item(it, canvas_size, false)
	else:
		var items: Array = current_challenge.visual_data.get("items", [])
		for i in range(items.size()):
			var it = items[i]
			var is_tapped = (i in tapped_indices)
			_draw_single_item(it, canvas_size, is_tapped)

func _draw_single_item(it: Dictionary, canvas_size: Vector2, is_tapped: bool) -> void:
	var center = Vector2(it["x"] * canvas_size.x, it["y"] * canvas_size.y)
	var sz = float(it.get("size", 20.0))
	var col = _get_color_from_string(it.get("color", "MINT"))
	var shape = it.get("shape", "circle")
	
	if is_tapped:
		# Highlight tapped item with checkmark glow
		draw_circle(center, sz * 1.3, GameConfig.COLOR_MINT)
		col = GameConfig.COLOR_DEEP_GREEN
		
	match shape:
		"circle":
			draw_circle(center, sz * 0.5, col)
		"square":
			var rect = Rect2(center - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz))
			draw_rect(rect, col)
		"triangle":
			var p1 = center + Vector2(0, -sz * 0.5)
			var p2 = center + Vector2(-sz * 0.5, sz * 0.5)
			var p3 = center + Vector2(sz * 0.5, sz * 0.5)
			draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)
		_:
			draw_circle(center, sz * 0.5, col)

func _get_color_from_string(col_name: String) -> Color:
	match col_name.to_upper():
		"MINT": return GameConfig.COLOR_MINT
		"RED": return GameConfig.COLOR_ACCENT_RED
		"BLUE": return GameConfig.COLOR_ACCENT_BLUE
		"YELLOW", "AMBER": return GameConfig.COLOR_ACCENT_YELLOW
		"WHITE": return GameConfig.COLOR_TEXT_LIGHT
		_: return GameConfig.COLOR_MINT
