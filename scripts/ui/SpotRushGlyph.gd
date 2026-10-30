extends Control

## Neumorphic vector icons for SpotRush.
##
## Every symbol is drawn in-engine as a small sculpture instead of a flat fill:
## the same top-left light that shapes the buttons also shapes the icons, so a
## glyph reads either as a RAISED object (soft dual shadow below-right, lit lip
## above-left), an ENGRAVING (lit lip below-right, faint inner edge) or an
## inlay on a coloured surface (tinted shadow + tinted lip, the same recipe the
## OnAccent NeuText labels use). Filled shapes are stroked with a hair-thin
## antialiased outline on the face pass, so edges stay crisp at any scale.
## No external icon assets are needed and everything scales with the rect.

@export_enum("play", "people", "book", "trophy", "chevron", "gear", "dot", "check", "cross", "clock", "bolt", "crown", "star", "circle", "square", "triangle", "diamond", "flame", "target", "shapes", "split", "shield", "branch", "sound", "sparkle", "vibrate", "wave") var glyph: String = "play":
        set(value):
                glyph = value
                queue_redraw()

@export var glyph_color: Color = Color.WHITE:
        set(value):
                glyph_color = value
                queue_redraw()

## Sits the glyph inside a sunken circular socket (neumorphic icon well).
@export var socket: bool = false:
        set(value):
                socket = value
                queue_redraw()
## Colour of the socket surface; set to the button colour for sockets on accent buttons.
@export var socket_surface: Color = Color("E4E9F2"):
        set(value):
                socket_surface = value
                queue_redraw()
@export var socket_colored: bool = false

## Lighting model. AUTO picks from context (coloured socket / etched == false
## means the icon sits on a coloured surface, everything else is raised on the
## light pad). Force Raised / Engraved / OnAccent to pin a look.
@export_enum("Auto", "Raised", "Engraved", "OnAccent") var look: int = 0:
        set(value):
                look = value
                queue_redraw()
## Surface colour for the OnAccent lighting; leave transparent to derive it
## from socket_surface (or from the glyph colour when neither is set).
@export var accent_base: Color = Color(0, 0, 0, 0):
        set(value):
                accent_base = value
                queue_redraw()
## Kept so existing scenes keep loading: false marks the icon as sitting on a
## coloured surface, which AUTO resolves to OnAccent lighting.
@export var etched: bool = true

const NeuKit = preload("res://scripts/ui/NeuKit.gd")

# Resolved lighting modes.
const LOOK_RAISED := 1
const LOOK_ENGRAVED := 2
const LOOK_ON_ACCENT := 3

var _socket_style: StyleBox

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        queue_redraw()

## Sculpting depth grows with the icon so big glyphs cast properly soft shadows,
## while small UI glyphs keep a feather-light seat.
func _depth_scale(side: float) -> float:
        return clampf(side / 46.0, 0.7, 1.5)

func _resolve_look() -> int:
        if look == LOOK_RAISED or look == LOOK_ENGRAVED or look == LOOK_ON_ACCENT:
                return look
        if socket_colored or not etched:
                return LOOK_ON_ACCENT
        return LOOK_RAISED

func _accent_surface() -> Color:
        if accent_base.a > 0.01:
                return accent_base
        if socket_colored:
                return socket_surface
        return glyph_color

