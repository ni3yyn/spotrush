extends RefCounted

# Soft synthesized sound bank. Everything is generated once from maths (no audio assets),
# then cached as AudioStreamWAV. The palette is deliberately round and muted - sine/bell
# tones with quick decays and a gentle low-pass - to match the soft UI instead of the
# harsh square/saw blips typical of procedural sfx.

const RATE := 32000

static var _bank: Dictionary = {}
static var _root: Node = null
static var _voices: Array = []
static var _next_voice: int = 0

class VoiceRoot extends Node:
        func _exit_tree() -> void:
                for child in get_children():
                        if child is AudioStreamPlayer:
                                child.stop()
                                child.stream = null

# --- public ---------------------------------------------------------------------------

static func play(sound: String, pitch: float = 1.0, gain_db: float = 0.0) -> void:
        if DisplayServer.get_name() == "headless":
                return
        _ensure_voices()
        if _voices.is_empty():
                return
        var voice: AudioStreamPlayer = _voices[_next_voice]
        _next_voice = (_next_voice + 1) % _voices.size()
        if not voice.is_inside_tree():
                return # first frame before the audio node is attached; dropping one blip is fine
        voice.stream = get_stream(sound)
        voice.pitch_scale = clampf(pitch, 0.5, 2.0)
        voice.volume_db = gain_db
        voice.play()

static func get_stream(sound: String) -> AudioStreamWAV:
        if not _bank.has(sound):
                _bank[sound] = _build(sound)
        return _bank[sound]

## Builds every sound up front (about a few ms each) so the first tap never hitches.
static func warm_up() -> void:
        for name in names():
                get_stream(name)

static func names() -> PackedStringArray:
        return PackedStringArray(["press", "release", "pop", "correct", "wrong", "tick", "whoosh", "spot",
                "pip", "count", "chime", "fanfare", "toggle_on", "toggle_off"])

# --- melody notes ---------------------------------------------------------------------

## Musical note voice for the typing melody: a soft glassy "tine" scaled to any
## pitch. Streams are cached per rounded frequency and built on first use, so a
## fresh pitch costs one tiny build the first time it is played.
static func play_note(freq: float, gain_db: float = -3.0) -> void:
        if DisplayServer.get_name() == "headless":
                return
        _ensure_voices()
        if _voices.is_empty():
                return
        var voice: AudioStreamPlayer = _voices[_next_voice]
        _next_voice = (_next_voice + 1) % _voices.size()
        if not voice.is_inside_tree():
                return # first frame before the audio node is attached; dropping one blip is fine
        voice.stream = note_stream(freq)
        voice.pitch_scale = 1.0
        voice.volume_db = gain_db
        voice.play()

static func note_stream(freq: float) -> AudioStreamWAV:
        var key := "note_%d" % int(round(freq * 100.0))
        if not _bank.has(key):
                _bank[key] = _build_note(freq)
        return _bank[key]

# --- voices ---------------------------------------------------------------------------

static func _ensure_voices() -> void:
        if _root != null and is_instance_valid(_root):
                return
        var tree := Engine.get_main_loop() as SceneTree
        if tree == null:
                return
        _root = VoiceRoot.new()
        _root.name = "FeelAudio"
        _voices.clear()
        for i in 8:
                var p := AudioStreamPlayer.new()
                p.bus = &"SFX"
                _root.add_child(p)
                _voices.append(p)
        # The root may still be busy setting up its children on the very first frame.
        tree.root.add_child.call_deferred(_root)

# --- synthesis ------------------------------------------------------------------------

