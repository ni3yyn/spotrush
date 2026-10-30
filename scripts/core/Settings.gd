extends RefCounted

# Persisted player settings (sound, haptics, particles, reduce motion).
# Stored in user:// so they survive restarts; read through tiny static helpers.

const PATH := "user://spotrush_settings.cfg"

static var _cfg: ConfigFile = null

static func _ensure() -> ConfigFile:
        if _cfg == null:
                _cfg = ConfigFile.new()
                _cfg.load(PATH) # missing file is fine: defaults apply
        return _cfg

static func get_bool(key: String, default_value: bool) -> bool:
        return bool(_ensure().get_value("feel", key, default_value))

static func set_bool(key: String, value: bool) -> void:
        var cfg := _ensure()
        cfg.set_value("feel", key, value)
        cfg.save(PATH)

static func get_string(key: String, default_value: String) -> String:
        return str(_ensure().get_value("feel", key, default_value))

static func set_string(key: String, value: String) -> void:
        var cfg := _ensure()
        cfg.set_value("feel", key, value)
        cfg.save(PATH)

## Colour vision mode: "off" / "deutan" / "protan" / "tritan" (v18).
## Presentation-only: challenge generation never reads it, so shared seeds,
## duels and rival codes stay identical no matter which mode a phone runs.
static func colorblind() -> String: return get_string("colorblind", "off")
static func set_colorblind(mode: String) -> void: set_string("colorblind", mode)

static func sfx() -> bool: return get_bool("sfx", true)
static func haptics() -> bool: return get_bool("haptics", true)
static func particles() -> bool: return get_bool("particles", true)
## Calms the UI: no staggered entrances, shakes, bursts or squish; transitions get very short.
static func reduce_motion() -> bool: return get_bool("reduce_motion", false)

# --- Audio volumes (v20) ---------------------------------------------------------------

## Music level on the Music bus, 0..1 (default 80%).
static func music_volume() -> float:
        return clampf(float(_ensure().get_value("audio", "music_volume", 0.8)), 0.0, 1.0)

static func set_music_volume(v: float) -> void:
        var cfg := _ensure()
        cfg.set_value("audio", "music_volume", clampf(v, 0.0, 1.0))
        cfg.save(PATH)
        apply_audio_volumes()

## Effects level on the SFX bus, 0..1 (default 100%).
static func sfx_volume() -> float:
        return clampf(float(_ensure().get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)

static func set_sfx_volume(v: float) -> void:
        var cfg := _ensure()
        cfg.set_value("audio", "sfx_volume", clampf(v, 0.0, 1.0))
        cfg.save(PATH)
        apply_audio_volumes()

## Push both levels onto their buses. Called at boot (Music autoload) and on
## every slider move. Buses come from default_bus_layout.tres.
static func apply_audio_volumes() -> void:
        _apply_bus("Music", music_volume())
        _apply_bus("SFX", sfx_volume())

static func _apply_bus(bus_name: String, level: float) -> void:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx < 0:
                return
        AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.0001)))
        AudioServer.set_bus_mute(idx, level <= 0.001)

# --- Daily streak reminder (v21) -------------------------------------------------------

## Opt-in: the daily nudge never fires unless the player turned it on.
static func reminder_enabled() -> bool:
        return bool(_ensure().get_value("reminders", "reminder_enabled", false))

static func set_reminder_enabled(v: bool) -> void:
        var cfg := _ensure()
        cfg.set_value("reminders", "reminder_enabled", bool(v))
        cfg.save(PATH)

## Test helper: drop the cached file so the next read comes from disk.
static func reload() -> void:
        _cfg = null

# --- Match preference ------------------------------------------------------------------

static func match_rounds() -> int:
        var value := int(_ensure().get_value("match", "rounds", 10))
        return value if value in [5, 10, 15] else 10

static func set_match_rounds(rounds: int) -> void:
        var value := 5 if rounds <= 5 else (10 if rounds <= 10 else 15)
        var cfg := _ensure()
        cfg.set_value("match", "rounds", value)
        cfg.save(PATH)
