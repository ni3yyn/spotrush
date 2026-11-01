extends Control

signal option_selected(option_val: Variant)
signal tap_item_clicked(index: int)

const ChallengeCanvasScript = preload("res://scripts/ui/ChallengeCanvas.gd")
const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const NeuText = preload("res://scripts/ui/NeuText.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const SpotRushButton = preload("res://scripts/ui/SpotRushButton.gd")

@onready var challenge_canvas: ChallengeCanvas = %ChallengeCanvas
@onready var options_container: HBoxContainer = %OptionsContainer
@onready var instruction_label: NeuText = %InstructionLabel
@onready var badge_label: Label = %BadgeLabel
@onready var btn_action_done: Button = %BtnActionDone

var current_challenge: ChallengeDefinition = null
var tapped_indices: Array[int] = []
var is_input_locked: bool = false
var entrance_tween: Tween = null

# Backwards compatibility accessor
var draw_canvas: Control:
		get:
				_ensure_nodes()
				return challenge_canvas

func _ready() -> void:
		SpotRushSkin.apply_screen(self, "game")
		_polish_challenge_surfaces()
		_ensure_nodes()
		_wire_challenge_canvas()
						
		if btn_action_done != null:
				if not btn_action_done.pressed.is_connected(_on_action_done_pressed):
						btn_action_done.pressed.connect(_on_action_done_pressed)
				btn_action_done.visible = false

func _wire_challenge_canvas() -> void:
		if challenge_canvas == null:
				return
		if not challenge_canvas.item_tapped.is_connected(_on_canvas_item_tapped):
				challenge_canvas.item_tapped.connect(_on_canvas_item_tapped)
		if not challenge_canvas.side_tapped.is_connected(_on_canvas_side_tapped):
				challenge_canvas.side_tapped.connect(_on_canvas_side_tapped)

func _polish_challenge_surfaces() -> void:
		var instruction_card := get_node_or_null("VBoxContent/InstructionCard") as PanelContainer
		if instruction_card != null:
				var instruction_style := instruction_card.get_theme_stylebox("panel") as NeuStyle
				if instruction_style != null:
						instruction_style.depth = -0.55
						instruction_style.gradient = 0.30
						_soft_surface(instruction_style, 0.44, 0.36, 0.0)
		var playfield_card := get_node_or_null("VBoxContent/PlayFieldContainer") as PanelContainer
		if playfield_card != null:
				var playfield_style := playfield_card.get_theme_stylebox("panel") as NeuStyle
				if playfield_style != null:
						playfield_style.depth = 0.65
						playfield_style.distance = 7.0
						playfield_style.blur = 20.0
						playfield_style.gradient = 0.35
						_soft_surface(playfield_style, 0.38, 0.32, 0.32)
		var category_badge := get_node_or_null("VBoxContent/BadgeContainer/BadgeLabel") as Label
		if category_badge != null:
				var badge_style := category_badge.get_theme_stylebox("normal") as NeuStyle
				if badge_style != null:
						badge_style.surface = NeuKit.SURFACE.lerp(NeuKit.COBALT, 0.035)
						badge_style.depth = 0.40
						badge_style.gradient = 0.28
						_soft_surface(badge_style, 0.44, 0.32, 0.35)

func _soft_surface(style: NeuStyle, light_alpha: float, dark_alpha: float, rim_strength: float) -> void:
		if style == null:
				return
		style.light = Color(1.0, 1.0, 1.0, light_alpha)
		style.dark = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, dark_alpha)
		style.rim = rim_strength
		style.emit_changed()

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

func load_challenge(challenge: ChallengeDefinition, animate: bool = true) -> void:
		_ensure_nodes()
		_wire_challenge_canvas()
		current_challenge = challenge
		if auto_confirm_tween != null and auto_confirm_tween.is_valid():
			auto_confirm_tween.kill()
		auto_confirm_tween = null
		tapped_indices.clear()
		is_input_locked = false
		
		if instruction_label != null:
				instruction_label.text = challenge.instruction
		if badge_label != null:
				badge_label.text = _get_friendly_category_name(challenge.type)
				
		if challenge_canvas != null:
				# Every token-picking family uses the same canvas hit-test and tap_targets path.
				challenge_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
				challenge_canvas.set_challenge(challenge, animate)
		
		_setup_options()
		if animate:
				call_deferred("play_entry_animation")

