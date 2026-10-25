class_name GameConfig
extends RefCounted

# Network constants
const DEFAULT_PORT: int = 7000
const MAX_PLAYERS: int = 2
const PROTOCOL_VERSION: int = 1

# Match constants
const DEFAULT_TOTAL_ROUNDS: int = 10
const MIN_ROUNDS: int = 3
const MAX_ROUNDS: int = 20

# Challenge timing (seconds)
const DEFAULT_CHALLENGE_DURATION: float = 8.0
const MIN_CHALLENGE_DURATION: float = 4.0
const MAX_CHALLENGE_DURATION: float = 14.0
const COUNTDOWN_DURATION: float = 1.5
const ROUND_FEEDBACK_DURATION: float = 2.0

# Scoring constants
const BASE_CORRECT_SCORE: int = 1000
const MAX_SPEED_BONUS: int = 500
const WRONG_ANSWER_PENALTY: int = 150
const WITHHOLD_SUCCESS_SCORE: int = 1000

# Color Palette (Hex)
const COLOR_DEEP_GREEN: Color = Color("17231F")
const COLOR_SURFACE: Color = Color("22332B")
const COLOR_SURFACE_LIGHT: Color = Color("2C4238")
const COLOR_MINT: Color = Color("A8F0C6")
const COLOR_MINT_HOVER: Color = Color("C5F8DB")
const COLOR_ACCENT_RED: Color = Color("F43F5E")
const COLOR_ACCENT_BLUE: Color = Color("38BDF8")
const COLOR_ACCENT_YELLOW: Color = Color("FBBF24")
const COLOR_TEXT_LIGHT: Color = Color("F1F5F9")
const COLOR_TEXT_MUTED: Color = Color("94A3B8")

# Warm Butter & Vibrant Arcade Palette Tokens
const COLOR_BUTTER: Color = Color("FAF5E8")
const COLOR_BUTTER_DARK: Color = Color("EDE5D0")
const COLOR_COBALT: Color = Color("2B52E2")
const COLOR_COBALT_DARK: Color = Color("1A3BB2")
const COLOR_TANGERINE: Color = Color("FF6B35")
const COLOR_CORAL: Color = Color("FF5964")
const COLOR_LAVENDER: Color = Color("7C5CFC")
const COLOR_CANARY: Color = Color("F4CB38")
const COLOR_DARK_NAVY: Color = Color("1E2432")
const COLOR_SLATE: Color = Color("64748B")

# Difficulty Tiers
enum Difficulty {
	EASY = 1,
	MEDIUM = 2,
	HARD = 3,
	EXPERT = 4
}

# Challenge types
const TYPE_ESTIMATION_COUNT: String = "estimation_count"
const TYPE_COMPARISON_SIDES: String = "comparison_sides"
const TYPE_COLOR_TARGET: String = "color_target"
const TYPE_SHAPE_TARGET: String = "shape_target"
const TYPE_DONT_TAP: String = "dont_tap"
const TYPE_COMBINED_CONDITIONAL: String = "combined_conditional"

# Game Modes
enum GameMode {
	SINGLE_PLAYER,
	MULTIPLAYER_HOST,
	MULTIPLAYER_CLIENT
}
