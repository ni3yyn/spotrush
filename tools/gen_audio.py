#!/usr/bin/env python3
"""
Faithful Python port of SpotRush's procedural audio (scripts/core/Sfx.gd and
scripts/core/Music.gd), used once to bake the current runtime-synthesized
sound bank into real .wav files. Every formula below is copied 1:1 from the
GDScript source (same durations, envelopes, frequencies, gains); the only
intentional deviation is the RNG backing Sfx's noise texture ("press"/
"whoosh") and Music's random brush scratches, which used Godot's own
RandomNumberGenerator - that can't be reproduced bit-for-bit outside the
engine, so Python's random module is used instead, seeded for a reproducible
build. The audible character (filtered noise texture, not exact samples) is
what matters there, not sample-identical output.

Writes mono 16-bit PCM WAV files to assets/audio/{sfx,notes,music}/, which
Sfx.gd/Music.gd load in preference to synthesizing at runtime (see the
"baked asset" comments at the top of each). Re-run this (`python3 gen_audio.py`,
no dependencies beyond the standard library) any time the formulas in
Sfx.gd/Music.gd change, so the baked files stay in sync with the source of
truth. tools/ExtractAudio.gd does the same job by calling the GDScript
directly through the Godot editor instead - either one keeps both in sync;
this one is just runnable from a plain terminal.
"""
import math
import os
import random
import struct

RATE = 44100
TAU = 2.0 * math.pi

OUT_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def write_wav(path: str, samples) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = bytearray()
    for v in samples:
        v = max(-1.0, min(1.0, v))
        iv = int(round(v * 32767.0))
        data += struct.pack("<h", iv)
    channels = 1
    bits = 16
    byte_rate = RATE * channels * bits // 8
    block_align = channels * bits // 8
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + len(data)))
        f.write(b"WAVE")
        f.write(b"fmt ")
        f.write(struct.pack("<I", 16))
        f.write(struct.pack("<H", 1))  # PCM
        f.write(struct.pack("<H", channels))
        f.write(struct.pack("<I", RATE))
        f.write(struct.pack("<I", byte_rate))
        f.write(struct.pack("<H", block_align))
        f.write(struct.pack("<H", bits))
        f.write(b"data")
        f.write(struct.pack("<I", len(data)))
        f.write(bytes(data))


# --- Sfx.gd port ---------------------------------------------------------------

SFX_DURATIONS = {
    "press": 0.085, "release": 0.05, "pop": 0.12, "correct": 0.5, "wrong": 0.3,
    "tick": 0.045, "whoosh": 0.34, "spot": 0.34, "pip": 0.14, "count": 0.03,
    "chime": 0.85, "fanfare": 1.0, "toggle_on": 0.09, "toggle_off": 0.09,
}

SFX_NAMES = ["press", "release", "pop", "correct", "wrong", "tick", "whoosh",
             "spot", "pip", "count", "chime", "fanfare", "toggle_on", "toggle_off"]


def bell(t, freq, start, decay):
    tt = t - start
    if tt < 0.0:
        return 0.0
    env = math.exp(-tt * decay)
    return (math.sin(TAU * freq * tt) + 0.34 * math.sin(TAU * freq * 2.0 * tt)
            + 0.11 * math.sin(TAU * freq * 3.01 * tt)) * env * min(1.0, tt / 0.002)


