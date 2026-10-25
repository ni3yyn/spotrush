class_name ChallengeCanvas
extends Control

signal item_tapped(index: int, item_data: Dictionary)
signal side_tapped(side_name: String)

var current_challenge: ChallengeDefinition = null
var tapped_indices: Array[int] = []
var is_interactive: bool = true

# Animation state
var pulse_time: float = 0.0
var entrance_tween: Tween = null

# Visual Styling Tokens
const COLOR_CANVAS_BG: Color = Color("17231F")
const COLOR_PLAYFIELD_BORDER: Color = Color("2C4238")
const COLOR_DIVIDER: Color = Color("A8F0C6", 0.4)
const COLOR_MINT: Color = Color("A8F0C6")
const COLOR_MINT_GLOW: Color = Color("A8F0C6", 0.45)
const COLOR_WHITE: Color = Color("F8FAFC")
const COLOR_SHADOW: Color = Color(0, 0, 0, 0.3)

func _ready() -> void:
	custom_minimum_size = Vector2(280, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	pulse_time += delta
	# Subtle pulse for inhibit/withhold challenge trigger items or active rounds
	if current_challenge != null and current_challenge.input_mode == "withhold_response":
		queue_redraw()

func set_challenge(challenge: ChallengeDefinition) -> void:
	current_challenge = challenge
	tapped_indices.clear()
	is_interactive = true
	pulse_time = 0.0
	
	queue_redraw()
	
	# Tactile elastic scale entrance on the control node
	pivot_offset = size * 0.5 if size.x > 0 else Vector2(200, 200)
	scale = Vector2(0.94, 0.94)
	modulate.a = 0.7
	
	if entrance_tween != null and entrance_tween.is_valid():
		entrance_tween.kill()
		
	entrance_tween = create_tween()
	entrance_tween.set_parallel(true)
	entrance_tween.set_trans(Tween.TRANS_BACK)
	entrance_tween.set_ease(Tween.EASE_OUT)
	entrance_tween.tween_property(self, "scale", Vector2.ONE, 0.28)
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.18)

func set_item_tapped(index: int) -> void:
	if not index in tapped_indices:
		tapped_indices.append(index)
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not is_interactive or current_challenge == null:
		return
		
	var is_press = false
	var click_pos = Vector2.ZERO
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_press = true
		click_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		is_press = true
		click_pos = event.position
		
	if not is_press:
		return
		
	accept_event()
	
	# 1. Split view side-by-side touch dispatch
	if current_challenge.visual_data.get("split_view", false):
		var mid_x = size.x * 0.5
		if click_pos.x < mid_x:
			side_tapped.emit("LEFT")
		else:
			side_tapped.emit("RIGHT")
		return
		
	# 2. Tap targets selection mode
	if current_challenge.input_mode == "tap_targets":
		var items: Array = current_challenge.visual_data.get("items", [])
		var pad = 24.0
		var play_w = size.x - (pad * 2.0)
		var play_h = size.y - (pad * 2.0)
		
		# Check from last to first (topmost drawn item)
		for i in range(items.size() - 1, -1, -1):
			var it = items[i]
			var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
			var base_sz = float(it.get("size", 28.0))
			var touch_radius = maxf(base_sz * 0.9, 28.0)
			
			if click_pos.distance_to(center) <= touch_radius:
				if not i in tapped_indices:
					tapped_indices.append(i)
					item_tapped.emit(i, it)
					queue_redraw()
				return
		return
		
	# 3. Withhold response tap dispatch
	if current_challenge.input_mode == "withhold_response":
		side_tapped.emit("TAP")
		return

func _draw() -> void:
	if current_challenge == null or size.x <= 0 or size.y <= 0:
		return
		
	var pad = 24.0
	var play_w = size.x - (pad * 2.0)
	var play_h = size.y - (pad * 2.0)
	var is_split = current_challenge.visual_data.get("split_view", false)
	
	if is_split:
		_draw_split_view(pad, play_w, play_h)
	else:
		_draw_single_field(pad, play_w, play_h)

func _draw_split_view(pad: float, play_w: float, play_h: float) -> void:
	var mid_x = size.x * 0.5
	
	# Draw subtle background shading for left and right comparison zones
	var left_zone = Rect2(pad * 0.5, pad * 0.5, mid_x - (pad * 0.5) - 4.0, size.y - pad)
	var right_zone = Rect2(mid_x + 4.0, pad * 0.5, (size.x - mid_x) - (pad * 0.5) - 4.0, size.y - pad)
	draw_rect(left_zone, Color(0.133, 0.208, 0.173, 0.4), true, -1.0)
	draw_rect(right_zone, Color(0.133, 0.208, 0.173, 0.4), true, -1.0)
	
	# Draw glowing dividing line
	draw_line(Vector2(mid_x, pad + 10.0), Vector2(mid_x, size.y - pad - 10.0), COLOR_DIVIDER, 3.0, true)
	
	# Draw LEFT pill header with text
	var badge_w = 84.0
	var badge_h = 30.0
	var left_badge_rect = Rect2(mid_x * 0.5 - (badge_w * 0.5), pad + 6.0, badge_w, badge_h)
	draw_rect(left_badge_rect, Color(0.09, 0.14, 0.12, 0.9), true, -1.0)
	draw_rect(left_badge_rect, COLOR_MINT, false, 2.0)
	
	var default_font = ThemeDB.fallback_font
	draw_string(default_font, Vector2(left_badge_rect.position.x + 24.0, left_badge_rect.position.y + 20.0), "LEFT", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, COLOR_MINT)
	
	# Draw RIGHT pill header with text
	var right_badge_rect = Rect2(mid_x + (mid_x * 0.5) - (badge_w * 0.5), pad + 6.0, badge_w, badge_h)
	draw_rect(right_badge_rect, Color(0.09, 0.14, 0.12, 0.9), true, -1.0)
	draw_rect(right_badge_rect, GameConfig.COLOR_ACCENT_YELLOW, false, 2.0)
	draw_string(default_font, Vector2(right_badge_rect.position.x + 20.0, right_badge_rect.position.y + 20.0), "RIGHT", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, GameConfig.COLOR_ACCENT_YELLOW)
	
	# Draw Left items
	var left_items: Array = current_challenge.visual_data.get("left_items", [])
	for it in left_items:
		var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
		_draw_shape_item(center, it, false)
		
	# Draw Right items
	var right_items: Array = current_challenge.visual_data.get("right_items", [])
	for it in right_items:
		var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
		_draw_shape_item(center, it, false)

