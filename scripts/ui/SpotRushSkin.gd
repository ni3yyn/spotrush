extends RefCounted

# Shared SpotRush visual language: soft-UI / neumorphic surfaces lit from the top-left.
# Every Button / Panel / ProgressBar / LineEdit in a screen is routed through NeuStyle
# (dual light+dark shadows, real inset states, animated click depth) by node name.
#
# Legacy constant names are kept so existing scripts keep compiling; they now map to the
# neumorphic palette defined in NeuKit (change SURFACE/LIGHT/DARK there to re-skin).

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

const INK: Color = NeuKit.INK
const MUTED: Color = NeuKit.SLATE
const CREAM: Color = NeuKit.SURFACE
const PAPER: Color = NeuKit.SURFACE
const INSET: Color = NeuKit.SURFACE
const BORDER: Color = Color("D2D9E6")
const WHITE: Color = Color("FFFFFF")
const COBALT: Color = NeuKit.COBALT
const COBALT_HOVER: Color = Color("3D63F3")
const COBALT_DARK: Color = Color("1A3BB2")
const CORAL: Color = NeuKit.CORAL
const LAVENDER: Color = NeuKit.LAVENDER
const CANARY: Color = NeuKit.CANARY
const MINT: Color = NeuKit.MINT
const SHADOW: Color = NeuKit.DARK

static func apply_screen(root: Control, screen: String = "default") -> void:
		if root == null:
				return
		root.add_theme_color_override("font_color", INK)
		_visit(root, screen)

static func make_feedback_style(correct: bool) -> StyleBoxFlat:
		# Typed StyleBoxFlat on purpose: GameScreen stores these as StyleBoxFlat.
		var tint := MINT if correct else CORAL
		return _flat(NeuKit.SURFACE.lerp(tint, 0.20), tint.lerp(WHITE, 0.45), 2, 24, Vector2(5, 7), 24)

static func make_timer_fill_style(state: String) -> StyleBoxFlat:
		var bg := COBALT
		var edge := Color("8FA6FF")
		var glow := Color(COBALT.r, COBALT.g, COBALT.b, 0.30)
		match state:
				"warn":
						bg = CANARY
						edge = Color("FFE29A")
						glow = Color(0.70, 0.48, 0.04, 0.26)
				"urgent":
						bg = CORAL
						edge = Color("FFC0C5")
						glow = Color(CORAL.r, CORAL.g, CORAL.b, 0.32)
		var style := _flat(bg, edge, 1, 6, Vector2(0, 2), 10)
		style.shadow_color = glow
		style.border_width_bottom = 0
		style.border_width_right = 0
		return style

static func _visit(node: Node, screen: String) -> void:
		if node is PanelContainer:
				_style_panel_container(node as PanelContainer, str(node.name), screen)
		elif node is Panel:
				_style_panel(node as Panel, str(node.name))
		elif node is CheckButton:
				pass # NeuSwitch draws itself; a plain CheckButton keeps the engine look.
		elif node is Button:
				_style_button(node as Button, str(node.name))
		elif node is ProgressBar:
				_style_progress(node as ProgressBar)
		elif node is LineEdit:
				_style_line_edit(node as LineEdit)
		elif node is TabContainer:
				_style_tabs(node as TabContainer)
		elif node is RichTextLabel:
				# [b] tags fall back to an ENGINE system font unless bold_font is provided.
				# Pin the bold face to the project font so every RichTextLabel stays on-brand.
				var rtl := node as RichTextLabel
				rtl.add_theme_font_override("bold_font", NeuKit.bold_font(rtl))
				if screen != "menu":
						rtl.add_theme_color_override("default_color", INK)
		elif node is Label:
				if screen != "menu":
						_style_label(node as Label)
				_etch_label(node as Label)

		for child in node.get_children():
				_visit(child, screen)

# --- panels --------------------------------------------------------------------------