def build_sfx(sound: str):
    dur = SFX_DURATIONS[sound]
    n = int(RATE * dur)
    samples = [0.0] * n
    rng = random.Random(7)  # mirrors GDScript's rng.seed = 7
    lp = 0.0
    lp2 = 0.0
    for i in range(n):
        t = i / RATE
        p = t / dur
        v = 0.0
        if sound == "press":
            f = 160.0 * math.exp(-t * 14.0) + 150.0
            v = (math.sin(TAU * f * t) + 0.25 * math.sin(TAU * f * 2.0 * t)) * math.exp(-t * 55.0) * 0.52
            lp = lp + (rng.uniform(-1.0, 1.0) - lp) * 0.18
            v += lp * math.exp(-t * 170.0) * 0.20
        elif sound == "release":
            v = math.sin(TAU * 640.0 * t) * math.exp(-t * 115.0) * 0.20
        elif sound == "pop":
            f2 = 260.0 + 520.0 * math.sqrt(max(0.0, min(1.0, p * 3.0)))
            v = (math.sin(TAU * f2 * t) + 0.18 * math.sin(TAU * f2 * 2.0 * t)) * math.exp(-t * 32.0) * 0.46
        elif sound == "correct":
            v = bell(t, 523.25, 0.0, 6.5) * 0.34 + bell(t, 783.99, 0.085, 6.0) * 0.30
        elif sound == "wrong":
            f3 = 150.0 + 125.0 * math.exp(-t * 16.0)
            v = (math.sin(TAU * f3 * t) + 0.30 * math.sin(TAU * f3 * 2.0 * t)) * math.exp(-t * 11.0) * 0.46
        elif sound == "tick":
            v = math.sin(TAU * 1040.0 * t) * math.exp(-t * 150.0) * 0.26
        elif sound == "whoosh":
            cutoff = 0.03 + (0.26 - 0.03) * (p * p)
            lp = lp + (rng.uniform(-1.0, 1.0) - lp) * cutoff
            lp2 = lp2 + (lp - lp2) * cutoff
            v = lp2 * (math.sin(math.pi * p) ** 2) * 1.45
        elif sound == "spot":
            f4 = 330.0 * math.exp(-t * 8.0) + 220.0
            v = math.sin(TAU * f4 * t) * math.exp(-t * 12.0) * 0.46
            v += bell(t, 660.0, 0.0, 9.0) * 0.18
            v += math.sin(TAU * 115.0 * t) * math.exp(-t * 26.0) * 0.24
        elif sound == "pip":
            v = (math.sin(TAU * 1318.5 * t) + 0.28 * math.sin(TAU * 2637.0 * t)) * math.exp(-t * 36.0) * 0.20
        elif sound == "count":
            v = math.sin(TAU * 900.0 * t) * math.exp(-t * 190.0) * 0.12
        elif sound == "chime":
            v = bell(t, 880.0, 0.0, 4.6) * 0.26 + bell(t, 1318.5, 0.0, 5.2) * 0.14 + bell(t, 1760.0, 0.0, 6.0) * 0.08
        elif sound == "fanfare":
            v = bell(t, 523.25, 0.0, 5.0) * 0.26 + bell(t, 659.25, 0.12, 5.0) * 0.26 \
                + bell(t, 783.99, 0.24, 5.0) * 0.26 + bell(t, 1046.5, 0.36, 3.6) * 0.30
        elif sound == "toggle_on":
            f5 = 520.0 + (840.0 - 520.0) * min(p * 2.0, 1.0)
            v = math.sin(TAU * f5 * t) * math.exp(-t * 42.0) * 0.30
        elif sound == "toggle_off":
            f6 = 840.0 + (520.0 - 840.0) * min(p * 2.0, 1.0)
            v = math.sin(TAU * f6 * t) * math.exp(-t * 42.0) * 0.26
        v *= min(1.0, t / 0.002) * min(1.0, (dur - t) / 0.008)
        samples[i] = math.tanh(v * 1.1)
    return samples


def build_note(freq: float):
    dur = 0.42
    n = int(RATE * dur)
    samples = [0.0] * n
    for i in range(n):
        t = i / RATE
        v = bell(t, freq, 0.0, 9.0) * 0.30 + bell(t, freq * 2.0, 0.0, 12.0) * 0.09
        v *= min(1.0, t / 0.002) * min(1.0, (dur - t) / 0.02)
        samples[i] = math.tanh(v * 1.05)
    return samples


# --- Music.gd port --------------------------------------------------------------

LOOP_LEN = 32.0
MENU_PEAK = 0.43
GAME_PEAK = 0.90


def smooth_unit(v):
    x = max(0.0, min(1.0, v))
    return x * x * (3.0 - 2.0 * x)


def render_warm_pad(samples, rate, t0, dur, freq, gain, phase, is_bass=False):
    i0 = max(0, int(t0 * rate))
    i1 = min(len(samples), int((t0 + dur) * rate))
    attack = 2.0 if is_bass else 2.5
    release = 2.2 if is_bass else 2.7
    for i in range(i0, i1):
        t = i / rate - t0
        fade_in = smooth_unit(t / attack)
        fade_out = smooth_unit((dur - t) / release)
        env = fade_in * fade_out
        if env <= 0.0001:
            continue
        breathe = 0.91 + 0.09 * math.sin(TAU * 0.038 * t + phase)
        fundamental = math.sin(TAU * freq * t + phase)
        if is_bass:
            voice = fundamental * 0.88 + math.sin(TAU * freq * 2.0 * t + phase * 0.5) * 0.12
        else:
            detuned = math.sin(TAU * (freq * 1.0022) * t + phase + 0.55)
            warm_partial = math.sin(TAU * freq * 2.0 * t + phase * 0.4)
            voice = fundamental * 0.76 + detuned * 0.19 + warm_partial * 0.05
        samples[i] += voice * env * gain * breathe