func _draw_single_field(pad: float, play_w: float, play_h: float) -> void:
	var items: Array = current_challenge.visual_data.get("items", [])
	
	for i in range(items.size()):
		var it = items[i]
		var center = Vector2(pad + (float(it["x"]) * play_w), pad + (float(it["y"]) * play_h))
		var is_tapped = (i in tapped_indices)
		_draw_shape_item(center, it, is_tapped)

func _draw_shape_item(center: Vector2, it: Dictionary, is_tapped: bool) -> void:
	var sz = float(it.get("size", 24.0))
	var col = _resolve_color(it.get("color", "MINT"))
	var shape = it.get("shape", "circle")
	
	# Subtle breathing pulse for Don't Tap trigger items
	if current_challenge.input_mode == "withhold_response" and it.get("color", "") == "RED":
		var pulse_scale = 1.0 + (sin(pulse_time * 6.0) * 0.1)
		sz *= pulse_scale
		
	# Draw drop shadow for tactile depth
	_draw_shape_primitive(shape, center + Vector2(0, 3.0), sz, COLOR_SHADOW)
	
	# Draw selection highlight glow if tapped
	if is_tapped:
		var glow_sz = sz * 1.45
		_draw_shape_primitive(shape, center, glow_sz, COLOR_MINT_GLOW)
		_draw_shape_primitive(shape, center, sz, COLOR_MINT)
		# Draw dark checkmark icon at center
		_draw_checkmark(center, sz * 0.5, COLOR_CANVAS_BG)
		return
		
	# Draw main shape
	_draw_shape_primitive(shape, center, sz, col)
	
	# Draw subtle specular outline for sharpness
	_draw_shape_outline(shape, center, sz, Color(1, 1, 1, 0.35), 1.5)

func _draw_shape_primitive(shape: String, center: Vector2, sz: float, col: Color) -> void:
	match shape:
		"circle":
			draw_circle(center, sz * 0.5, col)
		"square":
			var rect = Rect2(center - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz))
			draw_rect(rect, col, true, -1.0)
		"triangle":
			var half = sz * 0.5
			var p1 = center + Vector2(0, -half * 1.15)
			var p2 = center + Vector2(-half, half * 0.85)
			var p3 = center + Vector2(half, half * 0.85)
			draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)
		"diamond":
			var half = sz * 0.55
			var p1 = center + Vector2(0, -half)
			var p2 = center + Vector2(half, 0)
			var p3 = center + Vector2(0, half)
			var p4 = center + Vector2(-half, 0)
			draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), col)
		_:
			draw_circle(center, sz * 0.5, col)

func _draw_shape_outline(shape: String, center: Vector2, sz: float, col: Color, width: float) -> void:
	match shape:
		"circle":
			draw_arc(center, sz * 0.5, 0, TAU, 32, col, width, true)
		"square":
			var rect = Rect2(center - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz))
			draw_rect(rect, col, false, width)
		"triangle":
			var half = sz * 0.5
			var p1 = center + Vector2(0, -half * 1.15)
			var p2 = center + Vector2(-half, half * 0.85)
			var p3 = center + Vector2(half, half * 0.85)
			draw_polyline(PackedVector2Array([p1, p2, p3, p1]), col, width, true)
		"diamond":
			var half = sz * 0.55
			var p1 = center + Vector2(0, -half)
			var p2 = center + Vector2(half, 0)
			var p3 = center + Vector2(0, half)
			var p4 = center + Vector2(-half, 0)
			draw_polyline(PackedVector2Array([p1, p2, p3, p4]), col, width, true)
		_:
			draw_arc(center, sz * 0.5, 0, TAU, 32, col, width, true)

func _draw_checkmark(center: Vector2, sz: float, col: Color) -> void:
	var p1 = center + Vector2(-sz * 0.45, -sz * 0.05)
	var p2 = center + Vector2(-sz * 0.1, sz * 0.35)
	var p3 = center + Vector2(sz * 0.45, -sz * 0.35)
	draw_polyline(PackedVector2Array([p1, p2, p3]), col, maxf(3.0, sz * 0.22), true)

func _resolve_color(col_name: String) -> Color:
	match col_name.to_upper():
		"MINT": return GameConfig.COLOR_MINT
		"RED", "CORAL": return GameConfig.COLOR_ACCENT_RED
		"BLUE": return GameConfig.COLOR_ACCENT_BLUE
		"YELLOW", "AMBER": return GameConfig.COLOR_ACCENT_YELLOW
		"WHITE": return COLOR_WHITE
		_: return GameConfig.COLOR_MINT