func play_entry_animation() -> void:
		if not is_inside_tree() or Feel.reduced():
				return
		if entrance_tween != null and entrance_tween.is_valid():
				entrance_tween.kill()
		# Give the full level a brief tactile arrival, including challenge types that
		# use a split tray or have too many tokens for the per-token wave.
		scale = Vector2(0.975, 0.975)
		modulate.a = 0.82
		entrance_tween = create_tween()
		entrance_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		entrance_tween.set_parallel(true)
		entrance_tween.tween_property(self, "scale", Vector2.ONE, 0.26)
		entrance_tween.tween_property(self, "modulate:a", 1.0, 0.20)
		if options_container != null and options_container.visible:
				for i in range(options_container.get_child_count()):
						var child: Control = options_container.get_child(i) as Control
						if child == null:
								continue
						child.modulate.a = 0.0
						child.position.y += 8.0
						var button_tween := create_tween()
						button_tween.tween_interval(float(i) * 0.045)
						button_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
						button_tween.set_parallel(true)
						button_tween.tween_property(child, "modulate:a", 1.0, 0.18)
						button_tween.tween_property(child, "position:y", child.position.y - 8.0, 0.22)

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
								if not child.has_meta("chosen"):
										child.modulate = Color(1.0, 1.0, 1.0, 0.55)

## Release the round's input lock WITHOUT reloading the challenge. Used when the
## round was already dealt behind the transition curtain, so the round start
## doesn't re-render the playfield or replay its entrance.
func unlock_input() -> void:
		_ensure_nodes()
		is_input_locked = false
		if challenge_canvas != null:
				challenge_canvas.is_interactive = true
		if btn_action_done != null:
				btn_action_done.disabled = false
		if options_container != null:
				for child in options_container.get_children():
						if child is Button:
								child.disabled = false
								if not child.has_meta("chosen"):
										child.modulate = Color.WHITE

func _setup_options() -> void:
		_ensure_nodes()
		if options_container == null:
				return
				
		for child in options_container.get_children():
				child.queue_free()
				
		if current_challenge == null:
				return
		# Tap / withhold rounds have no answer keys; give that space back to the play field.
		options_container.visible = current_challenge.input_mode == "choice"
				
		if current_challenge.input_mode == "choice":
				if btn_action_done != null:
						btn_action_done.visible = false
						
				for opt in current_challenge.options:
						var btn := _make_option_button(opt)
						var opt_val = opt
						btn.pressed.connect(func(): _on_option_button_pressed(opt_val, btn))
						options_container.add_child(btn)
						
		elif current_challenge.input_mode == "tap_targets":
				if btn_action_done != null:
						# Size Order completes automatically after the final shape, just
						# like the existing target-selection families. It must not depend
						# on a separate confirmation control.
						var uses_auto_completion := current_challenge.type == GameConfig.TYPE_SIZE_ORDER
						btn_action_done.visible = not uses_auto_completion
						btn_action_done.disabled = false
						if not btn_action_done.pressed.is_connected(_on_action_done_pressed):
							btn_action_done.pressed.connect(_on_action_done_pressed)
						if not uses_auto_completion:
							_update_action_done_label()

		elif current_challenge.input_mode == "withhold_response":
				if btn_action_done != null:
						btn_action_done.visible = true
						btn_action_done.disabled = false
						# v16: the confirm key no longer reveals whether RED is
						# actually on the field - scanning for the trigger is the
						# whole challenge now, so the label stays state-agnostic.
						btn_action_done.text = RuleBook.GONOGO_KEY_LABEL
						_set_action_look("go")

