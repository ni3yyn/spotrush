extends RefCounted
class_name QrCode

# v21 QR JOIN - a tiny QR generator drawn by hand in GDScript.
#
# The host's open room shows a QR square that encodes the join code
# ("SPOTRUSH:JOIN:<ip>:<port>", see LanDiscovery.encode_join_code). The friend
# scans it with their phone's own camera app - no CAMERA permission, no
# in-app scanner machinery - copies the code it shows, and taps PASTE on the
# JOIN tab; the lobby parses the code out of the clipboard and joins in one
# tap. The camera app does the reading, this file does the drawing.
#
# Scope is deliberately small and exactly what SpotRush needs: byte mode,
# error-correction level M, versions 1-4 (14..62 byte payloads - the longest
# join code is 35 bytes). At these versions the whole codeword stream is a
# single block, so no block interleaving is required. The dark-module ink and
# a 4-module quiet zone come straight from the spec, so phone cameras read it
# reliably straight off the emissive screen.
#
# This file is pure math - no scene tree, no sockets - and section 10 of
# ChallengeSystemSelfTest verifies the structure (sizes, finder/timing/
# alignment patterns, dark module, format placement) plus a full image
# round-trip decoded by an external QR reader.

const QUIET_ZONE := 4
const INK := Color("1E2432")

# 2-bit error-correction designator for level M in the format info
# (L=01, M=00, Q=11, H=10).
const EC_M_FORMAT_BITS := 0

# Per-version tables (v1..v4, EC level M, always exactly one block).
const DATA_CODEWORDS := [16, 28, 44, 64]
const EC_CODEWORDS := [10, 16, 26, 36]
const BYTE_CAPACITY := [14, 26, 42, 62]
# The single alignment pattern centre per version (v1 has none).
const ALIGNMENT_CENTERS := [[], [6, 18], [6, 22], [6, 26]]

# BCH(15,5) format-info generator and mask, straight from the spec.
const FORMAT_BCH_GENERATOR := 0x537
const FORMAT_BCH_MASK := 0x5412

# GF(256) tables (primitive polynomial 0x11D), built once per process.
static var _gf_exp := PackedInt32Array()
static var _gf_log := PackedInt32Array()

## Encodes `payload` and returns {"size": int, "grid": Array[Array[bool]]},
## or {} when the payload cannot fit versions 1-4 at level M.
static func encode_matrix(payload: String) -> Dictionary:
        var bytes := payload.to_utf8_buffer()
        var version := _best_version(bytes.size())
        if version == 0:
                return {}
        var data_cw := _build_data_codewords(version, bytes)
        var ec_cw := _rs_ec(data_cw, EC_CODEWORDS[version - 1])
        var all_cw: Array = data_cw + ec_cw
        var size := 17 + 4 * version

        var grid: Array = []
        for r in range(size):
                var row: Array = []
                row.resize(size)
                grid.append(row)

        _place_finders(grid, size)
        _place_timing(grid, size)
        _place_alignment(grid, size, version)
        _reserve_format_cells(grid, size)

        # Try all 8 masks on a trial copy each and keep the calmest pattern.
        # Any valid mask scans fine - the penalty rules just pick the most
        # camera-friendly one, exactly as the spec recommends.
        var best_grid: Array = []
        var best_mask := 0
        var best_penalty := 2147483647
        for mask in range(8):
                var trial := _deep_copy(grid)
                _map_data(trial, size, all_cw, mask)
                _set_format_info(trial, size, mask)
                var penalty := _penalty(trial, size)
                if penalty < best_penalty:
                        best_penalty = penalty
                        best_mask = mask
                        best_grid = trial
        return {"size": size, "grid": best_grid, "mask": best_mask}

