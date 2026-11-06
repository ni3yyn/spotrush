extends SceneTree

# One-off dev tool: run the project's own procedural synthesis (Sfx.gd / Music.gd)
# exactly as the game would, and write the results to real .wav files on disk.
# This is the "bake" step behind swapping runtime synthesis for static assets -
# run it again any time the sound design in Sfx.gd/Music.gd/Feel.gd changes, to
# refresh the baked files. Not part of the shipped game; lives under tools/.
#
# Run with:
#   Godot_v4.7-stable_linux.x86_64 --headless --path <project_dir> --script res://tools/ExtractAudio.gd

const Sfx = preload("res://scripts/core/Sfx.gd")
const MusicScript = preload("res://scripts/core/Music.gd")

const OUT_SFX_DIR := "res://assets/audio/sfx/"
const OUT_NOTES_DIR := "res://assets/audio/notes/"
const OUT_MUSIC_DIR := "res://assets/audio/music/"

# Mirrors Feel.gd's MELODY array plus every scaled frequency combo_jingle()/
# band_change() ever actually passes to Sfx.play_note() - these two functions
# compute their notes from a base * a fixed multiplier rather than pulling
# from MELODY, so they're listed explicitly here to make sure nothing is missed.
const MELODY := [
	523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,
	698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,
	783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,
	783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33,
	523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99,
	698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25,
]

func _init() -> void:
	var out_root := ProjectSettings.globalize_path("res://assets/audio")
	DirAccess.make_dir_recursive_absolute(out_root + "/sfx")
	DirAccess.make_dir_recursive_absolute(out_root + "/notes")
	DirAccess.make_dir_recursive_absolute(out_root + "/music")

	var count := 0
	for sound_name in Sfx.names():
		var wav: AudioStreamWAV = Sfx.get_stream(sound_name)
		_write_wav(OUT_SFX_DIR + sound_name + ".wav", wav)
		count += 1
	print("[extract] wrote %d sfx" % count)

	var note_freqs := {}
	for f in MELODY:
		note_freqs[int(round(float(f) * 100.0))] = float(f)
	for tier_base in [523.25, 659.25, 783.99]:
		for mult in [1.0, 1.26, 1.50]:
			var f: float = tier_base * mult
			note_freqs[int(round(f * 100.0))] = f
	var band_base := 587.33
	for mult in [1.0, 1.50, 0.75]:
		var f: float = band_base * mult
		note_freqs[int(round(f * 100.0))] = f

	count = 0
	for key in note_freqs:
		var freq: float = note_freqs[key]
		var wav: AudioStreamWAV = Sfx.note_stream(freq)
		_write_wav(OUT_NOTES_DIR + ("note_%d.wav" % int(key)), wav)
		count += 1
	print("[extract] wrote %d notes" % count)

	for kind in ["menu", "game"]:
		var wav: AudioStreamWAV = MusicScript.build_stream(kind)
		_write_wav(OUT_MUSIC_DIR + kind + "_loop.wav", wav)
		print("[extract] wrote music: %s (%.1fs, %d bytes)" % [kind, float(wav.data.size()) / 2.0 / float(wav.mix_rate), wav.data.size()])

	print("[extract] done")
	quit()

## AudioStreamWAV only holds raw PCM16 + a mix rate/channel count - there is no
## built-in "save to disk as .wav" call, so build the 44-byte RIFF/WAVE header
## by hand and write the PCM payload straight after it.
func _write_wav(res_path: String, wav: AudioStreamWAV) -> void:
	var path := ProjectSettings.globalize_path(res_path)
	var data: PackedByteArray = wav.data
	var channels := 2 if wav.stereo else 1
	var bits_per_sample := 16
	var byte_rate := wav.mix_rate * channels * bits_per_sample / 8
	var block_align := channels * bits_per_sample / 8

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not open %s for writing (err %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string("RIFF")
	f.store_32(36 + data.size())
	f.store_string("WAVE")
	f.store_string("fmt ")
	f.store_32(16)
	f.store_16(1) # PCM
	f.store_16(channels)
	f.store_32(wav.mix_rate)
	f.store_32(byte_rate)
	f.store_16(block_align)
	f.store_16(bits_per_sample)
	f.store_string("data")
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
