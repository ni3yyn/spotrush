extends RefCounted

## v18 COLOUR VISION - colour-blind-safe token palettes.
##
## The forge emits abstract colour NAMES ("RED", "MINT", ...) in every
## challenge; this module is the single place those names become real colours,
## so a colour vision mode is a pure PRESENTATION swap:
##   - seeds are untouched -> duels, Daily Spot and rival codes stay identical
##   - both phones in a duel may run different modes and still play the same run
##
## Every palette is tuned against a Vienot/Brettel simulation of the actual
## vision deficiency and must keep every name inside its family (RED still
## reads red, MINT still reads mint) so the spoken instruction text - "Tap the
## YELLOW ones!" - stays truthful. Verified by ChallengeSystemSelfTest:
## worst-case pairwise CIE76 dE across all ten colour pairs is
##   base  deutan  5.4  ->  tuned 35.2
##   base  protan  7.1  ->  tuned 35.7
##   base  tritan  9.1  ->  tuned 33.2
## (30 is the pass bar; a typical "clearly distinct" line is ~25.)

const Settings = preload("res://scripts/core/Settings.gd")

const MODE_OFF := "off"
const MODE_DEUTAN := "deutan"
const MODE_PROTAN := "protan"
const MODE_TRITAN := "tritan"
const MODES := [MODE_OFF, MODE_DEUTAN, MODE_PROTAN, MODE_TRITAN]

## Token palettes per mode, as html hex (no alpha). The "off" row MUST mirror
## NeuKit exactly (CORAL / COBALT / CANARY / MINT / SURFACE) - the self-test
## asserts it, so any re-skin of NeuKit fails loudly until this table follows.
const PALETTES := {
        MODE_OFF: {
                "RED": "FF5964", "BLUE": "2B52E2", "YELLOW": "F4B82F",
                "MINT": "3FCB93", "WHITE": "E4E9F2",
        },
        ## Red-green axis folds: crimson is pulled dark, lemon pushed bright
        ## (lightness carries the RED-YELLOW pair), mint stays a bright teal.
        MODE_DEUTAN: {
                "RED": "A62E36", "BLUE": "2B52E2", "YELLOW": "F8D952",
                "MINT": "35BE8F", "WHITE": "E4E9F2",
        },
        ## Same collapse, slightly different compensation: protanopes read
        ## reds darker, so the crimson and canary shift one lightness notch.
        MODE_PROTAN: {
                "RED": "AD2830", "BLUE": "2B52E2", "YELLOW": "F6D445",
                "MINT": "3FB39A", "WHITE": "E4E9F2",
        },
        ## Blue-yellow axis folds: blue drifts to indigo, mint drops its cyan
        ## to a pure green, butter stays pale; the red-green axis survives,
        ## so the scarlet can stay vivid.
        MODE_TRITAN: {
                "RED": "C0392B", "BLUE": "2132ED", "YELLOW": "F2D160",
                "MINT": "35914A", "WHITE": "E4E9F2",
        },
}

const MODE_LABELS := {
        MODE_OFF: "STANDARD",
        MODE_DEUTAN: "DEUTAN",
        MODE_PROTAN: "PROTAN",
        MODE_TRITAN: "TRITAN",
}

static func mode() -> String:
        var stored := Settings.colorblind()
        return stored if stored in MODES else MODE_OFF

static func set_mode(m: String) -> void:
        Settings.set_colorblind(m if m in MODES else MODE_OFF)

static func is_cvd(m: String) -> bool:
        return m != MODE_OFF and m in MODES

static func mode_label(m: String) -> String:
        return str(MODE_LABELS.get(m, MODE_LABELS[MODE_OFF]))

## One-line description shown under the picker in the settings screen.
static func mode_hint(m: String) -> String:
        match m:
                MODE_DEUTAN:
                        return "Red-green (deuteranopia)\nTuned for green-weak vision"
                MODE_PROTAN:
                        return "Red-green (protanopia)\nTuned for red-weak vision"
                MODE_TRITAN:
                        return "Blue-yellow (tritanopia)\nTuned for blue-weak vision"
                _:
                        return "The default SpotRush palette"