## Renders the code as a square RGBA8 image (white ground, ink modules,
## quiet-zone border). Returns null when the payload does not fit.
static func generate_image(payload: String, module_size: int = 6) -> Image:
        var encoded := encode_matrix(payload)
        if encoded.is_empty():
                return null
        var grid: Array = encoded["grid"]
        var size: int = encoded["size"]
        var dim := (size + QUIET_ZONE * 2) * module_size
        var img := Image.create_empty(dim, dim, false, Image.FORMAT_RGBA8)
        img.fill(Color.WHITE)
        for r in range(size):
                for c in range(size):
                        if bool(grid[r][c]):
                                img.fill_rect(Rect2i((QUIET_ZONE + c) * module_size,
                                                (QUIET_ZONE + r) * module_size,
                                                module_size, module_size), INK)
        return img

## Convenience for UI callers: a ready-to-display texture, or null.
static func generate_texture(payload: String, module_size: int = 6) -> ImageTexture:
        var img := generate_image(payload, module_size)
        if img == null:
                return null
        return ImageTexture.create_from_image(img)

# --- version / capacity -----------------------------------------------------------------

static func _best_version(byte_count: int) -> int:
        for v in range(1, 5):
                if byte_count <= int(BYTE_CAPACITY[v - 1]):
                        return v
        return 0

# --- GF(256) + Reed-Solomon ---------------------------------------------------------------

static func _ensure_tables() -> void:
        if _gf_exp.size() == 512:
                return
        _gf_exp.resize(512)
        _gf_log.resize(256)
        var x := 1
        for i in range(255):
                _gf_exp[i] = x
                _gf_log[x] = i
                x <<= 1
                if x & 0x100:
                        x ^= 0x11D
        for i in range(255, 512):
                _gf_exp[i] = _gf_exp[i - 255]

static func _gf_mul(a: int, b: int) -> int:
        if a == 0 or b == 0:
                return 0
        return int(_gf_exp[int(_gf_log[a]) + int(_gf_log[b])])

## Generator polynomial for `ec_count` error-correction codewords
## (product of (x - alpha^i) for i in 0..ec_count-1; index 0 = highest degree).
static func _rs_generator(ec_count: int) -> Array:
        _ensure_tables()
        var g: Array = [1]
        for i in range(ec_count):
                var q: Array = [1, int(_gf_exp[i])]
                var r: Array = []
                r.resize(g.size() + 1)
                for k in range(r.size()):
                        r[k] = 0
                for j in range(2):
                        for t in range(g.size()):
                                r[t + j] ^= _gf_mul(int(g[t]), int(q[j]))
                g = r
        return g

## Error-correction codewords for one data block.
static func _rs_ec(data: Array, ec_count: int) -> Array:
        var gen := _rs_generator(ec_count)
        var res: Array = []
        res.resize(data.size() + ec_count)
        for k in range(data.size()):
                res[k] = int(data[k])
        for k in range(ec_count):
                res[data.size() + k] = 0
        for i in range(data.size()):
                var coef := int(res[i])
                if coef != 0:
                        for j in range(1, gen.size()):
                                res[i + j] ^= _gf_mul(int(gen[j]), coef)
        var out: Array = []
        out.resize(ec_count)
        for k in range(ec_count):
                out[k] = res[data.size() + k]
        return out

# --- data encoding ------------------------------------------------------------------------

static func _append_bits(bits: Array, value: int, count: int) -> void:
        for i in range(count - 1, -1, -1):
                bits.append(1 if ((value >> i) & 1) == 1 else 0)

## Byte mode bit stream -> data codewords (mode 0100, 8-bit count, data,
## terminator, byte alignment, 0xEC/0x11 pad).
static func _build_data_codewords(version: int, payload_bytes: PackedByteArray) -> Array:
        var bits: Array = []
        _append_bits(bits, 0b0100, 4)
        _append_bits(bits, payload_bytes.size(), 8)
        for b in payload_bytes:
                _append_bits(bits, int(b), 8)
        var capacity_bits := int(DATA_CODEWORDS[version - 1]) * 8
        var terminator := mini(4, capacity_bits - bits.size())
        _append_bits(bits, 0, terminator)
        while bits.size() % 8 != 0:
                bits.append(0)
        var pads := [0xEC, 0x11]
        var pad_index := 0
        while bits.size() < capacity_bits:
                _append_bits(bits, pads[pad_index % 2], 8)
                pad_index += 1
        var codewords: Array = []
        for i in range(bits.size() / 8):
                var v := 0
                for b in range(8):
                        v = (v << 1) | int(bits[i * 8 + b])
                codewords.append(v)
        return codewords

