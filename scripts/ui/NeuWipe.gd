extends Control

# The SpotRush signature scene change: a "spotlight wipe" through a neumorphic pad.
#
# The curtain is not a flat 2D colour: it is the same soft surface the whole app
# is sculpted from - base surface plus the two corner light glows drawn by
# NeuKit.draw_backdrop and BootScreen (passed to the shader as textures and UV
# rects, so the sealed curtain is pixel-identical to the boot screen's backdrop).
# The spotlight is a hole punched through a thick soft pad: a raised lip around
# the hole catches the top-left light and a soft contact shadow seats the edge
# into the material, which is what reads as depth instead of a flat cutout.
#
# A neumorphic curtain closes over the outgoing screen as a shrinking circle of
# light, the pressed spot-mark (NeuKit.draw_spot_mark, identical to the boot
# screen's) blooms on top at full cover, the scene swaps underneath, then the
# pad opens smoothly and the new screen's items rise into place (driven by each
# screen's own entrance). Reduce Motion: fast quiet wipe, static mark, no scene
# settle.
#
# The mark is drawn on a dedicated child layer and faded via that layer's
# modulate, because the sculpted NeuStyle pieces cannot be faded per-colour.

signal covered
signal revealed

const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const Feel = preload("res://scripts/core/Feel.gd")

# The curtain seals at a slightly negative radius: the smoothstep body then
# covers every pixel, so no pinhole of the outgoing scene survives the swap
# (and no flat veil is needed to fake it).
const _CLOSED_RADIUS: float = -0.06

const SHADER_CODE := """
shader_type canvas_item;

uniform vec4 wipe_color : source_color = vec4(0.894, 0.914, 0.949, 1.0);
uniform float radius : hint_range(-0.25, 2.0) = 2.0;
uniform float softness : hint_range(0.001, 0.25) = 0.05;
uniform float aspect = 1.0;

// Corner light sculpting: the same two radial glows NeuKit.draw_backdrop and
// BootScreen paint over the flat surface, sampled here so the sealed curtain's
// pad lighting matches the rest of the app exactly. Rects are in UV space.
uniform sampler2D light_glow : hint_default_white, filter_linear;
uniform sampler2D dark_glow : hint_default_white, filter_linear;
uniform vec4 light_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 dark_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 shadow_rgb = vec3(0.60, 0.66, 0.79);

void fragment() {
        vec2 p = UV - vec2(0.5);
        p.x *= aspect;
        float d = length(p);
        float body = smoothstep(radius - softness, radius + softness, d);

        // Pad material: base surface with the two corner glows composited
        // src-over, exactly like draw_texture_rect does on the canvas side.
        vec3 pad = wipe_color.rgb;
        float lit = texture(light_glow, (UV - light_rect.xy) / max(light_rect.zw, vec2(1e-5))).a;
        pad = mix(pad, vec3(1.0), lit);
        float shade = texture(dark_glow, (UV - dark_rect.xy) / max(dark_rect.zw, vec2(1e-5))).a;
        pad = mix(pad, shadow_rgb, shade);

        // Sculpted rim: the spotlight is a hole pressed through a thick pad.
        // A raised lip catches the top-left light on its outer slope and throws
        // a soft contact shadow around the hole; both hug the moving edge, so
        // the wipe reads as a physical opening rather than a flat mask.
        float e = (d - radius) / max(softness, 1e-4);
        float lip = (1.0 - smoothstep(0.0, 1.7, e)) * body;
        vec2 nd = p / max(d, 1e-4);
        float flank = dot(nd, vec2(-0.70710678, -0.70710678));
        pad = mix(pad, vec3(1.0), lip * clamp(flank, 0.0, 1.0) * 0.40);
        pad = mix(pad, shadow_rgb, lip * clamp(-flank, 0.0, 1.0) * 0.30);
        float halo = (1.0 - smoothstep(0.0, 4.0, e)) * body;
        pad *= 1.0 - halo * 0.05;

        // Fine dither keeps the wide soft falloffs from banding.
        float n = fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453);
        pad += (n - 0.5) * (2.0 / 255.0);

        COLOR = vec4(pad, body * wipe_color.a);
}
"""

var _curtain: ColorRect
var _mark_layer: MarkLayer
var _mat: ShaderMaterial
var _tween: Tween
var _mark_alpha := 0.0:
        set(value):
                _mark_alpha = value
                if _mark_layer != null and is_instance_valid(_mark_layer):
                        _mark_layer.modulate.a = value
                        # modulate is applied at render time and does not itself
                        # re-run _draw, so every alpha change must queue a redraw.
                        _mark_layer.queue_redraw()
var _mark_time := 0.0
var _mark_redraw_accumulator: float = 0.0
var _orbit := true
var _radius := 0.0

func _set_radius(r: float) -> void:
        _radius = r
        _mat.set_shader_parameter("radius", r)

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var shader := Shader.new()
        shader.code = SHADER_CODE
        _mat = ShaderMaterial.new()
        _mat.shader = shader
        _mat.set_shader_parameter("wipe_color", NeuKit.SURFACE)
        _mat.set_shader_parameter("shadow_rgb", Vector3(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b))
        # The exact glow textures the canvas-side backdrop painters use.
        _mat.set_shader_parameter("light_glow", NeuKit.glow_texture(Color(1.0, 1.0, 1.0, 0.65)))
        _mat.set_shader_parameter("dark_glow", NeuKit.glow_texture(Color(NeuKit.DARK.r, NeuKit.DARK.g, NeuKit.DARK.b, 0.24)))
        _curtain = ColorRect.new()
        _curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _curtain.material = _mat
        _curtain.color = Color.WHITE
        # Draw the curtain behind this node's own drawing so the mark layer always
        # sits ON TOP of the sealed curtain instead of being hidden underneath it.
        _curtain.show_behind_parent = true
        add_child(_curtain)
        _mark_layer = MarkLayer.new()
        _mark_layer.name = "MarkLayer"
        _mark_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _mark_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _mark_layer.modulate.a = 0.0
        add_child(_mark_layer)
        var vp := get_viewport()
        if vp != null:
                _sync_size()
                if not vp.size_changed.is_connected(_sync_size):
                        vp.size_changed.connect(_sync_size)
        set_process(false)