## Every in-round action uses the same neutral raised key as the lobby tabs.
func _set_action_look(_kind: String) -> void:
		if btn_action_done == null:
			return
		SpotRushButton.set_selected(btn_action_done, false)
		btn_action_done.modulate = Color.WHITE

func _make_option_button(opt: Variant) -> Button:
		var btn := Button.new()
		btn.set_meta("val", opt)
		btn.custom_minimum_size = Vector2(90, 104)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		SpotRushButton.configure(btn, str(opt), {
				"font_size": 30,
				"radius": 22.0,
		})
		return btn

func _get_tap_target_count() -> int:
		if current_challenge == null:
			return 0
		var target_count: int = int(current_challenge.visual_data.get("target_count", 0))
		if target_count <= 0 and current_challenge.input_mode == "tap_targets":
			target_count = maxi(0, int(current_challenge.correct_answer))
			if target_count <= 0:
				var items: Array = current_challenge.visual_data.get("items", [])
				target_count = items.size()
		return target_count

func _update_action_done_label() -> void:
		if btn_action_done == null or current_challenge == null:
			return
		var target_count: int = _get_tap_target_count()
		if target_count > 0:
			if tapped_indices.size() >= target_count:
				btn_action_done.text = "CONFIRM ALL %d TARGETS" % target_count
				_set_action_look("complete")
			else:
				btn_action_done.text = "CONFIRM SELECTIONS (%d / %d TARGETS)" % [tapped_indices.size(), target_count]
				_set_action_look("pending")
		else:
			btn_action_done.text = "CONFIRM SELECTIONS"
			_set_action_look("pending")

func _on_option_button_pressed(val: Variant, btn: Button = null) -> void:
		if is_input_locked:
				return
		if btn == null and options_container != null:
				for child in options_container.get_children():
						if child is Button and str((child as Button).get_meta("val", "")).to_upper() == str(val).to_upper():
								btn = child
								break
		if btn != null:
				btn.set_meta("chosen", true)
				SpotRushButton.set_selected(btn, true)
		lock_input()
		option_selected.emit(val)

func _on_action_done_pressed() -> void:
		if is_input_locked or current_challenge == null:
			return

		if current_challenge.input_mode == "tap_targets":
			lock_input()
			if OS.is_debug_build() and current_challenge.type == GameConfig.TYPE_SIZE_ORDER:
				print("[SIZE ORDER] completed tap order=%s" % [tapped_indices])
			option_selected.emit(tapped_indices.duplicate())
		elif current_challenge.input_mode == "withhold_response":
			lock_input()
			option_selected.emit("TAP")

func _on_canvas_item_tapped(index: int, _item: Dictionary) -> void:
		if is_input_locked or current_challenge == null:
			return
		if current_challenge.input_mode != "tap_targets":
			return

		var items: Array = current_challenge.visual_data.get("items", [])
		if index < 0 or index >= items.size():
			return

		# Selection and deselection are shared by all token families. Size Order
		# records the order in which shapes were tapped; the shared completion
		# quota commits the selection once every shape has been chosen.
		if index in tapped_indices:
			tapped_indices.erase(index)
			challenge_canvas.set_item_selected(index, false)
			if auto_confirm_tween != null and auto_confirm_tween.is_valid():
				auto_confirm_tween.kill()
			auto_confirm_tween = null
			_update_action_done_label()
			return

		tapped_indices.append(index)
		challenge_canvas.set_item_selected(index, true)
		if OS.is_debug_build() and current_challenge.type == GameConfig.TYPE_SIZE_ORDER:
			print("[SIZE ORDER] selected index=%d progress=%d/%d" % [index, tapped_indices.size(), _get_tap_target_count()])
		tap_item_clicked.emit(index)
		_update_action_done_label()

		# Every tap-target family completes through the same selection quota.
		# Size Order differs only in the rule that validates tap order, not in
		# how its input is committed. No confirmation button is required.
		var target_count: int = _get_tap_target_count()
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
				GameConfig.TYPE_SIZE_ORDER: return "SIZE RUSH • ORDER"
				_: return type.replace("_", " ").to_upper()
