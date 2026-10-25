extends Node

const SCENE_MAIN_MENU: String = "res://scenes/main/MainMenu.tscn"
const SCENE_GAME: String = "res://scenes/game/GameScreen.tscn"
const SCENE_RESULTS: String = "res://scenes/game/MatchResults.tscn"
const SCENE_LOCAL_LOBBY: String = "res://scenes/multiplayer/LocalLobby.tscn"

func goto_scene(path: String) -> void:
	call_deferred("_deferred_change_scene", path)

func _deferred_change_scene(path: String) -> void:
	var err = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load scene %s: %d" % [path, err])

func goto_main_menu() -> void:
	goto_scene(SCENE_MAIN_MENU)

func goto_game() -> void:
	goto_scene(SCENE_GAME)

func goto_results() -> void:
	goto_scene(SCENE_RESULTS)

func goto_lobby() -> void:
	goto_scene(SCENE_LOCAL_LOBBY)
