extends RefCounted

# One call site for "game feel": sound + haptics + reduce-motion, all gated by Settings.
#   Feel.sfx("pop", 1.2)     Feel.haptic("light")     if Feel.reduced(): ...

const Settings = preload("res://scripts/core/Settings.gd")
const Sfx = preload("res://scripts/core/Sfx.gd")

static func sfx(sound: String, pitch: float = 1.0, gain_db: float = 0.0) -> void:
        if Settings.sfx():
                Sfx.play(sound, pitch, gain_db)

## kind: "light" | "medium" | "heavy" | "success" | "error". No-ops on desktop.
static func haptic(kind: String) -> void:
        if not Settings.haptics() or not (OS.has_feature("android") or OS.has_feature("ios")):
                return
        match kind:
                "light": Input.vibrate_handheld(12, 0.3)
                "medium": Input.vibrate_handheld(24, 0.6)
                "heavy": Input.vibrate_handheld(40, 0.9)
                "success":
                        Input.vibrate_handheld(14, 0.4)
                        _later(0.07, func(): Input.vibrate_handheld(26, 0.7))
                "error":
                        Input.vibrate_handheld(45, 0.9)
                        _later(0.09, func(): Input.vibrate_handheld(30, 0.6))

static func reduced() -> bool:
        return Settings.reduce_motion()

static func _later(seconds: float, action: Callable) -> void:
        var tree := Engine.get_main_loop() as SceneTree
        if tree != null:
                tree.create_timer(seconds).timeout.connect(action)

## Builds the sound bank one sound per frame (the bell sounds are ~50 ms each), so
## no single frame hitches. Fire-and-forget: just call Feel.warm_up() once at startup.
static func warm_up() -> void:
        var tree := Engine.get_main_loop() as SceneTree
        if tree == null:
                return
        for sound_name in Sfx.names():
                var started_usec := Time.get_ticks_usec()
                Sfx.get_stream(sound_name)
                _log_warm_step("SFX " + sound_name, Time.get_ticks_usec() - started_usec)
                await tree.process_frame
        var seen := {}
        for f in MELODY:
                var key := int(round(f * 100.0))
                if seen.has(key):
                        continue
                seen[key] = true
                var started_usec := Time.get_ticks_usec()
                Sfx.note_stream(f)
                _log_warm_step("note %.2f" % f, Time.get_ticks_usec() - started_usec)
                await tree.process_frame

static func _log_warm_step(kind: String, elapsed_usec: int) -> void:
        if OS.is_debug_build() and elapsed_usec >= 6000:
                print("[PERF] Audio warm-up %s: %.2f ms (main thread)" % [kind, float(elapsed_usec) / 1000.0])

# --- typing melody --------------------------------------------------------------------

## "Twinkle, Twinkle, Little Star" (public domain), one note per keystroke, so
## typing the game code continuously plays the tune. The pitch contour alone
## carries the melody - every key always sounds, no silent rest slots.
const MELODY := [
        523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,   # C C G G A A G
        698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,   # F F E E D D C
        783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,   # G G F F E E D
        783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,   # G G F F E E D
        523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,   # C C G G A A G
        698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,   # F F E E D D C
]

static var _melody_idx: int = 0

## Advance one step and play the next note of the typing melody.
static func melody_pip() -> void:
        if not Settings.sfx():
                return
        var freq: float = MELODY[_melody_idx % MELODY.size()]
        _melody_idx += 1
        Sfx.play_note(freq)

## Backspace scrubs the melody back one note and replays it a touch softer.
static func melody_back() -> void:
        if not Settings.sfx():
                return
        _melody_idx = maxi(0, _melody_idx - 1)
        var freq: float = MELODY[_melody_idx % MELODY.size()]
        Sfx.play_note(freq, -7.0)

## Restart the melody from the first note (called when the field is cleared).
static func melody_reset() -> void:
        _melody_idx = 0

## Three rising glass notes when a combo tier is reached (x2 / x3 / x4).
## Each tier starts the arpeggio higher so escalation is always audible.
static func combo_jingle(tier: int) -> void:
        if not Settings.sfx():
                return
        var base := 523.25
        match tier:
                2: base = 523.25   # C5 - E5 - G5
                3: base = 659.25   # E5 - G5 - C6
                4: base = 783.99   # G5 - C6 - E6
                _: return
        _later(0.00, func(): Sfx.play_note(base))
        _later(0.09, func(): Sfx.play_note(base * 1.26))
        _later(0.18, func(): Sfx.play_note(base * 1.50))

## Difficulty-band change heard at GET READY: two notes rising when the adaptive
## engine moves the player up a band, falling when it eases off - so the
## difficulty changes are felt, not just silently applied.
static func band_change(up: bool) -> void:
        if not Settings.sfx():
                return
        var base := 587.33  # D5
        if up:
                _later(0.00, func(): Sfx.play_note(base))
                _later(0.13, func(): Sfx.play_note(base * 1.50))   # D5 -> A5
        else:
                _later(0.00, func(): Sfx.play_note(base))
                _later(0.13, func(): Sfx.play_note(base * 0.75))  # D5 -> A4
