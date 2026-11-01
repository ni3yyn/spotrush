extends Control

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const NeuMenuBackdrop = preload("res://scripts/ui/NeuMenuBackdrop.gd")
const SpotRushButton = preload("res://scripts/ui/SpotRushButton.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")
const Feel = preload("res://scripts/core/Feel.gd")
const Settings = preload("res://scripts/core/Settings.gd")

const FAMILIES := [
	{"id": GameConfig.TYPE_ESTIMATION_COUNT, "title": "QUANTITY ESTIMATION", "detail": "Estimate how many objects you see."},
	{"id": GameConfig.TYPE_COMPARISON_SIDES, "title": "SIDE COMPARISON", "detail": "Choose the side with more or fewer."},
	{"id": GameConfig.TYPE_COLOR_TARGET, "title": "COLOR TARGET", "detail": "Find and tap the requested color."},
	{"id": GameConfig.TYPE_SHAPE_TARGET, "title": "SHAPE TARGET", "detail": "React to the requested shape."},
	{"id": GameConfig.TYPE_DONT_TAP, "title": "GO / NO-GO", "detail": "Act on targets; resist the forbidden ones."},
	{"id": GameConfig.TYPE_COMBINED_CONDITIONAL, "title": "CONDITIONAL RULES", "detail": "Apply a rule across multiple attributes."},
	{"id": GameConfig.TYPE_SIZE_ORDER, "title": "SIZE ORDER", "detail": "Identify the required size relationship."},
]

var _checks: Dictionary = {}
var _rounds: SpinBox
var _start: Button
var _status: Label
var _safe: MarginContainer

func _ready() -> void:
	BackNav.register(self)
	Music.play_menu()
	_build()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)

func _exit_tree() -> void:
	BackNav.unregister(self)

func handle_back() -> bool:
	if SceneRouter.is_transitioning:
		return true
	SceneRouter.goto_main_menu()
	return true

