extends SceneTree

# Dev-only: force-compile EVERY script in the project so parse errors surface
# even for scripts the self-test never loads (scene-only UI, dev tools, etc).

func _init() -> void:
        # Defer to the first process frame: autoload globals (BackNav, NeuDialog,
        # ...) only resolve once the engine has added them to the tree.
        process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
        var paths: PackedStringArray = []
        _collect("res://scripts", paths)
        _collect("res://addons", paths)
        paths.sort()
        var failures := 0
        for path in paths:
                var s = load(path)
                if s == null:
                        print("COMPILE FAIL: " + path)
                        failures += 1
        print("COMPILE SWEEP: %d scripts, %d failures" % [paths.size(), failures])
        quit(1 if failures > 0 else 0)

func _collect(dir_path: String, out: PackedStringArray) -> void:
        var dir := DirAccess.open(dir_path)
        if dir == null:
                return
        dir.list_dir_begin()
        var name := dir.get_next()
        while name != "":
                var full := dir_path + "/" + name
                if dir.current_is_dir():
                        _collect(full, out)
                elif name.ends_with(".gd"):
                        out.append(full)
                name = dir.get_next()
        dir.list_dir_end()