def render_soft_note(samples, rate, t0, freq, gain, dur):
    i0 = max(0, int(t0 * rate))
    i1 = min(len(samples), int((t0 + dur) * rate))
    for i in range(i0, i1):
        t = i / rate - t0
        attack = 1.0 - math.exp(-t * 5.5)
        decay = math.exp(-t * 0.92)
        fundamental = math.sin(TAU * freq * t)
        octave = math.sin(TAU * freq * 2.0 * t + 0.18)
        fifth = math.sin(TAU * freq * 3.0 * t + 0.31)
        tone = fundamental * 0.80 + octave * 0.155 + fifth * 0.045
        tail = smooth_unit((dur - t) / 0.42)
        samples[i] += tone * attack * decay * tail * gain


def apply_volume_dips(samples, rate, dips):
    n = len(samples)
    for i in range(n):
        time = i / rate
        level = 1.0
        for start, floor_level, fall_time, hold_time, rise_time in dips:
            local = time - start
            if local < 0.0 or local >= fall_time + hold_time + rise_time:
                continue
            if local < fall_time:
                current = 1.0 + (floor_level - 1.0) * smooth_unit(local / fall_time)
            elif local < fall_time + hold_time:
                current = floor_level
            else:
                progress = (local - fall_time - hold_time) / rise_time
                current = floor_level + (1.0 - floor_level) * smooth_unit(progress)
            level = min(level, current)
        samples[i] *= level


def add_random_scratches(samples, rate, count, amplitude, seed):
    rng = random.Random(seed)
    n = len(samples)
    for _ in range(count):
        start = rng.uniform(1.8, LOOP_LEN - 2.2)
        duration = rng.uniform(0.18, 0.36)
        from_hz = rng.uniform(420.0, 820.0)
        to_hz = rng.uniform(250.0, 520.0)
        phase = rng.uniform(0.0, TAU)
        first = max(0, int(start * rate))
        last = min(n, int((start + duration) * rate))
        filtered_noise = 0.0
        for i in range(first, last):
            t = i / rate - start
            x = max(0.0, min(1.0, t / duration))
            envelope = math.sin(math.pi * x)
            envelope *= envelope
            noise = rng.uniform(-1.0, 1.0)
            filtered_noise += (noise - filtered_noise) * 0.10
            sweep_hz = from_hz + (to_hz - from_hz) * x
            friction = noise * 0.07 + filtered_noise * 0.58 + math.sin(TAU * sweep_hz * t + phase) * 0.35
            samples[i] += friction * envelope * amplitude


def soften(samples, amount):
    filtered = 0.0
    for i in range(len(samples)):
        filtered += (samples[i] - filtered) * amount
        samples[i] = filtered


def normalize(samples, target):
    peak = max(abs(v) for v in samples) if samples else 0.0
    if peak <= 0.0001:
        return
    g = target / peak
    for i in range(len(samples)):
        samples[i] *= g


def forge_menu(samples, rate):
    chords = [
        {"start": 0.0, "dur": 8.0, "bass": 87.31, "pad": [174.61, 220.0, 261.63, 329.63, 392.0]},
        {"start": 6.0, "dur": 10.0, "bass": 73.42, "pad": [146.83, 174.61, 220.0, 261.63, 329.63]},
        {"start": 14.0, "dur": 10.0, "bass": 55.0, "pad": [130.81, 164.81, 196.0, 246.94, 329.63]},
        {"start": 22.0, "dur": 10.0, "bass": 65.41, "pad": [130.81, 164.81, 196.0, 246.94, 293.66]},
    ]
    for ci, chord in enumerate(chords):
        begin = chord["start"]
        duration = chord["dur"]
        phase = ci * 1.31
        for j, padf in enumerate(chord["pad"]):
            gain = 0.042 if j < 3 else 0.030
            render_warm_pad(samples, rate, begin, duration, padf, gain, phase + j * 0.37)
        render_warm_pad(samples, rate, begin, duration, chord["bass"], 0.092, phase, True)

    notes = [
        [3.0, 392.0, 0.056, 3.8], [9.4, 349.23, 0.054, 3.8], [15.5, 329.63, 0.055, 3.8],
        [21.0, 246.94, 0.056, 3.8], [27.0, 293.66, 0.056, 3.8],
    ]
    answers = [
        [4.55, 329.63, 0.030, 2.8], [10.95, 293.66, 0.029, 2.8], [17.05, 261.63, 0.030, 2.8],
        [22.65, 196.00, 0.031, 2.8], [28.55, 246.94, 0.030, 2.8],
    ]
    for ev in notes + answers:
        render_soft_note(samples, rate, ev[0], ev[1], ev[2], ev[3])