# --- function patterns ---------------------------------------------------------------------

## Finder patterns plus their 1-module separators, at three corners.
static func _place_finders(grid: Array, size: int) -> void:
        var corners := [[0, 0], [0, size - 7], [size - 7, 0]]  # (row, col)
        for corner in corners:
                var fr := int(corner[0])
                var fc := int(corner[1])
                for r in range(-1, 8):
                        for c in range(-1, 8):
                                var rr := fr + r
                                var cc := fc + c
                                if rr < 0 or rr >= size or cc < 0 or cc >= size:
                                        continue
                                var dark := (r >= 0 and r <= 6 and (c == 0 or c == 6)) \
                                                or (c >= 0 and c <= 6 and (r == 0 or r == 6)) \
                                                or (r >= 2 and r <= 4 and c >= 2 and c <= 4)
                                grid[rr][cc] = dark

## The alternating timing tracks along row 6 and column 6.
static func _place_timing(grid: Array, size: int) -> void:
        for i in range(8, size - 8):
                if grid[6][i] == null:
                        grid[6][i] = i % 2 == 0
                if grid[i][6] == null:
                        grid[i][6] = i % 2 == 0

## The alignment pattern (v2+), skipping cells owned by the finders.
static func _place_alignment(grid: Array, size: int, version: int) -> void:
        var centers: Array = ALIGNMENT_CENTERS[version - 1]
        for cr in centers:
                for cc in centers:
                        if grid[int(cr)][int(cc)] != null:
                                continue
                        for r in range(-2, 3):
                                for c in range(-2, 3):
                                        var dark := absi(r) == 2 or absi(c) == 2 or (r == 0 and c == 0)
                                        grid[int(cr) + r][int(cc) + c] = dark

## Placeholder-fills the format-info cells (real values land after the mask
## is chosen) and plants the mandatory dark module at (size-8, 8).
static func _reserve_format_cells(grid: Array, size: int) -> void:
        for i in range(9):
                if grid[8][i] == null:
                        grid[8][i] = false
                if grid[i][8] == null:
                        grid[i][8] = false
        for i in range(size - 8, size):
                grid[i][8] = false
                grid[8][i] = false
        grid[size - 8][8] = true

# --- masking + placement --------------------------------------------------------------------

static func _mask_bit(mask: int, i: int, j: int) -> bool:
        match mask:
                0:
                        return (i + j) % 2 == 0
                1:
                        return i % 2 == 0
                2:
                        return j % 3 == 0
                3:
                        return (i + j) % 3 == 0
                4:
                        @warning_ignore("integer_division")
                        return (i / 2 + j / 3) % 2 == 0
                5:
                        return (i * j) % 2 + (i * j) % 3 == 0
                6:
                        return ((i * j) % 2 + (i * j) % 3) % 2 == 0
                7:
                        return ((i + j) % 2 + (i * j) % 3) % 2 == 0
        return false

## The spec's zigzag walk: two columns at a time from the bottom-right,
## snaking upward and downward, skipping reserved (non-null) cells. Data runs
## out before the grid does - the leftover cells are the version's remainder
## bits and take the mask over "light".
static func _map_data(grid: Array, size: int, codewords: Array, mask: int) -> void:
        var row := size - 1
        var inc := -1
        var bit_index := 7
        var byte_index := 0
        var col := size - 1
        while col > 0:
                if col == 6:
                        col -= 1
                var done := false
                while not done:
                        for c in range(2):
                                var cc := col - c
                                if grid[row][cc] == null:
                                        var dark := false
                                        if byte_index < codewords.size():
                                                dark = ((int(codewords[byte_index]) >> bit_index) & 1) == 1
                                        if _mask_bit(mask, row, cc):
                                                dark = not dark
                                        grid[row][cc] = dark
                                        bit_index -= 1
                                        if bit_index == -1:
                                                byte_index += 1
                                                bit_index = 7
                        row += inc
                        if row < 0 or row >= size:
                                row -= inc
                                inc = -inc
                                done = true
                col -= 2