static func _style_panel(panel: Panel, panel_name: String) -> void:
		if panel_name == "Background":
				panel.add_theme_stylebox_override("panel", _flat(NeuKit.SURFACE, NeuKit.SURFACE, 0, 0, Vector2.ZERO, 0))
		else:
				var s := NeuKit.raised(20.0, 6.0, 14.0)
				panel.add_theme_stylebox_override("panel", s)

static func _style_panel_container(panel: PanelContainer, panel_name: String, _screen: String) -> void:
		if panel_name in ["IconBadge", "Badge"]:
				_style_badge(panel)
				return
		var s: NeuStyle
		var h := 16.0
		var v := 10.0
		match panel_name:
				"TimerChip":
						s = NeuKit.raised(18.0, 4.0, 10.0)
						h = 10.0
						v = 5.0
				"StreakChip":
						s = NeuKit.raised(16.0, 4.0, 9.0, NeuKit.SURFACE.lerp(CANARY, 0.22))
						h = 10.0
						v = 5.0
				"CapsuleArcade", "StatsBox", "InstructionCard", "PillTimer", "PillScore", "P1", "P2", "RoundChip", "ScoreChip":
						s = NeuKit.inset(18.0, 4.0, 9.0)
				"ScoreWell", "CodeWell":
						# Deep readout wells: the personal-best value and the
						# Rival Codes challenge code live in the same sculpture.
						s = NeuKit.inset(26.0, 8.0, 20.0)
						h = 6.0
						v = 6.0
				"DailyCard":
						# The daily hub card: a raised tile between the wells and keys.
						s = NeuKit.raised(26.0, 9.0, 20.0)
						h = 20.0
						v = 14.0
				"IpWell":
						s = NeuKit.inset(20.0, 5.0, 11.0)
						h = 18.0
						v = 13.0
				"ModeTabs", "VisionTabs":
						# These wrap a row/grid of standalone key buttons, not a single
						# sculpted surface - a sunken tray behind them read as a second
						# (unclickable) control stacked under the real ones, and squeezed
						# the keys down to fill its tight margins. No panel body: just
						# pass the row/grid straight through at its own natural size.
						panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
						return
				"StatusPill":
						s = NeuKit.inset(22.0, 4.0, 9.0)
						h = 16.0
						v = 9.0
				"ChipP1", "ChipP2", "ChipYou":
						s = NeuKit.raised(20.0, 5.0, 11.0)
						h = 14.0
						v = 8.0
				"PlayFieldContainer":
						s = NeuKit.raised(30.0, 10.0, 24.0)
						h = 10.0
						v = 10.0
				"BoardContainer":
						s = NeuKit.inset(26.0, 8.0, 18.0)
				"ResultsCard", "FeedbackPanel", "HotspotGuide":
						s = NeuKit.raised(28.0, 11.0, 26.0)
				"HeroCard":
						s = NeuKit.raised(36.0, 14.0, 32.0)
						h = 30.0
						v = 26.0
				"GaugeCard", "ChartCard":
						s = NeuKit.raised(32.0, 12.0, 28.0)
						h = 24.0
						v = 22.0
				"NewBestChip":
						s = NeuKit.raised(20.0, 4.0, 9.0, NeuKit.SURFACE.lerp(CANARY, 0.28))
						h = 14.0
						v = 4.0
				"CountdownOverlay":
						s = NeuKit.accent(COBALT, 30.0, 10.0, 24.0)
				_:
						if panel_name.begins_with("StatTile"):
								s = NeuKit.inset(24.0, 6.0, 14.0)
								h = 18.0
								v = 10.0
						elif panel_name.begins_with("Modal"):
								s = NeuKit.raised(30.0, 13.0, 30.0)
						elif panel_name.begins_with("Rule"):
								s = NeuKit.inset(16.0, 4.0, 9.0)
						else:
								s = NeuKit.raised(22.0, 8.0, 18.0)
		s.content_margin_left = h
		s.content_margin_right = h
		s.content_margin_top = v
		s.content_margin_bottom = v
		panel.add_theme_stylebox_override("panel", s)

