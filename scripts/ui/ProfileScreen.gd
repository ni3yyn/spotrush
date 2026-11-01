extends Control

const Records = preload("res://scripts/core/Records.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuSafe = preload("res://scripts/core/NeuSafe.gd")
const SpotRushSkin = preload("res://scripts/ui/SpotRushSkin.gd")
const SpotRushButton = preload("res://scripts/ui/SpotRushButton.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

var _content: VBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	SpotRushSkin.apply_screen(self, "profile")
	BackNav.register(self)
	NeuSafe.fit(self)
	_build_ui()
	_refresh()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = NeuKit.SURFACE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var safe := MarginContainer.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 24)
	safe.add_theme_constant_override("margin_right", 24)
	safe.add_theme_constant_override("margin_top", 20)
	safe.add_theme_constant_override("margin_bottom", 20)
	add_child(safe)
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 14)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(104, 62)
	SpotRushButton.configure(back, "BACK", {"font_size": 22, "radius": 20.0})
	back.pressed.connect(func(): Music.play_menu(); SceneRouter.goto_main_menu())
	header.add_child(back)
	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	header.add_child(title_col)
	var title := Label.new()
	title.text = "PLAYER PROFILE"
	title.add_theme_font_override("font", NeuKit.bold_font(title, 0.9))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", NeuKit.INK)
	title_col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Your performance, measured over completed runs."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", NeuKit.SLATE)
	title_col.add_child(subtitle)
	_scroll = ScrollContainer.new()
	_scroll.name = "ProfileScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "ProfileContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_scroll.add_child(_content)

func _refresh() -> void:
	for child in _content.get_children():
		child.queue_free()
	var data: Dictionary = Records.profile_summary()
	var hero := _card()
	var hero_col := VBoxContainer.new()
	hero_col.add_theme_constant_override("separation", 6)
	hero.add_child(hero_col)
	_add_label(hero_col, "ALL-TIME BEST SCORE", 19, NeuKit.SLATE)
	_add_label(hero_col, Records.format(int(data.best_score)), 54, NeuKit.COBALT)
	_add_label(hero_col, "%d completed runs  ·  %d rounds played" % [data.matches, data.rounds], 20, NeuKit.INK)
	_content.add_child(hero)
	_add_section_title("PERFORMANCE SUMMARY")
	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)
	var rounds := int(data.rounds)
	var accuracy := 100.0 * float(data.correct) / float(rounds) if rounds > 0 else 0.0
	_add_stat(grid, "ACCURACY", "%.1f%%" % accuracy, "%d correct of %d rounds" % [data.correct, rounds])
	_add_stat(grid, "AVERAGE RESPONSE", "%.2f s" % float(data.avg_rt) if float(data.avg_rt) > 0 else "—", "Across recorded valid responses")
	_add_stat(grid, "BEST STREAK", str(data.best_streak), "Most consecutive correct responses")
	_add_stat(grid, "INCORRECT", str(data.wrong), "Incorrect responses across recorded runs")
	_add_stat(grid, "TIMEOUTS", str(data.timeouts), "Rounds not answered in time")
	_add_stat(grid, "ROUNDS PLAYED", str(rounds), "Completed standard solo rounds")
	_add_section_title("GAMEPLAY SKILLS")
	var skills := GridContainer.new()
	skills.name = "SkillsGrid"
	skills.columns = 2
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills.add_theme_constant_override("h_separation", 12)
	skills.add_theme_constant_override("v_separation", 12)
	_content.add_child(skills)
	_add_stat(skills, "ACCURACY CONTROL", "%.1f%%" % accuracy, "Correct responses / completed rounds")
	_add_stat(skills, "RESPONSE TEMPO", "%.2f s" % float(data.avg_rt) if float(data.avg_rt) > 0 else "NOT ENOUGH DATA", "Mean of recorded valid response times")
	_add_stat(skills, "STREAK CONTROL", str(data.best_streak), "Longest recorded correct streak")
	_add_stat(skills, "RELIABILITY", "%.1f%%" % (100.0 * float(rounds - int(data.timeouts)) / float(rounds)) if rounds > 0 else "—", "Rounds completed without a timeout")
	_add_section_title("RECENT SCORES")
	var recent_card := _card()
	var recent_col := VBoxContainer.new()
	recent_col.add_theme_constant_override("separation", 10)
	recent_card.add_child(recent_col)
	var recent: Array = data.recent
	if recent.is_empty():
		_add_label(recent_col, "No completed standard runs yet. Play a solo match and your real results will appear here.", 21, NeuKit.SLATE)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		recent_col.add_child(row)
		var max_score := 1
		for value in recent:
			max_score = maxi(max_score, int(value))
		for i in recent.size():
			var value := int(recent[i])
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.min_value = 0
			bar.max_value = max_score
			bar.value = value
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.custom_minimum_size = Vector2(0, 44)
			bar.tooltip_text = "Run %d: %s points" % [i + 1, Records.format(value)]
			var fill := StyleBoxFlat.new()
			fill.bg_color = NeuKit.COBALT if i == recent.size() - 1 else NeuKit.SLATE.lerp(NeuKit.SURFACE, 0.25)
			fill.corner_radius_top_left = 12; fill.corner_radius_top_right = 12; fill.corner_radius_bottom_left = 12; fill.corner_radius_bottom_right = 12
			bar.add_theme_stylebox_override("fill", fill)
			var empty := StyleBoxFlat.new()
			empty.bg_color = NeuKit.SURFACE.darkened(0.035)
			empty.corner_radius_top_left = 12; empty.corner_radius_top_right = 12; empty.corner_radius_bottom_left = 12; empty.corner_radius_bottom_right = 12
			bar.add_theme_stylebox_override("background", empty)
			row.add_child(bar)
		_add_label(recent_col, "OLD  →  LATEST", 17, NeuKit.SLATE)
	var note := _card()
	_add_label(note, "These are game-performance statistics, not a psychological assessment. Reaction-time and cognitive-test measures will only appear after separately implemented, validated tasks collect them.", 19, NeuKit.SLATE)
	_content.add_child(note)
	_content.add_child(note)

func _layout() -> void:
	if _content == null: return
	var width := get_viewport_rect().size.x
	var side := 16 if width < 600 else 26
	var safe := get_node_or_null("SafeArea") as MarginContainer
	if safe:
		safe.add_theme_constant_override("margin_left", side)
		safe.add_theme_constant_override("margin_right", side)
	for grid_name in ["StatsGrid", "SkillsGrid"]:
		var grid := _content.get_node_or_null(grid_name)
		if grid is GridContainer:
			grid.columns = 2 if width >= 520 else 1

func _add_section_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", NeuKit.bold_font(label, 0.7))
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", NeuKit.SLATE)
	_content.add_child(label)

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", NeuKit.raised(24.0, 5.0, 12.0))
	card.add_theme_constant_override("margin_left", 22)
	card.add_theme_constant_override("margin_right", 22)
	card.add_theme_constant_override("margin_top", 18)
	card.add_theme_constant_override("margin_bottom", 18)
	return card

func _add_stat(parent: Control, caption: String, value: String, detail: String) -> void:
	var card := _card()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	_add_label(col, caption, 17, NeuKit.SLATE)
	_add_label(col, value, 32, NeuKit.COBALT)
	_add_label(col, detail, 17, NeuKit.INK)
	parent.add_child(card)

func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size >= 25:
		label.add_theme_font_override("font", NeuKit.bold_font(label, 0.45))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