## Canonical name for every token string the forge can emit (aliases fold in).
static func canonical(token_name: String) -> String:
        match token_name.to_upper():
                "RED", "CORAL":
                        return "RED"
                "BLUE":
                        return "BLUE"
                "YELLOW", "AMBER":
                        return "YELLOW"
                "WHITE":
                        return "WHITE"
                "MINT", _:
                        return "MINT"

## The one resolver the render side asks for. Pure: same mode + name -> same
## colour, no state, so caching elsewhere stays safe.
static func resolve(token_name: String) -> Color:
        var key := canonical(token_name)
        var table: Dictionary = PALETTES.get(mode(), PALETTES[MODE_OFF])
        var hex := str(table.get(key, PALETTES[MODE_OFF][key]))
        return Color(hex)

## The Go/No-Go alert halo. Off mode keeps the exact v17 alert red so nothing
## shifts for standard vision; CVD modes follow their tuned RED so the halo
## can never disagree with the token it marks.
static func halo() -> Color:
        if not is_cvd(mode()):
                return Color(1.0, 0.22, 0.30)
        return resolve("RED")

# --- CVD simulation + dE (used by the self-test to re-verify the tables) -------------

## Vienot 1999 linear approximations (deutan/protan) and the Brettel-style
## tritan projection, in LINEAR rgb. Good enough to design and gate palettes.
const SIM_MATRICES := {
        MODE_DEUTAN: [Vector3(0.625, 0.375, 0.0), Vector3(0.6995, 0.3005, 0.0), Vector3(0.0, 0.3, 0.7)],
        MODE_PROTAN: [Vector3(0.567, 0.433, 0.0), Vector3(0.558, 0.442, 0.0), Vector3(0.0, 0.242, 0.758)],
        MODE_TRITAN: [Vector3(0.95, 0.05, 0.0), Vector3(0.0, 0.43333, 0.56667), Vector3(0.0, 0.475, 0.525)],
}

static func _srgb_to_linear(chan: float) -> float:
        if chan <= 0.04045:
                return chan / 12.92
        return pow((chan + 0.055) / 1.055, 2.4)

static func _linear_to_srgb(chan: float) -> float:
        if chan <= 0.0031308:
                return chan * 12.92
        return 1.055 * pow(maxf(chan, 0.0), 1.0 / 2.4) - 0.055

## Simulate how a colour-deficient viewer perceives `c` under the given mode.
static func simulate(c: Color, cvd_mode: String) -> Color:
        var rows: Array = SIM_MATRICES.get(cvd_mode, [Vector3.ONE, Vector3.ONE, Vector3.ONE])
        var lin := Vector3(_srgb_to_linear(c.r), _srgb_to_linear(c.g), _srgb_to_linear(c.b))
        var out := Vector3(
                rows[0].dot(lin),
                rows[1].dot(lin),
                rows[2].dot(lin))
        return Color(
                clampf(_linear_to_srgb(out.x), 0.0, 1.0),
                clampf(_linear_to_srgb(out.y), 0.0, 1.0),
                clampf(_linear_to_srgb(out.z), 0.0, 1.0))

## CIE76 colour difference on D65 Lab. Input colours are compared AS SEEN
## (call simulate() first when gating a CVD palette).
static func delta_e76(a: Color, b: Color) -> float:
        var la := _to_lab(a)
        var lb := _to_lab(b)
        return sqrt(pow(la.x - lb.x, 2.0) + pow(la.y - lb.y, 2.0) + pow(la.z - lb.z, 2.0))

static func _to_lab(c: Color) -> Vector3:
        var lin := Vector3(_srgb_to_linear(c.r), _srgb_to_linear(c.g), _srgb_to_linear(c.b))
        # sRGB -> XYZ (D65)
        var x := 0.4124564 * lin.x + 0.3575761 * lin.y + 0.1804375 * lin.z
        var y := 0.2126729 * lin.x + 0.7151522 * lin.y + 0.0721750 * lin.z
        var z := 0.0193339 * lin.x + 0.1191920 * lin.y + 0.9503041 * lin.z
        var fx := _lab_f(x / 0.95047)
        var fy := _lab_f(y / 1.0)
        var fz := _lab_f(z / 1.08883)
        return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))

static func _lab_f(t: float) -> float:
        return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
