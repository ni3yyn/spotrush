class_name GameConfig
extends RefCounted

## Build stamp shown on the menu footer chip. Bump it (and the export
## preset version) together when shipping a build (v21).
const APP_VERSION := "v21"

# Network constants
const DEFAULT_PORT: int = 7000
const MAX_PLAYERS: int = 2
const PROTOCOL_VERSION: int = 1
# v21: the UDP port the "nearby games" beacon shouts on. Deliberately distinct
# from the ENet duel port - beacons advertise, duels connect.
const DISCOVERY_PORT: int = 42113

# Match constants
const DEFAULT_TOTAL_ROUNDS: int = 10
const MIN_ROUNDS: int = 3
const MAX_ROUNDS: int = 20
const DAILY_ROUNDS: int = 10  # Daily Spot: fixed length, same for everyone

# Challenge timing (seconds)
const DEFAULT_CHALLENGE_DURATION: float = 8.0
const MIN_CHALLENGE_DURATION: float = 4.0
const MAX_CHALLENGE_DURATION: float = 14.0
const COUNTDOWN_DURATION: float = 0.8
const ROUND_FEEDBACK_DURATION: float = 1.0

# Scoring constants
const BASE_CORRECT_SCORE: int = 1000
const MAX_SPEED_BONUS: int = 500
const WRONG_ANSWER_PENALTY: int = 150
const WITHHOLD_SUCCESS_SCORE: int = 1000

# Combo multiplier tiers: consecutive correct answers escalate the multiplier.
const COMBO_TIER_2: int = 3   # 3 in a row -> x2
const COMBO_TIER_3: int = 6   # 6 in a row -> x3
const COMBO_TIER_4: int = 10  # 10 in a row -> x4

# --- Scoring 2.0 ----------------------------------------------------------------------
# Base pay is difficulty-weighted, so climbing the adaptive bands visibly raises
# the stakes: WARM-UP 800, STEADY 1000, HARD 1250, EXPERT 1550.
const BASE_BY_DIFFICULTY := [800, 1000, 1250, 1550]
# The speed bonus uses an ease-out curve (exponent < 1): mid-window answers earn
# closer to the max, so answering fast always feels worth it.
const SPEED_CURVE_EXP: float = 0.65
# Answered with at least this fraction of the clock still in hand -> flat bonus.
const LIGHTNING_THRESHOLD: float = 0.85
const LIGHTNING_BONUS: int = 150
# Per-round grade bands (fraction of the time limit actually used by a hit).
const GRADE_S_TIME: float = 0.30
const GRADE_A_TIME: float = 0.55
const GRADE_B_TIME: float = 0.80
# Display names for the four difficulty bands.
const DIFFICULTY_BANDS := ["WARM-UP", "STEADY", "HARD", "EXPERT"]

static func base_score_for(difficulty: int) -> int:
        return int(BASE_BY_DIFFICULTY[clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX) - 1])

static func band_name(difficulty: int) -> String:
        return str(DIFFICULTY_BANDS[clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX) - 1])

# Adaptive difficulty (session skill rating, clamped to the 1..4 difficulty bands).
# Targets the flow channel: correct + fast climbs quickly, correct + slow climbs
# gently, a miss eases off one band so the player is never overwhelmed.
const ADAPT_FAST_RATIO: float = 0.5  # answered within this fraction of the limit = fast
const ADAPT_STEP_FAST: int = 2
const ADAPT_STEP_SLOW: int = 1
const ADAPT_STEP_MISS: int = -1
const DIFFICULTY_MIN: int = 1
const DIFFICULTY_MAX: int = 4

# --- Run Forge (v16 procedural challenge system) ---------------------------------------
# Every Play click forges a whole run from fresh entropy: a type schedule
# with variety guarantees, a continuous difficulty curve, and per-round
# seeded generation with a quality gate. No hardcoded layouts or answers.
# Intensity span covered by a standard run's curve (in 0..3 band units).
# 2.6 lets a WARM-UP start finish at HARD, with band changes landing around
# the 1/3 and 2/3 marks so progression is audible; skill and momentum can
# still push a hot player into EXPERT territory.
const FORGE_RUN_SPAN: float = 2.6
# How strongly live performance may bend the curve in adaptive (solo) runs.
const FORGE_ADAPT_GAIN: float = 0.75
# Hard cap on tokens per play field (each split side counts as one field).
const FORGE_MAX_ITEMS_PER_FIELD: int = 46
# Build attempts (fresh salt each) before the calm-comparison fallback.
const FORGE_QUALITY_ATTEMPTS: int = 3

# Color Palette (Hex)
# SpotRush tactile arcade palette. Legacy constant names remain stable so gameplay
# and networking rules do not need to know about presentation changes.
const COLOR_DEEP_GREEN: Color = Color("1E2432") # Ink/navy for high contrast
const COLOR_SURFACE: Color = Color("FAF5E8") # Warm butter cream
const COLOR_SURFACE_LIGHT: Color = Color("FFFDF7") # Raised paper surface
const COLOR_MINT: Color = Color("A8E8BF")
const COLOR_MINT_HOVER: Color = Color("C9F2D6")
const COLOR_ACCENT_RED: Color = Color("FF5964") # Coral
const COLOR_ACCENT_BLUE: Color = Color("2B52E2") # Cobalt
const COLOR_ACCENT_YELLOW: Color = Color("F4CB38") # Canary
const COLOR_TEXT_LIGHT: Color = Color("1E2432") # Legacy name; now the primary ink
const COLOR_TEXT_MUTED: Color = Color("687386")

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