def forge_game(samples, rate):
    chords = [
        {"start": 0.0, "dur": 8.0, "bass": 55.0, "pad": [110.0, 164.81, 220.0, 261.63]},
        {"start": 6.0, "dur": 10.0, "bass": 43.65, "pad": [87.31, 130.81, 174.61, 220.0]},
        {"start": 14.0, "dur": 10.0, "bass": 65.41, "pad": [130.81, 164.81, 196.0, 246.94]},
        {"start": 22.0, "dur": 10.0, "bass": 49.0, "pad": [98.0, 146.83, 196.0, 293.66]},
    ]
    for ci, chord in enumerate(chords):
        begin = chord["start"]
        duration = chord["dur"]
        phase = ci * 0.83 + 0.6
        for j, padf in enumerate(chord["pad"]):
            gain = 0.030 if j < 3 else 0.020
            render_warm_pad(samples, rate, begin, duration, padf, gain, phase + j * 0.29)
        render_warm_pad(samples, rate, begin, duration, chord["bass"], 0.075, phase, True)

    notes = [
        [2.8, 220.0, 0.071, 4.0], [9.4, 261.63, 0.069, 4.0], [15.7, 196.0, 0.072, 4.0],
        [21.6, 164.81, 0.069, 4.0], [27.4, 220.0, 0.071, 4.0],
    ]
    answers = [
        [4.45, 329.63, 0.038, 2.9], [11.0, 293.66, 0.037, 2.9], [17.3, 261.63, 0.039, 2.9],
        [23.1, 246.94, 0.037, 2.9], [28.95, 293.66, 0.038, 2.9],
    ]
    for ev in notes + answers:
        render_soft_note(samples, rate, ev[0], ev[1], ev[2], ev[3])


def build_music(kind: str):
    rate = float(RATE)
    n = int(RATE * LOOP_LEN)
    samples = [0.0] * n
    if kind == "menu":
        forge_menu(samples, rate)
        add_random_scratches(samples, rate, 3, 0.009, seed=101)
        apply_volume_dips(samples, rate, [
            [7.0, 0.22, 0.10, 0.12, 0.78],
            [17.0, 0.26, 0.11, 0.14, 0.88],
            [25.2, 0.24, 0.10, 0.12, 0.82],
        ])
        soften(samples, 0.30)
        normalize(samples, MENU_PEAK)
    else:
        forge_game(samples, rate)
        add_random_scratches(samples, rate, 3, 0.0055, seed=202)
        apply_volume_dips(samples, rate, [
            [11.6, 0.46, 0.10, 0.16, 0.92],
            [24.0, 0.52, 0.10, 0.14, 0.86],
        ])
        soften(samples, 0.27)
        normalize(samples, GAME_PEAK)
    return samples


# --- Notes needed by Feel.gd (melody + combo_jingle + band_change) --------------

MELODY = [
    523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,
    698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,
    783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,
    783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,
    523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,
    698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,
]


def needed_note_freqs():
    freqs = {}
    for f in MELODY:
        freqs[int(round(f * 100.0))] = f
    for base in (523.25, 659.25, 783.99):
        for mult in (1.0, 1.26, 1.50):
            f = base * mult
            freqs[int(round(f * 100.0))] = f
    for mult in (1.0, 1.50, 0.75):
        f = 587.33 * mult
        freqs[int(round(f * 100.0))] = f
    return freqs


def main():
    print("Building sfx...")
    for name in SFX_NAMES:
        samples = build_sfx(name)
        write_wav(os.path.join(OUT_ROOT, "sfx", f"{name}.wav"), samples)
        print(f"  {name}: {len(samples)} samples ({len(samples)/RATE:.3f}s)")

    print("Building notes...")
    freqs = needed_note_freqs()
    for key, f in sorted(freqs.items()):
        samples = build_note(f)
        write_wav(os.path.join(OUT_ROOT, "notes", f"note_{key}.wav"), samples)
    print(f"  wrote {len(freqs)} notes")

    print("Building music (this takes a bit - it's a lot of samples)...")
    for kind in ("menu", "game"):
        samples = build_music(kind)
        write_wav(os.path.join(OUT_ROOT, "music", f"{kind}_loop.wav"), samples)
        print(f"  {kind}: {len(samples)} samples ({len(samples)/RATE:.1f}s)")

    print("Done.")


if __name__ == "__main__":
    main()