func _sync_size() -> void:
        # Full-rect anchors already track the viewport. Assigning size here fights
        # those anchors and triggers Control's overridden-size warning.
        _sync_aspect()
        _sync_glow_rects()

func _notification(what: int) -> void:
        if what == NOTIFICATION_RESIZED:
                _sync_aspect()
                _sync_glow_rects()

func _sync_aspect() -> void:
        if _mat != null and size.y > 0.0:
                _mat.set_shader_parameter("aspect", size.x / size.y)

## Mirror the glow placement of NeuKit.draw_backdrop / BootScreen._draw in UV
## space so the shader lights the pad from the same two corners.
func _sync_glow_rects() -> void:
        if _mat == null or size.x <= 1.0 or size.y <= 1.0:
                return
        var s := size
        var big := maxf(s.x, s.y) * 1.5
        var light_px := Rect2(Vector2(-big * 0.5, -big * 0.42), Vector2(big, big))
        var dark_px := Rect2(Vector2(s.x - big * 0.45, s.y - big * 0.45), Vector2(big, big))
        _mat.set_shader_parameter("light_rect", Rect2(light_px.position / s, light_px.size / s))
        _mat.set_shader_parameter("dark_rect", Rect2(dark_px.position / s, dark_px.size / s))

func block_input(on: bool) -> void:
        mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
        if _curtain != null:
                _curtain.mouse_filter = mouse_filter

## Close the spotlight over the outgoing screen.
func cover(duration: float, _accent: Color) -> void:
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _orbit = not Feel.reduced()
        _mark_layer.orbit = _orbit
        set_process(true)
        block_input(true)
        _mat.set_shader_parameter("wipe_color", NeuKit.SURFACE)
        _mat.set_shader_parameter("softness", 0.05)
        # Start from a fully open curtain via _set_radius (not just the shader
        # parameter) so _radius stays in sync and the tween truly animates from
        # open to closed instead of snapping shut on its first frame.
        _set_radius(_max_radius())
        _tween = create_tween()
        # Shrink the circle of light until the curtain seals shut (slightly past
        # zero, so the close completes fully with no leftover hole).
        _tween.tween_method(func(r: float): _set_radius(r), _radius, _CLOSED_RADIUS, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
        # Bloom the pressed spot-mark on top of the sealed curtain, then swap the scene.
        _tween.tween_property(self, "_mark_alpha", 1.0, 0.20 if _orbit else 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        _tween.tween_callback(func(): covered.emit())

## Seal the curtain instantly (no animation) and show the mark, as if the cover
## phase had already completed. `mark_phase` seeds the spark orbit so the boot
## screen's own orbiting beads continue on the curtain without a jump. The boot
## screen is drawn to look exactly like this sealed state, so sealing here and
## swapping scenes underneath is invisible to the player.
func snap_closed(mark_phase: float = 0.0) -> void:
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _orbit = not Feel.reduced()
        set_process(true)
        block_input(true)
        _mark_time = maxf(0.0, mark_phase)
        # Seed the bead phase before the first sealed draw so the orbit continues
        # from the boot screen without a one-frame jump.
        _mark_layer.time = _mark_time
        _mark_layer.orbit = _orbit
        _mark_alpha = 1.0
        _set_radius(_CLOSED_RADIUS)
        _mark_layer.queue_redraw()

## Open the pad on the new scene: fade the mark, hold a beat, then unfurl.
func reveal(duration: float) -> void:
        if _tween != null and _tween.is_valid():
                _tween.kill()
        _tween = create_tween()
        _tween.tween_property(self, "_mark_alpha", 0.0, minf(0.14, duration * 0.35)).set_ease(Tween.EASE_IN)
        _tween.tween_interval(0.05) # a beat on the closed mark before the world comes back
        # The curtain unseals from its slightly-negative closed radius, so the
        # circle of light grows smoothly out from the very center - no snap.
        _tween.tween_method(func(r: float): _set_radius(r), _radius, _max_radius(), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
        _tween.tween_callback(func():
                block_input(false)
                set_process(false)
                revealed.emit())

func _max_radius() -> float:
        var a := size.x / maxf(1.0, size.y)
        return 0.5 * sqrt(a * a + 1.0) + 0.12

func _process(delta: float) -> void:
        if _mark_alpha > 0.0 and _orbit:
                _mark_time += delta
                _mark_redraw_accumulator += delta
                if _mark_redraw_accumulator >= 1.0 / 30.0:
                        _mark_redraw_accumulator = fmod(_mark_redraw_accumulator, 1.0 / 30.0)
                        _mark_layer.time = _mark_time
                        _mark_layer.orbit = _orbit
                        _mark_layer.queue_redraw()


class MarkLayer extends Control:
        # Draws the shared pressed spot-mark (NeuKit.draw_spot_mark). The whole
        # layer fades through modulate.a, driven by NeuWipe's _mark_alpha setter.
        const NeuKit = preload("res://scripts/ui/NeuKit.gd")

        var time: float = 0.0
        var orbit: bool = true

        func _draw() -> void:
                if modulate.a <= 0.001 or size.x <= 0.0:
                        return
                NeuKit.draw_spot_mark(self, size * 0.5, minf(size.x, size.y) * 0.085, time, orbit)