func _draw() -> void:
        var side := minf(size.x, size.y)
        if side < 1.0:
                return
        var c := size * 0.5
        var k := side
        if glyph == "dot":
                _draw_led(c, side)
                return
        if socket:
                _draw_socket(c, side)
                k = side * 0.82
        var s := _depth_scale(side)
        match _resolve_look():
                LOOK_ENGRAVED:
                        # Pressed into the pad: the lower edge catches the light, the upper
                        # edge keeps a faint inner shadow.
                        _paint(c + Vector2(1.3, 1.8) * s, k, Color(1.0, 1.0, 1.0, 0.95), false)
                        _paint(c + Vector2(-0.8, -1.0) * s, k, Color(0.35, 0.42, 0.58, 0.22), false)
                        _paint(c, k, glyph_color.darkened(0.10), true)
                LOOK_ON_ACCENT:
                        # Inlay on a coloured surface: shadows deepen the surface colour and
                        # the lip lightens it, matching the OnAccent NeuText labels.
                        var base := _accent_surface()
                        var deep := base.darkened(0.62)
                        var high := base.lightened(0.55)
                        _paint(c + Vector2(2.4, 3.4) * s, k, Color(deep, 0.30), false)
                        _paint(c + Vector2(1.3, 1.9) * s, k, Color(deep, 0.55), false)
                        _paint(c + Vector2(-1.0, -1.3) * s, k, Color(high, 0.55), false)
                        _paint(c, k, glyph_color, true)
                _:
                        # RAISED sculpture - the icon lifts OFF the pad, never pressed in:
                        # three stacked slate shadows (wide ambient falloff, mid falloff, tight
                        # contact) seat it with real altitude, a crisp lit lip rims the top-left
                        # toward the light, and the face carries the colour.
                        _paint(c + Vector2(3.4, 4.6) * s, k, Color(0.45, 0.52, 0.68, 0.10), false)
                        _paint(c + Vector2(2.1, 2.9) * s, k, Color(0.45, 0.52, 0.68, 0.22), false)
                        _paint(c + Vector2(1.1, 1.5) * s, k, Color(0.42, 0.49, 0.66, 0.40), false)
                        _paint(c + Vector2(-1.4, -1.7) * s, k, Color(1.0, 1.0, 1.0, 0.95), false)
                        _paint(c, k, glyph_color, true)

func _draw_socket(c: Vector2, side: float) -> void:
        if _socket_style == null:
                _socket_style = NeuKit.inset(side * 0.5, 3.0, 7.0)
        _socket_style.surface = socket_surface
        _socket_style.colored = socket_colored
        _socket_style.corner_radius = side * 0.5
        draw_style_box(_socket_style, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)))

func _draw_led(c: Vector2, side: float) -> void:
        # A status LED: sunken bezel with a glowing core.
        if socket:
                _draw_socket(c, side)
        var core := side * (0.26 if socket else 0.43)
        draw_circle(c, core * 2.1, Color(glyph_color.r, glyph_color.g, glyph_color.b, 0.10))
        draw_circle(c, core * 1.5, Color(glyph_color.r, glyph_color.g, glyph_color.b, 0.18))
        draw_circle(c, core, glyph_color)
        draw_arc(c, core, 0.0, TAU, 24, glyph_color, 1.0, true)
        draw_circle(c + Vector2(-core * 0.3, -core * 0.35), core * 0.34, Color(1.0, 1.0, 1.0, 0.7))

## Filled shapes get an antialiased closed outline on the face pass so their
## edges stay sharp; shadow and lip passes stay soft.
func _poly(pts: PackedVector2Array, col: Color, face: bool) -> void:
        draw_colored_polygon(pts, col)
        if face:
                var closed := pts.duplicate()
                closed.append(pts[0])
                draw_polyline(closed, col, maxf(1.2, minf(size.x, size.y) * 0.03), true)

## Upright half-disc with a flat bottom: rounded shoulders for figures.
func _dome(cc: Vector2, r: float, squash: float, col: Color) -> void:
        var pts := PackedVector2Array()
        var steps := 24
        for i in steps + 1:
                var a := PI - PI * float(i) / float(steps)
                pts.append(cc + Vector2(cos(a) * r, -sin(a) * r * squash))
        draw_colored_polygon(pts, col)

