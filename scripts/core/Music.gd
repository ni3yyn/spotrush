extends Node

# Restored original SpotRush music composition (v20) with the newer lazy threaded loader.
#
# Both themes are synthesized at boot; no music assets are required.
# Menu: Fmaj7 -> Am7 warm pad, deep bass and five soft tine notes.
# Gameplay: A-minor drone, a slow swell and three faint bells. Both loops are
# rhythm-free so they never compete with the round clock or action sounds.
#
# Menu and gameplay loops are forged independently on a worker thread. The
# menu stream is built first and starts as soon as it is ready; gameplay never
# holds the first audible note hostage while its own longer render completes.

const Sfx = preload("res://scripts/core/Sfx.gd")
const Settings = preload("res://scripts/core/Settings.gd")

const RATE := 22050
const LOOP_LEN := 16.0
const FADE_IN := 1.6
const FADE_OUT := 1.0


static var _bank: Dictionary = {}
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

## Builds and caches one seamless 16-second original ambient loop.
static func build_stream(kind: String) -> AudioStreamWAV:
        # The self-test can request a stream on the main thread while the menu
        # worker is filling the same static cache. Lock only cache access; keep
        # the expensive synthesis outside the mutex to avoid blocking either.
        _bank_mutex.lock()
        if _bank.has(kind):
                var cached: AudioStreamWAV = _bank[kind]
                _bank_mutex.unlock()
                return cached
        _bank_mutex.unlock()

        var n := int(RATE * LOOP_LEN)
        var samples := PackedFloat32Array()
        samples.resize(n)
        if kind == "menu":
                _forge_menu(samples)
                _normalize(samples, 0.72)
        else:
                _forge_game(samples)
                _normalize(samples, 0.52)

        var wav := Sfx._to_wav(samples)
        wav.mix_rate = RATE
        wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
        wav.loop_begin = 0
        wav.loop_end = n

        _bank_mutex.lock()
        if _bank.has(kind):
                wav = _bank[kind]
        else:
                _bank[kind] = wav
        _bank_mutex.unlock()
        return wav

# --- composition -----------------------------------------------------------------------

## Menu: Fmaj7 (8 s) -> Am7 (8 s). The chord boundary lands on the loop seam
## and both chords' envelopes reach zero there, so the loop is seamless.
static func _forge_menu(samples: PackedFloat32Array) -> void:
        var rate := float(RATE)
        var chords := [
                {"bass": 87.31, "pad": [174.61, 220.0, 261.63, 329.63]},  # F2 + Fmaj7
                {"bass": 110.0, "pad": [196.0, 220.0, 261.63, 329.63]},   # A2 + Am7
        ]
        for ci in chords.size():
                var start := float(ci) * 8.0
                var phase := float(ci) * 1.7
                for f in chords[ci]["pad"]:
                        _render_pad(samples, rate, start, 8.0, float(f), 0.105, phase)
                _render_pad(samples, rate, start, 8.0, float(chords[ci]["bass"]), 0.15, phase, true)
        # Gentle tine melody from F pentatonic; every note ends before the seam.
        var tines := [[1.1, 440.0, 0.15], [4.3, 523.25, 0.14], [6.4, 392.0, 0.13],
                [9.4, 329.63, 0.15], [12.6, 440.0, 0.12]]
        for ev in tines:
                _render_tine(samples, rate, float(ev[0]), float(ev[1]), float(ev[2]))

## Game: A-minor drone bed (A2 + E3 over an A1 floor) with a slow breathing
## swell and three near-whisper bells. No rhythm - the clock owns rhythm.
static func _forge_game(samples: PackedFloat32Array) -> void:
        var rate := float(RATE)
        var n := samples.size()
        var drones := [[110.0, 0.13], [164.81, 0.085], [55.0, 0.10]]
        for d in drones:
                var freq := float(d[0])
                var gain := float(d[1])
                for i in n:
                        var t := float(i) / rate
                        var env := minf(1.0, t / 2.5) * minf(1.0, (LOOP_LEN - t) / 2.5)
                        if env <= 0.0:
                                continue
                        var lfo := 0.75 + 0.25 * sin(TAU * 0.09 * t + 1.3)
                        samples[i] += (sin(TAU * freq * t) + 0.22 * sin(TAU * freq * 2.0 * t)) \
                                        * env * gain * lfo
        var bells := [[5.2, 329.63, 0.085], [11.8, 261.63, 0.075], [14.0, 196.0, 0.06]]
        for ev in bells:
                _render_tine(samples, rate, float(ev[0]), float(ev[1]), float(ev[2]))

# --- voices ----------------------------------------------------------------------------

static func _render_pad(samples: PackedFloat32Array, rate: float, t0: float, dur: float,
                freq: float, gain: float, phase: float, is_bass := false) -> void:
        var n := samples.size()
        var i0 := maxi(0, int(t0 * rate))
        var i1 := mini(n, int((t0 + dur) * rate))
        for i in range(i0, i1):
                var t := float(i) / rate - t0
                var env := minf(1.0, t / 1.6) * minf(1.0, (dur - t) / 2.2)
                if env <= 0.0:
                        continue
                var v: float
                if is_bass:
                        v = (sin(TAU * freq * t) + 0.28 * sin(TAU * freq * 2.0 * t)) * env * gain
                else:
                        var lfo := 0.88 + 0.12 * sin(TAU * (0.13 * t + phase))
                        v = (sin(TAU * freq * t) + 0.32 * sin(TAU * freq * 2.0 * t) \
                                        + 0.10 * sin(TAU * freq * 3.01 * t)) * env * gain * lfo
                samples[i] += v

static func _render_tine(samples: PackedFloat32Array, rate: float, t0: float,
                freq: float, gain: float) -> void:
        var dur := 0.9
        var n := samples.size()
        var i0 := maxi(0, int(t0 * rate))
        var i1 := mini(n, int((t0 + dur) * rate))
        for i in range(i0, i1):
                var t := float(i) / rate - t0
                var v := Sfx._bell(t, freq, 0.0, 6.0) * gain
                v *= minf(1.0, t / 0.002) * minf(1.0, (dur - t) / 0.02)
                samples[i] += v

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
