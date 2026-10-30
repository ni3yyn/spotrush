class_name DifficultyCurve
extends RefCounted

## v16 RUN FORGE - the run's difficulty heartbeat.
##
## A match is no longer a stack of discrete tiers: every round sits on a
## continuous 0.0..3.0 intensity axis (0 = WARM-UP floor, 3 = EXPERT
## ceiling). The curve starts at the player's persisted band, ramps
## smoothly toward the run's ceiling and deliberately breathes - a
## settle-in beat on the opening round and one recovery beat just past
## halfway - so pressure builds like a designed set list instead of a
## mechanical stair-climb. Band boundaries still exist (1..4) because the
## scoring system, the HUD callouts and the record book are band-based.

## Ramp bow: slightly > 1.0 keeps the very first rounds readable before the
## climb starts landing band changes the player can hear.
const RAMP_SHAPE: float = 1.05
## How far below the curve the opening round sits (settling beat).
const SETTLE_DIP: float = 0.30
## How far below the curve the mid-run recovery round sits (breather).
const BREATHER_DIP: float = 0.55

var start_intensity: float = 0.0
var end_intensity: float = 2.0
var total_rounds: int = 10

func _init(p_start_band: int = 1, p_total_rounds: int = 10, p_span: float = 2.0) -> void:
        total_rounds = maxi(1, p_total_rounds)
        start_intensity = clampf(float(clampi(p_start_band, 1, 4)) - 1.0, 0.0, 3.0)
        end_intensity = clampf(start_intensity + maxf(0.5, p_span), 0.0, 3.0)

## Difficulty band (1..4) a continuous intensity falls into. This is what
## the scoring system, the GET READY callout and the adaptive announcements
## consume, so the classic four-band vocabulary survives the upgrade.
static func band_for(intensity: float) -> int:
        return clampi(int(round(clampf(intensity, 0.0, 3.0))), 0, 3) + 1

## Intensity of one round on the curve, including the designed beats.
func intensity_at(round_index: int) -> float:
        var span := float(maxi(1, total_rounds - 1))
        var progress := clampf(float(round_index) / span, 0.0, 1.0)
        var shaped := pow(progress, RAMP_SHAPE)
        var value := lerpf(start_intensity, end_intensity, shaped)
        if round_index == 0 and total_rounds >= 4:
                value -= SETTLE_DIP
        if total_rounds >= 7:
                var breather := clampi(int(round(float(total_rounds) * 0.62)), 1, total_rounds - 2)
                if round_index == breather:
                        value -= BREATHER_DIP
        return clampf(value, 0.0, 3.0)
