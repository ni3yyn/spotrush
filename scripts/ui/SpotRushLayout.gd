extends RefCounted

# Shared geometry tokens for SpotRush's portrait-first screens.
# Keep padding and gaps on a 4px rhythm so independently-built screens align.
const SPACE_XS: int = 4
const SPACE_SM: int = 8
const SPACE_MD: int = 12
const SPACE_LG: int = 16
const SPACE_XL: int = 24
const SPACE_2XL: int = 32

const HEADER_HEIGHT: float = 56.0
const HEADER_GAP: int = SPACE_MD
const HEADER_SIDE_COMPACT: float = 88.0
const HEADER_SIDE_STANDARD: float = 96.0
const COMPACT_WIDTH: float = 420.0

static func is_compact_width(viewport_width: float) -> bool:
	return viewport_width < COMPACT_WIDTH

## Applies shared geometry only; signal wiring, navigation and button behavior
## stay owned by the screen that created the header.
static func apply_screen_header(
	header: HBoxContainer,
	back_button: Control,
	title_slot: Control,
	right_spacer: Control,
	compact: bool = false
) -> void:
	if header == null:
		return
	var side_width := HEADER_SIDE_COMPACT if compact else HEADER_SIDE_STANDARD
	header.custom_minimum_size.y = HEADER_HEIGHT
	header.add_theme_constant_override("separation", HEADER_GAP)
	if back_button != null:
		back_button.custom_minimum_size = Vector2(side_width, HEADER_HEIGHT)
	if title_slot != null:
		title_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if title_slot is Label:
			(title_slot as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right_spacer != null:
		right_spacer.custom_minimum_size = Vector2(side_width, 0.0)