static func _style_badge(panel: PanelContainer) -> void:
		# Keep the badge's authored accent colour but make it a small raised, tinted tile.
		var col := LAVENDER
		var existing := panel.get_theme_stylebox("panel")
		if existing is StyleBoxFlat:
				col = (existing as StyleBoxFlat).bg_color
		elif existing is NeuStyle:
				col = (existing as NeuStyle).surface
		var s := NeuKit.accent(col, 16.0, 4.0, 10.0)
		s.content_margin_left = 0.0
		s.content_margin_right = 0.0
		s.content_margin_top = 0.0
		s.content_margin_bottom = 0.0
		panel.add_theme_stylebox_override("panel", s)

# --- buttons -------------------------------------------------------------------------

static func _style_button(button: Button, button_name: String) -> void:
		var primary := _is_primary(button_name)
		var kind := "primary" if primary else "raised"
		var font_color := WHITE if primary else INK
		var radius := 22.0
		match button_name:
				"BtnSolo":
						radius = 999.0
				"BtnMultiplayer", "BtnHowToPlay", "BtnProfile":
						radius = 999.0
				"BtnSettings":
						radius = 999.0
				"BtnRematch", "BtnMenu", "BtnCreateRoom", "BtnLaunchMatch", "BtnConnect", "BtnShareDaily":
						radius = 36.0
				"BtnStreak":
						kind = "well"
						radius = 999.0
						font_color = MUTED
		var s := NeuKit.style_button(button, kind, radius)
		if button_name == "BtnSolo":
				# The hero action floats highest.
				s.distance = 10.0
				s.blur = 22.0
				s.depth_hover = 1.15
		elif button_name in ["BtnMultiplayer", "BtnHowToPlay", "BtnStreak"]:
				# Secondary pills keep a tighter seat: a smaller cast shadow stops the
				# lower edge from reading as extra button body beneath the label.
				s.distance = 5.0
				s.blur = 12.0
		button.add_theme_color_override("font_color", font_color)
		button.add_theme_color_override("font_hover_color", font_color)
		button.add_theme_color_override("font_pressed_color", font_color)
		button.add_theme_color_override("font_hover_pressed_color", font_color)
		button.add_theme_color_override("font_focus_color", font_color)
		button.add_theme_color_override("font_disabled_color", Color(font_color.r, font_color.g, font_color.b, 0.45))
		button.add_theme_constant_override("h_separation", 10)
		button.add_theme_font_override("font", NeuKit.bold_font(button))

static func _is_primary(button_name: String) -> bool:
		return button_name in [
				"BtnSolo", "BtnRematch", "BtnCreateRoom", "BtnLaunchMatch", "BtnConnect",
				"BtnActionDone", "BtnCloseHowTo", "BtnCloseSettings", "BtnWifiLobby",
				"BtnPlayDaily", "BtnPlayMine"
		]

# --- labels --------------------------------------------------------------------------

static func _style_label(label: Label) -> void:
		# Labels nested directly within buttons can carry specific icon/brand colors.
		if label.get_parent() is Button:
				return
		var label_color := INK
		var label_name := str(label.name)
		if label_name == "LblCountdown":
				label_color = WHITE
		elif label_name in ["LblFeedback", "LblFeedbackDetail", "LblMiniFeedback"]:
				label_color = INK
		elif label_name in ["LblHostStatus", "LblJoinStatus", "LblCorrectStats", "LblCaption", "LblModeHint"]:
				# These labels carry live instructions/status; use readable secondary ink.
				label_color = NeuKit.SLATE
		elif label_name in ["LblRound", "LblScoreP1", "LblScoreP2", "LblTimer"]:
				label_color = COBALT
		elif label_name in ["LblHostIP", "LblPeerCount", "LblOutcome", "LblBestRound", "LobbyTitle", "LblJoinStatusBig"]:
				label_color = COBALT
		elif label_name == "LblStreak":
				label_color = Color("B8730F")
		elif label_name == "BadgeLabel":
				label_color = COBALT
				var chip := NeuKit.raised(16.0, 3.0, 8.0)
				chip.content_margin_left = 16.0
				chip.content_margin_right = 16.0
				chip.content_margin_top = 6.0
				chip.content_margin_bottom = 6.0
				label.add_theme_stylebox_override("normal", chip)
				SpotRushTypography.apply_as(label, SpotRushTypography.Role.MICRO)
		label.add_theme_color_override("font_color", label_color)

