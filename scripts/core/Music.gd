extends Node

# The ambient music engine (v21).
#
# Both themes are synthesized at boot; no music assets are required.
# The sound palette is intentionally soft and "neumorphic": warm low-mid
# frequencies, rounded attacks, long overlapping envelopes, almost no bright
# transients, and very slow movement. The menu gets a sparse felt-like motif;
# the gameplay bed stays rhythm-free so it never competes with the round clock
# or the action sounds.
#
# Menu and gameplay loops are forged independently on a worker thread. The
# menu stream is built first and starts as soon as it is ready; gameplay never
# holds the first audible note hostage while its own longer render completes.

const Sfx = preload("res://scripts/core/Sfx.gd")
const Settings = preload("res://scripts/core/Settings.gd")

const RATE := 22050
const LOOP_LEN := 32.0
const FADE_IN := 0.95
const FADE_OUT := 2.4

# These are intentionally lower than the old bright pad/bell mix. The Music
# bus and the user's saved volume setting still control the final level.
const MENU_PEAK := 0.43
# Challenges need a real audible bed on phone speakers, where low fundamentals
# disappear easily. This is roughly a 9 dB peak lift over the previous game loop; the user's
# Music bus slider remains the final master control.
const GAME_PEAK := 0.90

static var _bank: Dictionary = {}
# Guards _bank: the autoload's own worker thread (_build_menu_stream /
# _build_game_stream) and ChallengeSystemSelfTest.gd (which calls
# build_stream() directly from the main thread during boot) can otherwise
# race to write the same static Dictionary from two threads at once.
# Unsynchronized concurrent Dictionary writes are undefined behavior in
# Godot and can corrupt memory in a way that only surfaces later, in a
# completely unrelated thread - exactly the shape of a crash that's hard to
# pin down from a single native SIGSEGV line with no GDScript stack trace.
static var _bank_mutex := Mutex.new()

var _menu_player: AudioStreamPlayer
var _game_player: AudioStreamPlayer
var _menu_ready := false
var _game_ready := false
var _desired := ""
var _playing := ""
var _menu_thread: Thread = null
var _game_thread: Thread = null
var _fades: Dictionary = {}

func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        _menu_player = _make_player()
        _game_player = _make_player()
        Settings.apply_audio_volumes()
        # Only synthesize the menu loop during launch. The much heavier gameplay
        # loop is generated on first entry to a challenge, not while the first
        # screen is competing for CPU time.
        _menu_thread = Thread.new()
        var err := _menu_thread.start(_build_menu_stream, Thread.PRIORITY_LOW)
        if err != OK:
                push_error("Could not start menu music worker: %d" % err)

func _make_player() -> AudioStreamPlayer:
        var p := AudioStreamPlayer.new()
        p.bus = &"Music"
        p.volume_db = -40.0
        add_child(p)
        return p

func _exit_tree() -> void:
        # A Thread must be joined even when it has just finished: is_alive()
        # can already be false while the Thread object still owns native state.
        if _menu_thread != null and _menu_thread.is_started():
                _menu_thread.wait_to_finish()
        if _game_thread != null and _game_thread.is_started():
                _game_thread.wait_to_finish()
        _menu_thread = null
        _game_thread = null
        for tw: Tween in _fades.values():
                if tw != null and tw.is_valid():
                        tw.kill()
        _fades.clear()
        for p in [_menu_player, _game_player]:
                if is_instance_valid(p):
                        p.stop()
                        p.stream = null

# --- public API ------------------------------------------------------------------------

## The menu family: main menu, friends hub, lobby, results screen.
func play_menu() -> void:
        _desired = "menu"

## The gameplay bed: arena screen only.
func play_game() -> void:
        _desired = "game"
        if _menu_ready:
                _start_game_build()

## Prebuild the gameplay loop during an idle menu moment, not during scene entry.
func prime_game() -> void:
        if _menu_ready:
                _start_game_build()

func stop_all() -> void:
        _desired = ""

# --- bank ------------------------------------------------------------------------------

func _build_menu_stream() -> void:
        var started_usec := Time.get_ticks_usec()
        var menu_stream := build_stream("menu")
        call_deferred("_log_music_build", "menu", Time.get_ticks_usec() - started_usec)
        call_deferred("_on_stream_ready", "menu", menu_stream)