func _paint(c: Vector2, k: float, col: Color, face: bool) -> void:
        match glyph:
                "play":
                        var points := PackedVector2Array([
                                        c + Vector2(-k * 0.22, -k * 0.34),
                                        c + Vector2(k * 0.34, 0.0),
                                        c + Vector2(-k * 0.22, k * 0.34)
                        ])
                        _poly(points, col, face)
                "people":
                        # Two rounded figures; the front one is separated from the back one
                        # by a thin surface-coloured cutout so both read cleanly at any size.
                        var surf := socket_surface if socket else NeuKit.SURFACE
                        var halo := 1.6 if minf(size.x, size.y) > 30.0 else 1.1
                        draw_circle(c + Vector2(-k * 0.17, -k * 0.20), k * 0.13, col)
                        _dome(c + Vector2(-k * 0.17, k * 0.33), k * 0.26, 0.85, col)
                        draw_circle(c + Vector2(k * 0.18, -k * 0.12), k * 0.115 + halo, surf)
                        draw_circle(c + Vector2(k * 0.18, -k * 0.12), k * 0.115, col)
                        _dome(c + Vector2(k * 0.18, k * 0.35), k * 0.22 + halo, 0.85, surf)
                        _dome(c + Vector2(k * 0.18, k * 0.35), k * 0.22, 0.85, col)
                "book":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.39, -k * 0.31),
                                        c + Vector2(-k * 0.13, -k * 0.24),
                                        c + Vector2(-k * 0.03, -k * 0.15),
                                        c + Vector2(-k * 0.03, k * 0.34),
                                        c + Vector2(-k * 0.17, k * 0.23),
                                        c + Vector2(-k * 0.39, k * 0.29)
                        ]), col, face)
                        _poly(PackedVector2Array([
                                        c + Vector2(k * 0.39, -k * 0.31),
                                        c + Vector2(k * 0.13, -k * 0.24),
                                        c + Vector2(k * 0.03, -k * 0.15),
                                        c + Vector2(k * 0.03, k * 0.34),
                                        c + Vector2(k * 0.17, k * 0.23),
                                        c + Vector2(k * 0.39, k * 0.29)
                        ]), col, face)
                        draw_line(c + Vector2(0.0, -k * 0.12), c + Vector2(0.0, k * 0.34), Color(col.r, col.g, col.b, 0.55), maxf(1.0, k * 0.035), true)
                "trophy":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.27, -k * 0.30),
                                        c + Vector2(k * 0.27, -k * 0.30),
                                        c + Vector2(k * 0.22, -k * 0.01),
                                        c + Vector2(k * 0.11, k * 0.12),
                                        c + Vector2(-k * 0.11, k * 0.12),
                                        c + Vector2(-k * 0.22, -k * 0.01)
                        ]), col, face)
                        draw_arc(c + Vector2(-k * 0.25, -k * 0.14), k * 0.14, -PI * 0.48, PI * 0.48, 12, col, maxf(1.5, k * 0.07), true)
                        draw_arc(c + Vector2(k * 0.25, -k * 0.14), k * 0.14, PI * 0.52, PI * 1.48, 12, col, maxf(1.5, k * 0.07), true)
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.055, k * 0.10),
                                        c + Vector2(k * 0.055, k * 0.10),
                                        c + Vector2(k * 0.055, k * 0.28),
                                        c + Vector2(-k * 0.055, k * 0.28)
                        ]), col, face)
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.19, k * 0.27),
                                        c + Vector2(k * 0.19, k * 0.27),
                                        c + Vector2(k * 0.19, k * 0.36),
                                        c + Vector2(-k * 0.19, k * 0.36)
                        ]), col, face)
                "chevron":
                        var line_width := maxf(1.5, k * 0.09)
                        draw_line(c + Vector2(-k * 0.12, -k * 0.28), c + Vector2(k * 0.15, 0.0), col, line_width, true)
                        draw_line(c + Vector2(k * 0.15, 0.0), c + Vector2(-k * 0.12, k * 0.28), col, line_width, true)
                "clock":
                        draw_arc(c, k * 0.36, 0.0, TAU, 32, col, maxf(2.0, k * 0.09), true)
                        draw_line(c, c + Vector2(0.0, -k * 0.22), col, maxf(2.0, k * 0.08), true)
                        draw_line(c, c + Vector2(k * 0.17, k * 0.10), col, maxf(2.0, k * 0.08), true)
                "bolt":
                        _poly(PackedVector2Array([
                                        c + Vector2(k * 0.08, -k * 0.42), c + Vector2(-k * 0.24, k * 0.06), c + Vector2(-k * 0.03, k * 0.06),
                                        c + Vector2(-k * 0.11, k * 0.42), c + Vector2(k * 0.25, -k * 0.09), c + Vector2(k * 0.04, -k * 0.09),
                                        c + Vector2(k * 0.18, -k * 0.42)
                        ]), col, face)
                "crown":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.38, k * 0.24), c + Vector2(-k * 0.40, -k * 0.18), c + Vector2(-k * 0.19, k * 0.02),
                                        c + Vector2(0.0, -k * 0.32), c + Vector2(k * 0.19, k * 0.02), c + Vector2(k * 0.40, -k * 0.18),
                                        c + Vector2(k * 0.38, k * 0.24)
                        ]), col, face)
                "star":
                        var star := PackedVector2Array()
                        for i in 10:
                                var a := -PI * 0.5 + TAU * float(i) / 10.0
                                var rr := k * (0.44 if i % 2 == 0 else 0.20)
                                star.append(c + Vector2(cos(a), sin(a)) * rr)
                        _poly(star, col, face)
                "check":
                        draw_polyline(PackedVector2Array([c + Vector2(-k * 0.32, k * 0.02), c + Vector2(-k * 0.08, k * 0.27), c + Vector2(k * 0.36, -k * 0.24)]), col, maxf(2.0, k * 0.15), true)
                "cross":
                        var w := maxf(2.0, k * 0.15)
                        draw_line(c + Vector2(-k * 0.27, -k * 0.27), c + Vector2(k * 0.27, k * 0.27), col, w, true)
                        draw_line(c + Vector2(k * 0.27, -k * 0.27), c + Vector2(-k * 0.27, k * 0.27), col, w, true)
                "gear":
                        # Eight machine-cut teeth with softened corners and a machined hub.
                        var teeth := PackedVector2Array()
                        var n := 8
                        for i in n * 4:
                                var angle := TAU * float(i) / float(n * 4) - PI * 0.5
                                var phase := i % 4
                                var radius := k * 0.35 if (phase == 0 or phase == 3) else k * 0.47
                                teeth.append(c + Vector2(cos(angle), sin(angle)) * radius)
                        _poly(NeuKit.round_poly(teeth, k * 0.035), col, face)
                        if face:
                                var surf := socket_surface if socket else NeuKit.SURFACE
                                var hole := k * 0.155
                                draw_circle(c, hole, surf)
                                draw_arc(c, hole, 0.0, TAU, 28, col, 1.2, true)
                                draw_arc(c, k * 0.25, 0.0, TAU, 36, Color(col.r, col.g, col.b, 0.28), 1.0, true)
                "circle":
                        var cr := k * 0.30
                        draw_circle(c, cr, col)
                        if face:
                                draw_arc(c, cr, 0.0, TAU, 40, col, maxf(1.0, k * 0.03), true)
                "square":
                        var sq := k * 0.52
                        _poly(PackedVector2Array([
                                        c + Vector2(-sq, -sq) * 0.5,
                                        c + Vector2(sq, -sq) * 0.5,
                                        c + Vector2(sq, sq) * 0.5,
                                        c + Vector2(-sq, sq) * 0.5
                        ]), col, face)
                "triangle":
                        _poly(PackedVector2Array([
                                        c + Vector2(0.0, -k * 0.34), c + Vector2(k * 0.32, k * 0.26), c + Vector2(-k * 0.32, k * 0.26)
                        ]), col, face)
                "diamond":
                        _poly(PackedVector2Array([
                                        c + Vector2(0.0, -k * 0.36), c + Vector2(k * 0.28, 0.0), c + Vector2(0.0, k * 0.36), c + Vector2(-k * 0.28, 0.0)
                        ]), col, face)
                "flame":
                        _poly(PackedVector2Array([
                                        c + Vector2(0.0, -k * 0.42),
                                        c + Vector2(k * 0.14, -k * 0.16),
                                        c + Vector2(k * 0.29, k * 0.04),
                                        c + Vector2(k * 0.20, k * 0.30),
                                        c + Vector2(0.0, k * 0.36),
                                        c + Vector2(-k * 0.20, k * 0.30),
                                        c + Vector2(-k * 0.29, k * 0.04),
                                        c + Vector2(-k * 0.14, -k * 0.16)
                        ]), col, face)
                        if face:
                                # Molten core: a light teardrop lifts the flame off the pad.
                                draw_colored_polygon(PackedVector2Array([
                                                c + Vector2(0.0, -k * 0.10),
                                                c + Vector2(k * 0.09, k * 0.08),
                                                c + Vector2(0.0, k * 0.24),
                                                c + Vector2(-k * 0.09, k * 0.08)
                                ]), Color(1.0, 1.0, 1.0, 0.42))
                "target":
                        draw_arc(c, k * 0.33, 0.0, TAU, 40, col, maxf(2.2, k * 0.095), true)
                        draw_circle(c, k * 0.13, col)
                "shapes":
                        var tp := c + Vector2(-k * 0.17, -k * 0.12)
                        _poly(PackedVector2Array([
                                        tp + Vector2(0.0, -k * 0.22), tp + Vector2(k * 0.20, k * 0.16), tp + Vector2(-k * 0.20, k * 0.16)
                        ]), col, face)
                        var sq2 := k * 0.36
                        _poly(PackedVector2Array([
                                        c + Vector2(k * 0.15, k * 0.13) + Vector2(-sq2, -sq2) * 0.5,
                                        c + Vector2(k * 0.15, k * 0.13) + Vector2(sq2, -sq2) * 0.5,
                                        c + Vector2(k * 0.15, k * 0.13) + Vector2(sq2, sq2) * 0.5,
                                        c + Vector2(k * 0.15, k * 0.13) + Vector2(-sq2, sq2) * 0.5
                        ]), col, face)
                "split":
                        var lw := maxf(2.0, k * 0.085)
                        for sx in [-1.0, 1.0]:
                                draw_line(c + Vector2(sx * k * 0.08, 0.0), c + Vector2(sx * k * 0.32, 0.0), col, lw, true)
                                draw_line(c + Vector2(sx * k * 0.20, -k * 0.13), c + Vector2(sx * k * 0.32, 0.0), col, lw, true)
                                draw_line(c + Vector2(sx * k * 0.20, k * 0.13), c + Vector2(sx * k * 0.32, 0.0), col, lw, true)
                "shield":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.30, -k * 0.34), c + Vector2(k * 0.30, -k * 0.34), c + Vector2(k * 0.30, 0.02),
                                        c + Vector2(0.0, k * 0.38), c + Vector2(-k * 0.30, 0.02)
                        ]), col, face)
                "branch":
                        var bw := maxf(2.0, k * 0.085)
                        draw_line(c + Vector2(0.0, k * 0.36), c + Vector2(0.0, -k * 0.02), col, bw, true)
                        draw_line(c + Vector2(0.0, -k * 0.02), c + Vector2(-k * 0.24, -k * 0.30), col, bw, true)
                        draw_line(c + Vector2(0.0, -k * 0.02), c + Vector2(k * 0.24, -k * 0.30), col, bw, true)
                        draw_circle(c + Vector2(0.0, k * 0.36), k * 0.09, col)
                        draw_circle(c + Vector2(-k * 0.24, -k * 0.30), k * 0.09, col)
                        draw_circle(c + Vector2(k * 0.24, -k * 0.30), k * 0.09, col)
                "sound":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.34, -k * 0.14), c + Vector2(-k * 0.10, -k * 0.14), c + Vector2(k * 0.08, -k * 0.32),
                                        c + Vector2(k * 0.08, k * 0.32), c + Vector2(-k * 0.10, k * 0.14), c + Vector2(-k * 0.34, k * 0.14)
                        ]), col, face)
                        var sw := maxf(2.0, k * 0.075)
                        draw_arc(c, k * 0.30, -0.9, 0.9, 12, col, sw, true)
                        draw_arc(c, k * 0.42, -0.75, 0.75, 12, col, sw, true)
                "sparkle":
                        var sp := PackedVector2Array()
                        for i in 8:
                                var sa := -PI * 0.5 + TAU * float(i) / 8.0
                                var sr := k * (0.40 if i % 2 == 0 else 0.115)
                                sp.append(c + Vector2(cos(sa), sin(sa)) * sr)
                        _poly(sp, col, face)
                        draw_circle(c, k * 0.055, col)
                "vibrate":
                        _poly(PackedVector2Array([
                                        c + Vector2(-k * 0.14, -k * 0.30),
                                        c + Vector2(k * 0.14, -k * 0.30),
                                        c + Vector2(k * 0.14, k * 0.30),
                                        c + Vector2(-k * 0.14, k * 0.30)
                        ]), col, face)
                        var vw := maxf(2.0, k * 0.07)
                        draw_arc(c, k * 0.38, -0.62, 0.62, 10, col, vw, true)
                        draw_arc(c, k * 0.38, PI - 0.62, PI + 0.62, 10, col, vw, true)
                        draw_arc(c, k * 0.50, -0.5, 0.5, 10, col, vw, true)
                        draw_arc(c, k * 0.50, PI - 0.5, PI + 0.5, 10, col, vw, true)
                "wave":
                        var ww := maxf(2.0, k * 0.075)
                        var wpts := PackedVector2Array()
                        for i in 25:
                                var wt := float(i) / 24.0
                                var wamp := 0.22 * maxf(0.0, 1.0 - absf(wt - 0.5) * 1.6)
                                wpts.append(c + Vector2((wt - 0.5) * 0.84 * k, sin(wt * TAU * 1.5) * wamp * k))
                        draw_polyline(wpts, col, ww, true)
                _:
                        pass
