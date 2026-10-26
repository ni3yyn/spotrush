extends Node

const SCENE_MAIN_MENU: String = "res://scenes/main/MainMenu.tscn"
const SCENE_GAME: String = "res://scenes/game/GameScreen.tscn"
const SCENE_RESULTS: String = "res://scenes/game/MatchResults.tscn"
const SCENE_LOCAL_LOBBY: String = "res://scenes/multiplayer/LocalLobby.tscn"

var is_transitioning: bool = false
var _curtain_layer: CanvasLayer = null
var _curtain_rect: ColorRect = null

func _ready() -> void:
	# Create lightweight persistent overlay for smooth transitions
	_curtain_layer = CanvasLayer.new()
	_curtain_layer.layer = 120 # Above all scene UI
	
	_curtain_rect = ColorRect.new()
	_curtain_rect.color = Color(0.05, 0.08, 0.07, 1.0)
	_curtain_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain_rect.modulate.a = 0.0
	
	_curtain_layer.add_child(_curtain_rect)
	add_child(_curtain_layer)

func goto_scene(path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# Block input immediately
	if _curtain_rect != null:
		_curtain_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw = create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_curtain_rect, "modulate:a", 1.0, 0.08)
		tw.tween_callback(func(): call_deferred("_deferred_change_scene", path))
	else:
		call_deferred("_deferred_change_scene", path)

func _deferred_change_scene(path: String) -> void:
	var err = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load scene %s: %d" % [path, err])
		is_transitioning = false
		if _curtain_rect != null:
			_curtain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_curtain_rect.modulate.a = 0.0
		return
		
	# Reveal new scene promptly
	if _curtain_rect != null:
		var tw = create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.04)
		tw.tween_property(_curtain_rect, "modulate:a", 0.0, 0.1)
		tw.tween_callback(func():
			_curtain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			is_transitioning = false
		)
	else:
		is_transitioning = false

func goto_main_menu() -> void:
	goto_scene(SCENE_MAIN_MENU)

func goto_game() -> void:
	goto_scene(SCENE_GAME)

func goto_results() -> void:
	goto_scene(SCENE_RESULTS)

func goto_lobby() -> void:
	goto_scene(SCENE_LOCAL_LOBBY)