static func _build(sound: String) -> AudioStreamWAV:
        var dur := 0.1
        match sound:
                "press": dur = 0.085
                "release": dur = 0.05
                "pop": dur = 0.12
                "correct": dur = 0.5
                "wrong": dur = 0.3
                "tick": dur = 0.045
                "whoosh": dur = 0.34
                "spot": dur = 0.34
                "pip": dur = 0.14
                "count": dur = 0.03
                "chime": dur = 0.85
                "fanfare": dur = 1.0
                "toggle_on", "toggle_off": dur = 0.09
        var n := int(RATE * dur)
        var samples := PackedFloat32Array()
        samples.resize(n)
        var rng := RandomNumberGenerator.new()
        rng.seed = 7
        var lp := 0.0
        var lp2 := 0.0
        for i in n:
                var t := float(i) / float(RATE)
                var p := t / dur
                var v := 0.0
                match sound:
                        "press": # soft low "thock": pitch-dropping sine plus a muffled click
                                var f := 160.0 * exp(-t * 14.0) + 150.0
                                v = (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t)) * exp(-t * 55.0) * 0.52
                                lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
                                v += lp * exp(-t * 170.0) * 0.20
                        "release": # light, higher "tick"
                                v = sin(TAU * 640.0 * t) * exp(-t * 115.0) * 0.20
                        "pop": # bubble: fast upward sweep
                                var f2 := 260.0 + 520.0 * sqrt(clampf(p * 3.0, 0.0, 1.0))
                                v = (sin(TAU * f2 * t) + 0.18 * sin(TAU * f2 * 2.0 * t)) * exp(-t * 32.0) * 0.46
                        "correct": # two glassy bell notes, C5 then G5
                                v = _bell(t, 523.25, 0.0, 6.5) * 0.34 + _bell(t, 783.99, 0.085, 6.0) * 0.30
                        "wrong": # muted "bonk": low sine sinking, no harsh edges
                                var f3 := 150.0 + 125.0 * exp(-t * 16.0)
                                v = (sin(TAU * f3 * t) + 0.30 * sin(TAU * f3 * 2.0 * t)) * exp(-t * 11.0) * 0.46
                        "tick": # clock-like blip
                                v = sin(TAU * 1040.0 * t) * exp(-t * 150.0) * 0.26
                        "whoosh": # breath of filtered noise sweeping upward
                                var cutoff := lerpf(0.03, 0.26, p * p)
                                lp = lerpf(lp, rng.randf_range(-1.0, 1.0), cutoff)
                                lp2 = lerpf(lp2, lp, cutoff) # second pole: steeper roll-off, less hiss
                                v = lp2 * pow(sin(PI * p), 2.0) * 1.45
                        "spot": # punchy chord with a sub thump
                                var f4 := 330.0 * exp(-t * 8.0) + 220.0
                                v = sin(TAU * f4 * t) * exp(-t * 12.0) * 0.46
                                v += _bell(t, 660.0, 0.0, 9.0) * 0.18
                                v += sin(TAU * 115.0 * t) * exp(-t * 26.0) * 0.24
                        "pip": # tiny glass tink
                                v = (sin(TAU * 1318.5 * t) + 0.28 * sin(TAU * 2637.0 * t)) * exp(-t * 36.0) * 0.20
                        "count": # barely-there counter tick
                                v = sin(TAU * 900.0 * t) * exp(-t * 190.0) * 0.12
                        "chime": # medal: bright bell with fifth and octave
                                v = _bell(t, 880.0, 0.0, 4.6) * 0.26 + _bell(t, 1318.5, 0.0, 5.2) * 0.14 + _bell(t, 1760.0, 0.0, 6.0) * 0.08
                        "fanfare": # C-E-G-C arpeggio
                                v = _bell(t, 523.25, 0.0, 5.0) * 0.26 + _bell(t, 659.25, 0.12, 5.0) * 0.26 \
                                        + _bell(t, 783.99, 0.24, 5.0) * 0.26 + _bell(t, 1046.5, 0.36, 3.6) * 0.30
                        "toggle_on":
                                var f5 := lerpf(520.0, 840.0, minf(p * 2.0, 1.0))
                                v = sin(TAU * f5 * t) * exp(-t * 42.0) * 0.30
                        "toggle_off":
                                var f6 := lerpf(840.0, 520.0, minf(p * 2.0, 1.0))
                                v = sin(TAU * f6 * t) * exp(-t * 42.0) * 0.26
                # 2 ms fade-in and 8 ms fade-out keep every sound click-free.
                v *= minf(1.0, t / 0.002) * minf(1.0, (dur - t) / 0.008)
                samples[i] = tanh(v * 1.1)
        return _to_wav(samples)

## A soft struck tine for melody notes: the fundamental plus a quiet octave
## above, warm exponential decay, the same rounded character as the bank.
static func _build_note(freq: float) -> AudioStreamWAV:
        var dur := 0.42
        var n := int(RATE * dur)
        var samples := PackedFloat32Array()
        samples.resize(n)
        for i in n:
                var t := float(i) / float(RATE)
                var v := _bell(t, freq, 0.0, 9.0) * 0.30 + _bell(t, freq * 2.0, 0.0, 12.0) * 0.09
                v *= minf(1.0, t / 0.002) * minf(1.0, (dur - t) / 0.02)
                samples[i] = tanh(v * 1.05)
        return _to_wav(samples)

## A struck-bell partial stack: fundamental plus softer 2nd/3rd harmonics, exponential decay.
static func _bell(t: float, freq: float, start: float, decay: float) -> float:
        var tt := t - start
        if tt < 0.0:
                return 0.0
        var env := exp(-tt * decay)
        return (sin(TAU * freq * tt) + 0.34 * sin(TAU * freq * 2.0 * tt) + 0.11 * sin(TAU * freq * 3.01 * tt)) * env * minf(1.0, tt / 0.002)

static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
        var data := PackedByteArray()
        data.resize(samples.size() * 2)
        for i in samples.size():
                data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
        var wav := AudioStreamWAV.new()
        wav.format = AudioStreamWAV.FORMAT_16_BITS
        wav.mix_rate = RATE
        wav.stereo = false
        wav.data = data
        return wav
