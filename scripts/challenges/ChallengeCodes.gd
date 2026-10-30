class_name ChallengeCodes
extends RefCounted

## v17 RIVAL CODES - the async challenge codec.
##
## A challenge code is a run's identity compressed into something a friend can
## type over a chat message: 9 characters, grouped XXX-XXX-XXX. Inside those
## 45 bits rides everything the Run Forge needs to deal the identical series
## on another phone - the seed, the round count, the difficulty anchor and a
## mode tag - plus a 6-bit checksum so a mistyped character fails loudly
## instead of dealing a stranger's run.
##
## The alphabet is base36 with the near-miss glyphs EXCLUDED (no O, I, L),
## Crockford-style - 33 symbols, 9 slots = 4.6e13 codes, more than the 45-bit
## space needs. On input the excluded glyphs are forgiven anyway (O reads as
## 0, I/L as 1), so display and parse agree by construction and a printed
## code never survives its own round-trip as a different code.
## No server, no accounts, no state: the code IS the match.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTUVWXYZ"
const ALPHABET_SIZE := 33
const CODE_CHARS := 9
const GROUP := 3

# Payload layout (39 bits): seed 30 | rounds 5 | band 2 | mode 2.
const SEED_BITS := 30
const ROUNDS_BITS := 5
const BAND_BITS := 2
const MODE_BITS := 2
const PAYLOAD_BITS := SEED_BITS + ROUNDS_BITS + BAND_BITS + MODE_BITS # 39
const CHECK_BITS := 6
const TOTAL_BITS := PAYLOAD_BITS + CHECK_BITS # 45

const MODE_CHALLENGE_RUN := 0

const SEED_MASK := (1 << SEED_BITS) - 1
const ROUNDS_MASK := (1 << ROUNDS_BITS) - 1
const BAND_MASK := (1 << BAND_BITS) - 1
const MODE_MASK := (1 << MODE_BITS) - 1
const PAYLOAD_MASK := (1 << PAYLOAD_BITS) - 1
const CHECK_MASK := (1 << CHECK_BITS) - 1

## Mint a fresh code for a brand-new challenge run. The band anchors the
## curve at the creator's level - both players climb the same hill.
static func create(rounds: int = 10, band: int = 2) -> String:
		return encode(fresh_seed(), rounds, band, MODE_CHALLENGE_RUN)

## Fresh entropy, the same stir RunDeck uses: wall clock, monotonic ticks and
## the engine RNG, masked to the seed space the codec packs.
static func fresh_seed() -> int:
		var h := int(Time.get_unix_time_from_system() * 1000.0) \
						^ (Time.get_ticks_usec() << 13) \
						^ randi()
		return int(h & SEED_MASK)

## Pack a run recipe into display form ("XXX-XXX-XXX"). Inputs are clamped,
## never truncated silently out of validity.
static func encode(seed_val: int, rounds: int, band: int, mode: int = MODE_CHALLENGE_RUN) -> String:
		var safe_rounds := clampi(rounds, GameConfig.MIN_ROUNDS, GameConfig.MAX_ROUNDS)
		var safe_band := clampi(band, GameConfig.DIFFICULTY_MIN, GameConfig.DIFFICULTY_MAX)
		var payload := (int(seed_val) & SEED_MASK) \
						| ((safe_rounds & ROUNDS_MASK) << SEED_BITS) \
						| (((safe_band - 1) & BAND_MASK) << (SEED_BITS + ROUNDS_BITS)) \
						| ((mode & MODE_MASK) << (SEED_BITS + ROUNDS_BITS + BAND_BITS))
		var full := payload | (_checksum6(payload) << PAYLOAD_BITS)
		return display_form(_encode36(full))

## Parse any human input into a run recipe. Returns an empty Dictionary when
## the text is not a valid code (wrong shape, bad character, failed checksum
## or out-of-range fields) - callers treat {} as "retype it".
static func parse(text: String) -> Dictionary:
		var clean := normalize(text)
		if clean.length() != CODE_CHARS:
				return {}
		var value := _decode36(clean)
		if value < 0:
				return {}
		var payload := value & PAYLOAD_MASK
		var checksum := (value >> PAYLOAD_BITS) & CHECK_MASK
		if checksum != _checksum6(payload):
				return {}
		var seed_val := payload & SEED_MASK
		var rounds := (payload >> SEED_BITS) & ROUNDS_MASK
		var band := ((payload >> (SEED_BITS + ROUNDS_BITS)) & BAND_MASK) + 1
		var mode := (payload >> (SEED_BITS + ROUNDS_BITS + BAND_BITS)) & MODE_MASK
		if mode != MODE_CHALLENGE_RUN:
				return {}
		if rounds < GameConfig.MIN_ROUNDS or rounds > GameConfig.MAX_ROUNDS:
				return {}
		if band < GameConfig.DIFFICULTY_MIN or band > GameConfig.DIFFICULTY_MAX:
				return {}
		return {"seed": seed_val, "rounds": rounds, "band": band, "mode": mode,
						"display": display_form(clean)}

## Uppercase, strip everything that is not code material, and forgive the
## near-miss glyphs (O -> 0, I/L -> 1). Length is NOT checked here - parse()
## owns that. Encoded codes never contain O, I or L, so normalizing an
## already-encoded code is the identity map and display round-trips exactly.
static func normalize(text: String) -> String:
		var out := ""
		for ch in text.to_upper():
				if ch == "O":
						out += "0"
				elif ch == "I" or ch == "L":
						out += "1"
				elif ALPHABET.contains(ch):
						out += ch
		return out

## "XXX-XXX-XXX" display form from any accepted code spelling.
static func display_form(code: String) -> String:
		var clean := normalize(code)
		var out := ""
		for i in clean.length():
				if i > 0 and i % GROUP == 0:
						out += "-"
				out += clean[i]
		return out

# --- internals -----------------------------------------------------------------------

## 6-bit FNV-1a fold over the five payload bytes. Not cryptographic - it just
## has to make a single mistyped character fail with 63/64 probability, and a
## swapped pair with near-certainty.
static func _checksum6(payload: int) -> int:
		var h := 2166136261
		for i in 5:
				h ^= (payload >> (i * 8)) & 0xFF
				h = (h * 16777619) & 0xFFFFFFFF
		h ^= h >> 11
		h ^= h >> 22
		return h & CHECK_MASK

## 45 bits -> 9 alphabet characters (base 33), big-endian. 33^9 =
## 46,411,456,251,875 > 2^45, so every legal value round-trips.
static func _encode36(value: int) -> String:
		var out := ""
		var v := maxi(value, 0)
		for i in CODE_CHARS:
				out = ALPHABET[v % ALPHABET_SIZE] + out
				v = floori(float(v) / float(ALPHABET_SIZE))
		return out

## 9 alphabet characters -> value, or -1 on any character outside the
## alphabet or any value above the 45-bit space (a random-character soup
## decodes out of range and is rejected before the checksum even runs).
static func _decode36(code: String) -> int:
		var value := 0
		var limit := (CHECK_MASK << PAYLOAD_BITS) | PAYLOAD_MASK
		for ch in code:
				var idx := ALPHABET.find(ch)
				if idx < 0:
						return -1
				value = value * ALPHABET_SIZE + idx
				if value > limit:
						return -1
		return value