static func _etch_label(label: Label) -> void:
		# Dark text gets a light lip (letterpress); light text on accent surfaces a dark one.
		if str(label.name) in ["TokenToast", "LblCountdown"]:
				return
		var c := label.get_theme_color("font_color")
		NeuKit.etch(label, c.get_luminance() > 0.72)
		# Captions living inside keys get a bolder weight so they stay legible on the surface.
		if label.get_parent() is BoxContainer or label.get_parent() is Button:
				if label.get_theme_font_size("font_size") >= 15:
						label.add_theme_font_override("font", NeuKit.bold_font(label, 0.4))

# --- progress / inputs / tabs --------------------------------------------------------

static func _style_progress(progress: ProgressBar) -> void:
		var trough := NeuKit.inset(10.0, 2.5, 6.0)
		trough.content_margin_left = 0.0
		trough.content_margin_right = 0.0
		trough.content_margin_top = 0.0
		trough.content_margin_bottom = 0.0
		var fill := NeuKit.accent(COBALT, 10.0, 2.0, 5.0)
		fill.content_margin_left = 0.0
		fill.content_margin_right = 0.0
		fill.content_margin_top = 0.0
		fill.content_margin_bottom = 0.0
		progress.add_theme_stylebox_override("background", trough)
		progress.add_theme_stylebox_override("fill", fill)

static func _style_line_edit(line_edit: LineEdit) -> void:
		var normal := NeuKit.inset(16.0, 3.0, 8.0)
		normal.content_margin_left = 14.0
		normal.content_margin_right = 14.0
		var focus := NeuKit.inset(16.0, 3.0, 8.0)
		focus.depth = -1.05
		focus.content_margin_left = 14.0
		focus.content_margin_right = 14.0
		var read_only := NeuKit.raised(16.0, 2.0, 5.0)
		read_only.depth = 0.3
		line_edit.add_theme_stylebox_override("normal", normal)
		line_edit.add_theme_stylebox_override("focus", focus)
		line_edit.add_theme_stylebox_override("read_only", read_only)
		line_edit.add_theme_color_override("font_color", INK)
		line_edit.add_theme_color_override("font_placeholder_color", NeuKit.MUTED)
		line_edit.add_theme_color_override("caret_color", COBALT)
		line_edit.add_theme_color_override("selection_color", Color("AFC0FF"))

static func _style_tabs(tabs: TabContainer) -> void:
		tabs.add_theme_stylebox_override("panel", NeuKit.raised(20.0, 6.0, 14.0))
		tabs.add_theme_stylebox_override("tab_selected", NeuKit.inset(14.0, 3.0, 7.0))
		tabs.add_theme_stylebox_override("tab_unselected", NeuKit.raised(14.0, 3.0, 7.0))
		tabs.add_theme_stylebox_override("tab_hovered", NeuKit.raised(14.0, 4.0, 9.0))
		tabs.add_theme_stylebox_override("tab_focus", NeuKit.raised(14.0, 3.0, 7.0))
		tabs.add_theme_color_override("font_selected_color", COBALT)
		tabs.add_theme_color_override("font_unselected_color", INK)
		tabs.add_theme_color_override("font_hovered_color", COBALT)

static func _flat(bg: Color, border: Color, border_width: int, shadow_size: int, shadow_offset: Vector2, radius: int) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = bg
		style.set_border_width_all(border_width)
		style.border_color = border
		style.set_corner_radius_all(radius)
		style.shadow_color = SHADOW
		style.shadow_size = shadow_size
		style.shadow_offset = shadow_offset
		style.content_margin_left = 16.0
		style.content_margin_top = 10.0
		style.content_margin_right = 16.0
		style.content_margin_bottom = 10.0
		return style