func _build() -> void:
	var backdrop := Control.new()
	backdrop.set_script(NeuMenuBackdrop)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)

	_safe = MarginContainer.new()
	_safe.name = "SafeArea"
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.add_theme_constant_override("margin_left", 22)
	_safe.add_theme_constant_override("margin_right", 22)
	_safe.add_theme_constant_override("margin_top", 28)
	_safe.add_theme_constant_override("margin_bottom", 24)
	add_child(_safe)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	_safe.add_child(page)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 54
	header.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(88, 52)
	SpotRushButton.configure(back, "BACK", {"font_size": 18, "radius": 20.0})
	back.pressed.connect(func(): SceneRouter.goto_main_menu())
	header.add_child(back)
	var title := Label.new()
	title.text = "BUILD YOUR RUN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	SpotRushTypography.apply_as(title, SpotRushTypography.Role.SCREEN_TITLE)
	title.add_theme_color_override("font_color", NeuKit.COBALT)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 88
	header.add_child(spacer)
	page.add_child(header)

	var intro := Label.new()
	intro.text = "CHOOSE THE CHALLENGE FAMILIES YOU WANT TO PLAY"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	SpotRushTypography.apply_as(intro, SpotRushTypography.Role.BODY)
	intro.add_theme_color_override("font_color", NeuKit.SLATE)
	page.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.name = "FamilyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var all_row := HBoxContainer.new()
	var family_heading := Label.new()
	family_heading.text = "CHALLENGE FAMILIES"
	family_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SpotRushTypography.apply_as(family_heading, SpotRushTypography.Role.SECTION_TITLE)
	all_row.add_child(family_heading)
	var all_btn := Button.new()
	all_btn.text = "SELECT ALL"
	SpotRushButton.configure(all_btn, "SELECT ALL", {"font_size": 15, "radius": 16.0})
	all_btn.custom_minimum_size = Vector2(112, 42)
	all_btn.pressed.connect(_select_all)
	all_row.add_child(all_btn)
	body.add_child(all_row)

	for family in FAMILIES:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", NeuKit.raised(18.0, 4.0, 8.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 3)
		var name_label := Label.new()
		name_label.text = str(family.title)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		SpotRushTypography.apply_as(name_label, SpotRushTypography.Role.BODY_STRONG)
		name_label.add_theme_color_override("font_color", NeuKit.INK)
		copy.add_child(name_label)
		var detail := Label.new()
		detail.text = str(family.detail)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		SpotRushTypography.apply_as(detail, SpotRushTypography.Role.CAPTION)
		detail.add_theme_color_override("font_color", NeuKit.SLATE)
		copy.add_child(detail)
		row.add_child(copy)
		var check := CheckBox.new()
		check.button_pressed = true
		check.custom_minimum_size = Vector2(56, 54)
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(_on_family_toggled)
		row.add_child(check)
		_checks[str(family.id)] = check
		body.add_child(card)

	var rounds_card := PanelContainer.new()
	rounds_card.add_theme_stylebox_override("panel", NeuKit.inset(18.0, 4.0, 8.0))
	var rounds_row := HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", 12)
	rounds_card.add_child(rounds_row)
	var rounds_copy := VBoxContainer.new()
	rounds_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rounds_title := Label.new()
	rounds_title.text = "NUMBER OF ROUNDS"
	SpotRushTypography.apply_as(rounds_title, SpotRushTypography.Role.SECTION_TITLE)
	rounds_copy.add_child(rounds_title)
	var rounds_hint := Label.new()
	rounds_hint.text = "%d–%d rounds per run" % [GameConfig.MIN_ROUNDS, GameConfig.MAX_ROUNDS]
	SpotRushTypography.apply_as(rounds_hint, SpotRushTypography.Role.CAPTION)
	rounds_hint.add_theme_color_override("font_color", NeuKit.SLATE)
	rounds_copy.add_child(rounds_hint)
	rounds_row.add_child(rounds_copy)
	_rounds = SpinBox.new()
	_rounds.min_value = GameConfig.MIN_ROUNDS
	_rounds.max_value = GameConfig.MAX_ROUNDS
	_rounds.step = 1
	_rounds.value = Settings.match_rounds()
	_rounds.custom_minimum_size = Vector2(116, 56)
	_rounds.add_theme_font_size_override("font_size", 25)
	_rounds.value_changed.connect(func(_value: float): _refresh_selection())
	rounds_row.add_child(_rounds)
	body.add_child(rounds_card)

	_status = Label.new()
	_status.text = "All families selected. Every run is freshly generated."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	SpotRushTypography.apply_as(_status, SpotRushTypography.Role.CAPTION)
	_status.add_theme_color_override("font_color", NeuKit.SLATE)
	body.add_child(_status)

	_start = Button.new()
	_start.text = "START CUSTOM RUN"
	_start.custom_minimum_size = Vector2(0, 68)
	SpotRushButton.configure(_start, "START CUSTOM RUN", {"font_size": 24, "radius": 24.0})
	_start.pressed.connect(_start_run)
	page.add_child(_start)
	_refresh_selection()

func _select_all() -> void:
	for check in _checks.values():
		(check as CheckBox).button_pressed = true
	_refresh_selection()

func _on_family_toggled(_pressed: bool) -> void:
	_refresh_selection()

func _refresh_selection() -> void:
	var count := 0
	for check in _checks.values():
		if (check as CheckBox).button_pressed:
			count += 1
	if is_instance_valid(_start):
		_start.disabled = count == 0
	if is_instance_valid(_status):
		_status.text = "%d of %d families selected · %d rounds" % [count, FAMILIES.size(), int(_rounds.value)] if count > 0 else "Select at least one family to start."

func _start_run() -> void:
	var selected: Array[String] = []
	for family in FAMILIES:
		var check: CheckBox = _checks[str(family.id)]
		if check.button_pressed:
			selected.append(str(family.id))
	if selected.is_empty():
		return
	var rounds := int(_rounds.value)
	if GameManager.queue_family_mode_start(rounds, selected):
		SceneRouter.goto_game()

func _apply_layout() -> void:
	if not is_instance_valid(_safe):
		return
	var narrow := get_viewport_rect().size.x < 430.0
	_safe.add_theme_constant_override("margin_left", 14 if narrow else 22)
	_safe.add_theme_constant_override("margin_right", 14 if narrow else 22)