func _build_game_stream() -> void:
        var started_usec := Time.get_ticks_usec()
        var game_stream := build_stream("game")
        call_deferred("_log_music_build", "game", Time.get_ticks_usec() - started_usec)
        call_deferred("_on_stream_ready", "game", game_stream)

func _log_music_build(kind: String, elapsed_usec: int) -> void:
        if OS.is_debug_build() and elapsed_usec >= 8000:
                print("[PERF] Music synthesis %s (worker): %.2f ms" % [kind, float(elapsed_usec) / 1000.0])

func _start_game_build() -> void:
        if _game_ready or (_game_thread != null and _game_thread.is_started()):
                return
        # The menu worker has already posted its completion callback. Join it
        # before reusing any worker resources; this should be a very short wait.
        if _menu_thread != null and _menu_thread.is_started():
                _menu_thread.wait_to_finish()
        _game_thread = Thread.new()
        var err := _game_thread.start(_build_game_stream, Thread.PRIORITY_LOW)
        if err != OK:
                push_error("Could not start gameplay music worker: %d" % err)

func _on_stream_ready(kind: String, stream: AudioStreamWAV) -> void:
        if kind == "menu":
                _menu_ready = true
                _menu_player.stream = stream
                # The player may have reached a challenge before the menu loop
                # finished generating. Defer the second worker until this callback
                # arrives so the two synthesis jobs never compete at launch.
                if _desired == "game":
                        call_deferred("_start_game_build")
        elif kind == "game":
                _game_ready = true
                _game_player.stream = stream
        if _desired == kind and _playing != kind:
                _apply_desired()

func _stream_is_ready(kind: String) -> bool:
        return _menu_ready if kind == "menu" else _game_ready

## Builds and caches one seamless 32-second ambient loop.
static func build_stream(kind: String) -> AudioStreamWAV:
        _bank_mutex.lock()
        if _bank.has(kind):
                var cached: AudioStreamWAV = _bank[kind]
                _bank_mutex.unlock()
                return cached
        _bank_mutex.unlock()
        # Synthesis itself (below) deliberately happens OUTSIDE the lock - it's
        # the expensive part and doesn't touch _bank, so there's no reason to
        # make a second caller block on it. Losing the race just means two
        # callers synthesize the same loop once each; only the final _bank
        # write below needs to be mutually exclusive.
        var n := int(RATE * LOOP_LEN)
        var samples := PackedFloat32Array()
        samples.resize(n)
        if kind == "menu":
                _forge_menu(samples)
                # The melody gently ducks at a few uneven moments, then returns
                # on a slower curve. Add a handful of soft, random brush-like
                # scratches before the final low-pass, so they sit inside the bed.
                _add_random_scratches(samples, float(RATE), 3, 0.009)
                # Quick, rounded dips across the whole mix. The fall is brief
                # and noticeable; the return is slower, like the music taking
                # a calm breath rather than a hard volume cut.
                _apply_volume_dips(samples, float(RATE), [
                        [7.0, 0.22, 0.10, 0.12, 0.78],
                        [17.0, 0.26, 0.11, 0.14, 0.88],
                        [25.2, 0.24, 0.10, 0.12, 0.82],
                ])
                _soften(samples, 0.30)
                _normalize(samples, MENU_PEAK)
        else:
                _forge_game(samples)
                _add_random_scratches(samples, float(RATE), 3, 0.0055)
                _apply_volume_dips(samples, float(RATE), [
                        [11.6, 0.46, 0.10, 0.16, 0.92],
                        [24.0, 0.52, 0.10, 0.14, 0.86],
                ])
                _soften(samples, 0.27)
                _normalize(samples, GAME_PEAK)
        var wav := Sfx._to_wav(samples)
        wav.mix_rate = RATE
        wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
        wav.loop_begin = 0
        wav.loop_end = n
        _bank_mutex.lock()
        # Another thread may have finished building and cached this same kind
        # while we were synthesizing our own copy above - keep whichever one
        # landed first so every caller ever after shares one canonical object
        # (the self-test's cache-identity check relies on this).
        if _bank.has(kind):
                wav = _bank[kind]
        else:
                _bank[kind] = wav
        _bank_mutex.unlock()
        return wav