## BCH(15,5) encode of the 5 format data bits, XORed with the spec mask.
static func _bch_format(data: int) -> int:
        var d := data << 10
        while _msb(d) - _msb(FORMAT_BCH_GENERATOR) >= 0:
                d ^= FORMAT_BCH_GENERATOR << (_msb(d) - _msb(FORMAT_BCH_GENERATOR))
        return ((data << 10) | d) ^ FORMAT_BCH_MASK

static func _msb(v: int) -> int:
        var bit := -1
        var x := v
        while x != 0:
                x >>= 1
                bit += 1
        return bit

## Writes both format-info copies (they encode EC level + mask id).
static func _set_format_info(grid: Array, size: int, mask: int) -> void:
        var bits := _bch_format((EC_M_FORMAT_BITS << 3) | mask)
        for i in range(15):
                var mod := ((bits >> i) & 1) == 1
                # Vertical copy: top-left edge + bottom-left column.
                if i < 6:
                        grid[i][8] = mod
                elif i < 8:
                        grid[i + 1][8] = mod
                else:
                        grid[size - 15 + i][8] = mod
                # Horizontal copy: top-left edge + top-right row.
                if i < 8:
                        grid[8][size - 1 - i] = mod
                elif i == 8:
                        grid[8][7] = mod
                else:
                        grid[8][14 - i] = mod

# --- mask penalty (the spec's four rules) ----------------------------------------------------

static func _penalty(grid: Array, size: int) -> int:
        var score := 0
        # N1: runs of five or more same-coloured modules in a row or column.
        for r in range(size):
                score += _run_score(grid[r])
        for c in range(size):
                var column: Array = []
                for r in range(size):
                        column.append(grid[r][c])
                score += _run_score(column)
        # N2: every 2x2 block of one colour costs 3.
        for r in range(size - 1):
                for c in range(size - 1):
                        var v = grid[r][c]
                        if grid[r][c + 1] == v and grid[r + 1][c] == v and grid[r + 1][c + 1] == v:
                                score += 3
        # N3: the 1:1:3:1:1 finder look-alike with 4 light modules on a side.
        for r in range(size):
                score += _finder_like_score(grid[r])
        for c in range(size):
                var column: Array = []
                for r in range(size):
                        column.append(grid[r][c])
                score += _finder_like_score(column)
        # N4: dark/light balance.
        var dark := 0
        for r in range(size):
                for c in range(size):
                        if bool(grid[r][c]):
                                dark += 1
        var total := size * size
        var percent := dark * 100 / total  # integer math: floors, like the spec
        @warning_ignore("integer_division")
        score += 10 * absi(percent - 50) / 5
        return score

static func _run_score(line: Array) -> int:
        var score := 0
        var run := 1
        for i in range(1, line.size()):
                if line[i] == line[i - 1]:
                        run += 1
                else:
                        if run >= 5:
                                score += 3 + run - 5
                        run = 1
        if run >= 5:
                score += 3 + run - 5
        return score

static func _finder_like_score(line: Array) -> int:
        var score := 0
        var text := ""
        for v in line:
                text += "1" if bool(v) else "0"
        for i in range(line.size() - 10):
                var window := text.substr(i, 11)
                if window == "00001011101" or window == "10111010000":
                        score += 40
        return score

# --- misc ------------------------------------------------------------------------------------

static func _deep_copy(grid: Array) -> Array:
        var out: Array = []
        for row in grid:
                out.append(row.duplicate())
        return out
