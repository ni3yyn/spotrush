extends Node

func _ready() -> void:
	print("--- CAPTURING MAIN MENU TACTILE REDESIGN SCREENSHOT ---")
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("docs/screenshots"):
		dir.make_dir_recursive("docs/screenshots")
		
	var menu_scene = load("res://scenes/main/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)
	
	for f in range(10):
		await get_tree().process_frame
		
	var vp = get_viewport()
	if vp != null:
		var tex = vp.get_texture()
		if tex != null:
			var img = tex.get_image()
			if img != null:
				var path = "docs/screenshots/main_menu_tactile.png"
				var err = img.save_png(path)
				if err == OK:
					print("SUCCESS: Saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
				else:
					print("ERROR: Failed to save %s (code %d)" % [path, err])
					
	print(">> CAPTURE PROCESS FINISHED <<")
	get_tree().quit(0)