# --- composition -----------------------------------------------------------------------

## Menu: a slow Fmaj9 -> Dm9 -> Am9 -> Cmaj9 journey.
## Chords overlap by roughly two seconds, so the harmony breathes into each new
## shape instead of switching abruptly. A rounded felt-key motif sits above it.
static func _forge_menu(samples: PackedFloat32Array) -> void:
        var rate := float(RATE)
        var chords := [
                {"start": 0.0, "dur": 8.0, "bass": 87.31, "pad": [174.61, 220.0, 261.63, 329.63, 392.0]},
                {"start": 6.0, "dur": 10.0, "bass": 73.42, "pad": [146.83, 174.61, 220.0, 261.63, 329.63]},
                {"start": 14.0, "dur": 10.0, "bass": 55.0, "pad": [130.81, 164.81, 196.0, 246.94, 329.63]},
                {"start": 22.0, "dur": 10.0, "bass": 65.41, "pad": [130.81, 164.81, 196.0, 246.94, 293.66]},
        ]
        for ci in chords.size():
                var chord: Dictionary = chords[ci]
                var begin := float(chord["start"])
                var duration := float(chord["dur"])
                var phase := float(ci) * 1.31
                for j in chord["pad"].size():
                        var gain := 0.042 if j < 3 else 0.030
                        _render_warm_pad(samples, rate, begin, duration,
                                float(chord["pad"][j]), gain, phase + float(j) * 0.37)
                _render_warm_pad(samples, rate, begin, duration,
                        float(chord["bass"]), 0.092, phase, true)

        # Keep the five original low, widely-spaced anchor notes. Their contour
        # now moves through clearer, chord-aware intervals, so each new phrase
        # feels like a response rather than a barely perceptible pitch drift.
        var notes := [
                [3.0, 392.0, 0.056, 3.8],
                [9.4, 349.23, 0.054, 3.8],
                [15.5, 329.63, 0.055, 3.8],
                [21.0, 246.94, 0.056, 3.8],
                [27.0, 293.66, 0.056, 3.8],
        ]
        # A quieter answer note follows each anchor, with loose spacing and
        # slightly different intervals. It adds emotional movement without
        # creating a beat or turning the theme into an arcade tune.
        var answers := [
                [4.55, 329.63, 0.030, 2.8],
                [10.95, 293.66, 0.029, 2.8],
                [17.05, 261.63, 0.030, 2.8],
                [22.65, 196.00, 0.031, 2.8],
                [28.55, 246.94, 0.030, 2.8],
        ]
        for ev in notes + answers:
                _render_soft_note(samples, rate, float(ev[0]),
                        float(ev[1]), float(ev[2]), float(ev[3]))

## Gameplay: the darker Am9 -> Fmaj7 -> Cmaj7 -> G6 bed. A low, slow melodic
## line makes the music audible on phone speakers, but stays behind timer ticks
## and action cues instead of introducing a regular rhythm.
static func _forge_game(samples: PackedFloat32Array) -> void:
        var rate := float(RATE)
        var chords := [
                {"start": 0.0, "dur": 8.0, "bass": 55.0, "pad": [110.0, 164.81, 220.0, 261.63]},
                {"start": 6.0, "dur": 10.0, "bass": 43.65, "pad": [87.31, 130.81, 174.61, 220.0]},
                {"start": 14.0, "dur": 10.0, "bass": 65.41, "pad": [130.81, 164.81, 196.0, 246.94]},
                {"start": 22.0, "dur": 10.0, "bass": 49.0, "pad": [98.0, 146.83, 196.0, 293.66]},
        ]
        for ci in chords.size():
                var chord: Dictionary = chords[ci]
                var begin := float(chord["start"])
                var duration := float(chord["dur"])
                var phase := float(ci) * 0.83 + 0.6
                for j in chord["pad"].size():
                        var gain := 0.030 if j < 3 else 0.020
                        _render_warm_pad(samples, rate, begin, duration,
                                float(chord["pad"][j]), gain, phase + float(j) * 0.29)
                _render_warm_pad(samples, rate, begin, duration,
                        float(chord["bass"]), 0.075, phase, true)

        # A distinct but restrained low-mid phrase for challenge play. These
        # notes sit above the phone speaker's weakest sub-bass range and move
        # through the underlying chords, while leaving several seconds of air.
        var notes := [
                [2.8, 220.0, 0.071, 4.0],
                [9.4, 261.63, 0.069, 4.0],
                [15.7, 196.0, 0.072, 4.0],
                [21.6, 164.81, 0.069, 4.0],
                [27.4, 220.0, 0.071, 4.0],
        ]
        var answers := [
                [4.45, 329.63, 0.038, 2.9],
                [11.0, 293.66, 0.037, 2.9],
                [17.3, 261.63, 0.039, 2.9],
                [23.1, 246.94, 0.037, 2.9],
                [28.95, 293.66, 0.038, 2.9],
        ]
        for ev in notes + answers:
                _render_soft_note(samples, rate, float(ev[0]),
                        float(ev[1]), float(ev[2]), float(ev[3]))

