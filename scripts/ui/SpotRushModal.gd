extends RefCounted
class_name SpotRushModal

## Shared, explicit modal anatomy:
##   ModalHeader -> ModalBodyScroll/ModalBody -> ModalFooter
## Every modal owns the same shell, spacing, typography, and wide action treatment.
## Existing named controls are kept alive; only their parent containers change.
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuStyle = preload("res://scripts/ui/NeuStyle.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

static func apply(modal: Control, header_node_names: Array, footer_button_names: Array, compact: bool = false) -> void:
	if modal == null or not is_instance_valid(modal):
		return
	var margin := modal.get_node_or_null("Margin") as MarginContainer
	var vbox := modal.get_node_or_null("Margin/VBox") as VBoxContainer
	if margin == null or vbox == null:
		push_warning("SpotRushModal: missing Margin/VBox on %s" % modal.name)
		return

	var header := vbox.get_node_or_null("ModalHeader") as VBoxContainer
	var body_scroll := vbox.get_node_or_null("ModalBodyScroll") as ScrollContainer
	var body := vbox.get_node_or_null("ModalBodyScroll/ModalBody") as VBoxContainer
	var footer := vbox.get_node_or_null("ModalFooter") as VBoxContainer

	if header == null or body_scroll == null or body == null or footer == null:
		# Snapshot the original children before creating the semantic sections.
		var original_children := vbox.get_children()
		header = VBoxContainer.new()
		header.name = "ModalHeader"
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		header.add_theme_constant_override("separation", 6)

		body_scroll = ScrollContainer.new()
		body_scroll.name = "ModalBodyScroll"
		body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_scroll.size_flags_stretch_ratio = 1.0
		body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		body_scroll.follow_focus = true
		body_scroll.clip_contents = true

		body = VBoxContainer.new()
		body.name = "ModalBody"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		body.add_theme_constant_override("separation", 12)
		body_scroll.add_child(body)

		footer = VBoxContainer.new()
		footer.name = "ModalFooter"
		footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical = Control.SIZE_SHRINK_END
		footer.add_theme_constant_override("separation", 10)

		for child in original_children:
			vbox.remove_child(child)
		var header_divider := _make_divider("ModalHeaderDivider")
		var footer_divider := _make_divider("ModalFooterDivider")
		vbox.add_child(header)
		vbox.add_child(header_divider)
		vbox.add_child(body_scroll)
		vbox.add_child(footer_divider)
		vbox.add_child(footer)

		for child in original_children:
			if header_node_names.has(String(child.name)):
				header.add_child(child)
			elif footer_button_names.has(String(child.name)):
				footer.add_child(child)
			else:
				body.add_child(child)
	else:
		# Idempotent path: a repeated responsive pass never reparents content twice.
		for button_name in footer_button_names:
			var button := _find(modal, button_name) as Button
			# A footer action may live inside a nested HBox (for example the two
			# Rival Code choices). Preserve that grouping on every repeat apply.
			if button != null and not footer.is_ancestor_of(button):
				button.reparent(footer, false)

	modal.set_meta("spotrush_modal_shell", true)
	_apply_geometry(modal, compact)
	_apply_typography(modal)
	_apply_panel_style(modal)

static func find(modal: Node, node_name: String) -> Node:
	return _find(modal, node_name)

static func set_compact(modal: Control, compact: bool) -> void:
	if modal == null or not modal.has_meta("spotrush_modal_shell"):
		return
	_apply_geometry(modal, compact)

static func _find(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == StringName(node_name):
		return root
	return root.find_child(node_name, true, false)

static func _apply_geometry(modal: Control, compact: bool) -> void:
	var margin := modal.get_node_or_null("Margin") as MarginContainer
	var vbox := modal.get_node_or_null("Margin/VBox") as VBoxContainer
	var header := modal.get_node_or_null("Margin/VBox/ModalHeader") as VBoxContainer
	var body := modal.get_node_or_null("Margin/VBox/ModalBodyScroll/ModalBody") as VBoxContainer
	var footer := modal.get_node_or_null("Margin/VBox/ModalFooter") as VBoxContainer
	var body_scroll := modal.get_node_or_null("Margin/VBox/ModalBodyScroll") as ScrollContainer
	var header_divider := modal.get_node_or_null("Margin/VBox/ModalHeaderDivider") as ColorRect
	var footer_divider := modal.get_node_or_null("Margin/VBox/ModalFooterDivider") as ColorRect
	if margin == null or vbox == null or header == null or body == null or footer == null or body_scroll == null:
		return

	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	var viewport_size := modal.get_viewport_rect().size
	var narrow := viewport_size.x < 560.0
	var tight := compact or viewport_size.y < 1120.0
	var side_margin := 12 if narrow else (18 if compact else 22)
	margin.add_theme_constant_override("margin_left", side_margin)
	margin.add_theme_constant_override("margin_right", side_margin)
	margin.add_theme_constant_override("margin_top", 10 if tight else 16)
	margin.add_theme_constant_override("margin_bottom", 10 if tight else 16)
	vbox.add_theme_constant_override("separation", 8 if tight else 12)
	header.add_theme_constant_override("separation", 5 if tight else 8)
	body.add_theme_constant_override("separation", 8 if tight else 11)
	footer.add_theme_constant_override("separation", 7 if tight else 10)
	if header_divider != null:
		var header_line_color := header_divider.color
		header_line_color.a = 0.10 if compact else 0.14
		header_divider.color = header_line_color
	if footer_divider != null:
		var footer_line_color := footer_divider.color
		footer_line_color.a = 0.12 if compact else 0.16
		footer_divider.color = footer_line_color
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.custom_minimum_size.y = 100.0 if tight else 136.0
	body_scroll.size_flags_stretch_ratio = 1.0
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var vertical_bar := body_scroll.get_v_scroll_bar()
	if vertical_bar != null:
		vertical_bar.visible = false
	var horizontal_bar := body_scroll.get_h_scroll_bar()
	if horizontal_bar != null:
		horizontal_bar.visible = false
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.size_flags_vertical = Control.SIZE_SHRINK_END

	# Size every button in the modal, not only footer children. Nested controls
	# such as Rival Code's COPY / NEW actions must never collapse to text width.
	for node in _all_controls(modal):
		if node is LineEdit or node is TextEdit:
			var field := node as Control
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.custom_minimum_size.y = maxf(field.custom_minimum_size.y, 64.0 if not tight else 58.0)
			continue
		if not (node is Button):
			continue
		var button := node as Button
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.size_flags_stretch_ratio = 1.0
		button.custom_minimum_size.x = 0.0
		var min_height := 72.0 if not tight else 64.0
		if button.name in ["BtnWifiLobby", "BtnPassPlay", "BtnChallengeCode"]:
			min_height = 96.0 if not tight else 88.0
		elif button.name in ["BtnPlayMine", "BtnPlayFriend"]:
			min_height = 72.0 if not tight else 68.0
		elif button.name == "BtnPlayDaily":
			min_height = 96.0 if not tight else 88.0
		elif button.name in ["BtnCopyCode", "BtnNewCode"]:
			min_height = 64.0 if not tight else 58.0
		elif button.name == "BtnShareDaily":
			min_height = 68.0 if not tight else 62.0
		elif String(button.name).begins_with("BtnClose"):
			min_height = 60.0 if not tight else 56.0
		button.custom_minimum_size.y = min_height
		button.focus_mode = Control.FOCUS_ALL

static func _make_divider(node_name: String) -> ColorRect:
	var divider := ColorRect.new()
	divider.name = node_name
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	divider.color = Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.12)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider

static func _apply_panel_style(modal: Control) -> void:
	var card := modal as PanelContainer
	if card == null:
		return
	var style := card.get_theme_stylebox("panel") as NeuStyle
	if style != null:
		style.corner_radius = 32.0
		style.distance = 11.0
		style.blur = 24.0
		style.rim = 0.80
		style.emit_changed()

static func _apply_typography(modal: Control) -> void:
	for node in _all_controls(modal):
		var control := node as Control
		var node_name := String(control.name)
		if control is Button:
			var role := SpotRushTypography.Role.BUTTON_LARGE
			if node_name in ["BtnCopyCode", "BtnNewCode"]:
				role = SpotRushTypography.Role.BUTTON
			elif String(node_name).begins_with("BtnClose"):
				role = SpotRushTypography.Role.BUTTON
			SpotRushTypography.apply_as(control, role)
		elif control is LineEdit or control is TextEdit:
			SpotRushTypography.apply_as(control, SpotRushTypography.Role.INPUT_VALUE)
		elif control.has_method("set_typography_size"):
			var text_role := SpotRushTypography.Role.BUTTON_LARGE
			var parent_name := String(control.get_parent().name) if control.get_parent() != null else ""
			if String(parent_name).begins_with("BtnClose") or parent_name == "BtnShareDaily":
				text_role = SpotRushTypography.Role.BUTTON
			SpotRushTypography.apply_as(control, text_role)
		elif control is Label:
			var role := SpotRushTypography.Role.BODY
			if node_name == "Title":
				role = SpotRushTypography.Role.SCREEN_TITLE
			elif node_name == "Caption":
				role = SpotRushTypography.Role.SECTION_TITLE
			elif node_name == "ButtonCaption":
				role = SpotRushTypography.Role.CAPTION
			elif node_name in ["LblBestCaption", "CapMine", "CapFriend", "LblDailyCountdown", "L1", "L2"]:
				role = SpotRushTypography.Role.STAT_LABEL
			elif node_name in ["ChoiceTitle", "Name", "LblMyCode"]:
				role = SpotRushTypography.Role.CARD_TITLE
			elif node_name in ["BestModalValue", "Val1", "Val2"]:
				role = SpotRushTypography.Role.DISPLAY
			elif node_name == "LblDailyNumber":
				role = SpotRushTypography.Role.CARD_TITLE
			elif node_name in ["BestModalHint", "LblDailyStreak", "ChoiceCaption", "LblChallengeStatus"]:
				role = SpotRushTypography.Role.CAPTION
			SpotRushTypography.apply_as(control, role)
			if node_name == "Title" and not control.has_theme_font_override("font"):
				var title_font: Font = control.get_theme_default_font()
				if title_font == null:
					title_font = ThemeDB.fallback_font
				control.add_theme_font_override("font", NeuKit.weighted_font(title_font, 800.0, 0.34))
				NeuKit.etch(control)
			# No modal copy is allowed to clip or collapse to a narrow intrinsic width.
			control.clip_text = false
			control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func _all_controls(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	if root is Control:
		result.append(root as Control)
	for child in root.get_children():
		result.append_array(_all_controls(child))
	return result
