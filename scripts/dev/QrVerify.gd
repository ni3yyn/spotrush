extends SceneTree

# Dev-only QR verification harness (not part of the game bundle).
# Renders join-code QR squares to PNG so an external QR reader (pyzbar/cv2)
# can prove the GDScript encoder produces genuinely scannable codes.

const QrCodeScript = preload("res://scripts/ui/QrCode.gd")

func _init() -> void:
        var payloads := [
                "SPOTRUSH:JOIN:1.1.1.1:7000",           # 26 bytes -> v2
                "SPOTRUSH:JOIN:10.0.0.7:7000",          # 27 bytes -> v3
                "SPOTRUSH:JOIN:192.168.1.24:7000",      # 31 bytes -> v3
                "SPOTRUSH:JOIN:192.168.100.100:65535",  # 35 bytes -> v4 (max)
        ]
        var dir := "/home/z/my-project/work/spotrush_v21/test_out"
        DirAccess.make_dir_recursive_absolute(dir)
        var idx := 0
        for p in payloads:
                var img: Image = QrCodeScript.generate_image(p, 6)
                if img == null:
                        print("FAIL null image for: " + p)
                        quit(1)
                        return
                img.save_png(dir + "/qr_%d.png" % idx)
                print("wrote qr_%d.png for %s (%dx%d)" % [idx, p, img.get_width(), img.get_height()])
                idx += 1
        print("WROTE %d PNGs" % idx)
        quit(0)