## Short, soft amplitude drops. The fall is quick enough to be felt, but uses
## a smooth curve so there is no click; the return is deliberately slower.
static func _apply_volume_dips(samples: PackedFloat32Array, rate: float, dips: Array) -> void:
        for i in samples.size():
                var time := float(i) / rate
                var level := 1.0
                for dip in dips:
                        var start := float(dip[0])
                        var floor_level := float(dip[1])
                        var fall_time := float(dip[2])
                        var hold_time := float(dip[3])
                        var rise_time := float(dip[4])
                        var local := time - start
                        if local < 0.0 or local >= fall_time + hold_time + rise_time:
                                continue
                        var current := 1.0
                        if local < fall_time:
                                current = lerpf(1.0, floor_level, _smooth_unit(local / fall_time))
                        elif local < fall_time + hold_time:
                                current = floor_level
                        else:
                                var progress := (local - fall_time - hold_time) / rise_time
                                current = lerpf(floor_level, 1.0, _smooth_unit(progress))
                        level = minf(level, current)
                samples[i] *= level

## Very quiet vinyl/brush-like traces, placed at random points in the loop.
## Their envelopes meet silence at both ends; the loop seam stays untouched.
static func _add_random_scratches(samples: PackedFloat32Array, rate: float,
                count: int, amplitude: float) -> void:
        var rng := RandomNumberGenerator.new()
        rng.randomize()
        for _scratch_index in count:
                var start := rng.randf_range(1.8, LOOP_LEN - 2.2)
                var duration := rng.randf_range(0.18, 0.36)
                var from_hz := rng.randf_range(420.0, 820.0)
                var to_hz := rng.randf_range(250.0, 520.0)
                var phase := rng.randf_range(0.0, TAU)
                var first := maxi(0, int(start * rate))
                var last := mini(samples.size(), int((start + duration) * rate))
                var filtered_noise := 0.0
                for i in range(first, last):
                        var t := float(i) / rate - start
                        var x := clampf(t / duration, 0.0, 1.0)
                        var envelope := sin(PI * x)
                        envelope *= envelope
                        var noise := rng.randf_range(-1.0, 1.0)
                        filtered_noise += (noise - filtered_noise) * 0.10
                        var sweep_hz := lerpf(from_hz, to_hz, x)
                        # Mostly a soft filtered brush with a small tonal glide;
                        # very little raw noise, so it never turns into static.
                        var friction := noise * 0.07 + filtered_noise * 0.58 \
                                + sin(TAU * sweep_hz * t + phase) * 0.35
                        samples[i] += friction * envelope * amplitude

# --- voices -----------------------------------------------------------------------------

## Softly chorused pad voice. The second oscillator is only fractionally detuned,
## creating slow movement without audible wobble. Harmonics are deliberately low.
static func _render_warm_pad(samples: PackedFloat32Array, rate: float,
                t0: float, dur: float, freq: float, gain: float,
                phase: float, is_bass := false) -> void:
        var i0 := maxi(0, int(t0 * rate))
        var i1 := mini(samples.size(), int((t0 + dur) * rate))
        var attack := 2.0 if is_bass else 2.5
        var release := 2.2 if is_bass else 2.7
        for i in range(i0, i1):
                var t := float(i) / rate - t0
                var fade_in := _smooth_unit(t / attack)
                var fade_out := _smooth_unit((dur - t) / release)
                var env := fade_in * fade_out
                if env <= 0.0001:
                        continue
                var breathe := 0.91 + 0.09 * sin(TAU * 0.038 * t + phase)
                var fundamental := sin(TAU * freq * t + phase)
                var voice: float
                if is_bass:
                        voice = fundamental * 0.88 \
                                + sin(TAU * freq * 2.0 * t + phase * 0.5) * 0.12
                else:
                        var detuned := sin(TAU * (freq * 1.0022) * t + phase + 0.55)
                        var warm_partial := sin(TAU * freq * 2.0 * t + phase * 0.4)
                        voice = fundamental * 0.76 + detuned * 0.19 + warm_partial * 0.05
                samples[i] += voice * env * gain * breathe

