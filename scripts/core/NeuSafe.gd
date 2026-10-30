extends RefCounted

# Real OS safe-area insets (v20).
#
# Phones cut holes in the screen: punch-hole cameras, status bars, gesture
# pills. Godot renders edge to edge, so a HUD placed at the canvas top can
# hide behind the camera. This helper reads the platform's safe area, maps it
# into canvas pixels and inflates a screen's content container by exactly the
# blocked amount. On desktop the safe area equals the window, so every helper
# here is a no-op while testing in the editor. On mobile, a conservative top
# fallback is also used when an immersive build reports no safe rectangle.

## Left, top, right, bottom insets in canvas pixels (0 on desktop).
static func canvas_insets() -> Vector4:
        var zero := Vector4(0.0, 0.0, 0.0, 0.0)
        var win := Vector2i(DisplayServer.window_get_size())
        if win.x <= 0 or win.y <= 0:
                return zero
        var sa := DisplayServer.get_display_safe_area()
        var is_mobile := OS.has_feature("mobile")
        if sa.size.x <= 0 or sa.size.y <= 0:
                # Some mobile immersive builds return an empty safe rect even
                # though the camera/status area still occupies the top edge.
                # Keep a small top breathing zone on mobile in that case.
                if is_mobile:
                        return Vector4(0.0, 48.0, 0.0, 0.0)
                return zero
        var left := maxf(0.0, float(sa.position.x) / float(win.x))
        var top := maxf(0.0, float(sa.position.y) / float(win.y))
        var right := maxf(0.0, float(win.x - sa.end.x) / float(win.x))
        var bottom := maxf(0.0, float(win.y - sa.end.y) / float(win.y))
        if left + top + right + bottom <= 0.0001 and not is_mobile:
                return zero
        # Sanity clamp: no real device blocks more than ~15% of one edge.
        left = minf(left, 0.15)
        top = minf(top, 0.15)
        right = minf(right, 0.15)
        bottom = minf(bottom, 0.15)
        var vp := Vector2(720.0, 1280.0) # design size fallback
        var tree := Engine.get_main_loop() as SceneTree
        if tree != null and tree.root != null:
                var size := tree.root.get_visible_rect().size
                if size.x > 1.0 and size.y > 1.0:
                        vp = size
        var top_px := top * vp.y
        if is_mobile:
                top_px = maxf(top_px, 48.0)
        return Vector4(left * vp.x, top_px, right * vp.x, bottom * vp.y)

## Inflates a full-rect container by the OS-reported insets. Call it in the
## screen's _ready(), BEFORE any code captures the container's offsets as an
## animation base, so entrance animations return to the padded position.
static func fit(c: Control) -> void:
        if c == null:
                return
        var i := canvas_insets()
        if i.x <= 0.0 and i.y <= 0.0 and i.z <= 0.0 and i.w <= 0.0:
                return
        c.offset_left += i.x
        c.offset_top += i.y
        c.offset_right -= i.z
        c.offset_bottom -= i.w
