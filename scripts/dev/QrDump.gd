extends SceneTree

# Debug: dump the chosen mask and the raw matrix as 0/1 rows for diffing
# against the python `qrcode` reference implementation.

const QrCodeScript = preload("res://scripts/ui/QrCode.gd")

func _init() -> void:
        var payload := "SPOTRUSH:JOIN:192.168.1.24:7000"
        var encoded := QrCodeScript.encode_matrix(payload)
        print("MASK=%d" % int(encoded["mask"]))
        print("SIZE=%d" % int(encoded["size"]))
        var grid: Array = encoded["grid"]
        var size := int(encoded["size"])
        var lines: Array = []
        for r in range(size):
                var row_text := ""
                for c in range(size):
                        row_text += "1" if bool(grid[r][c]) else "0"
                lines.append(row_text)
        print("MATRIX")
        for line in lines:
                print(line)
        quit(0)