## A muted, rounded key-like tone: quick-but-not-sharp onset, soft upper partials,
## and a long natural decay. No metallic bell spectrum or high-frequency click.
static func _render_soft_note(samples: PackedFloat32Array, rate: float,
                t0: float, freq: float, gain: float, dur: float) -> void:
        var i0 := maxi(0, int(t0 * rate))
        var i1 := mini(samples.size(), int((t0 + dur) * rate))
        for i in range(i0, i1):
                var t := float(i) / rate - t0
                # Soft felt-key onset, then a rounded, audible tail.
                var attack := 1.0 - exp(-t * 5.5)
                var decay := exp(-t * 0.92)
                var fundamental := sin(TAU * freq * t)
                var octave := sin(TAU * freq * 2.0 * t + 0.18)
                var fifth := sin(TAU * freq * 3.0 * t + 0.31)
                var tone := fundamental * 0.80 + octave * 0.155 + fifth * 0.045
                var tail := _smooth_unit((dur - t) / 0.42)
                samples[i] += tone * attack * decay * tail * gain

## Cubic easing keeps the envelopes rounded at both ends.
static func _smooth_unit(v: float) -> float:
        var x := clampf(v, 0.0, 1.0)
        return x * x * (3.0 - 2.0 * x)

## A very gentle one-pole low-pass takes the brittle edge off the synthesized
## partials while preserving the fundamental and the soft low-end body.
static func _soften(samples: PackedFloat32Array, amount: float) -> void:
        var filtered := 0.0
        for i in samples.size():
                filtered += (samples[i] - filtered) * amount
                samples[i] = filtered

static func _normalize(samples: PackedFloat32Array, target: float) -> void:
        var peak := 0.0
        for v in samples:
                peak = maxf(peak, absf(v))
        if peak <= 0.0001:
                return
        var g := target / peak
        for i in samples.size():
                samples[i] *= g

# --- playback ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
        if _desired != _playing and (_desired == "" or _stream_is_ready(_desired)):
                _apply_desired()

func _apply_desired() -> void:
        # The headless dummy audio driver can retain active WAV playbacks during
        # automated shutdown. Music is meaningless there, so keep tests silent.
        if DisplayServer.get_name() == "headless":
                _playing = _desired
                return
        if _desired == "":
                _fade_out(_menu_player)
                _fade_out(_game_player)
                _playing = ""
                return
        var p := _menu_player if _desired == "menu" else _game_player
        var other := _game_player if _desired == "menu" else _menu_player
        if p.stream == null:
                # Stream assignment happens in _on_stream_ready(). Never render
                # a whole loop synchronously on the main thread as a fallback.
                return
        if not p.playing:
                p.volume_db = -40.0
                p.play()
        _fade_to(p, 0.0, FADE_IN)
        _fade_out(other)
        _playing = _desired

func _fade_to(p: AudioStreamPlayer, db_to: float, dur: float) -> void:
        _kill_fade(p)
        var tw := create_tween()
        tw.tween_property(p, "volume_db", db_to, dur) \
                .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        _fades[p] = tw

func _fade_out(p: AudioStreamPlayer) -> void:
        if not p.playing:
                return
        _kill_fade(p)
        var tw := create_tween()
        tw.tween_property(p, "volume_db", -40.0, FADE_OUT) \
                .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        tw.tween_callback(p.stop)
        _fades[p] = tw

func _kill_fade(p: AudioStreamPlayer) -> void:
        var tw: Tween = _fades.get(p)
        if tw != null and tw.is_valid():
                tw.kill()
