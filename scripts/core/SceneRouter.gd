extends Node

const Feel = preload("res://scripts/core/Feel.gd")
const NeuKit = preload("res://scripts/ui/NeuKit.gd")
const NeuWipe = preload("res://scripts/ui/NeuWipe.gd")
const SpotRushTypography = preload("res://scripts/ui/SpotRushTypography.gd")

const SCENE_MAIN_MENU: String = "res://scenes/main/MainMenu.tscn"
const SCENE_GAME: String = "res://scenes/game/GameScreen.tscn"
const SCENE_RESULTS: String = "res://scenes/game/MatchResults.tscn"
const SCENE_LOCAL_LOBBY: String = "res://scenes/multiplayer/LocalLobby.tscn"
const SCENE_SETTINGS: String = "res://scenes/settings/SettingsScreen.tscn"
const APP_THEME: String = "res://assets/ui/SpotRushTypography.tres"

# Per-destination accents kept for future use; the wipe currently stays neutral.
const WIPE_ACCENTS := {
		SCENE_MAIN_MENU: NeuKit.COBALT,
		SCENE_GAME: NeuKit.MINT,
		SCENE_RESULTS: NeuKit.CANARY,
		SCENE_LOCAL_LOBBY: NeuKit.LAVENDER,
		SCENE_SETTINGS: NeuKit.SLATE,
}

signal transition_started
signal transition_finished

var is_transitioning: bool = false

var _layer: CanvasLayer
var _wipe: NeuWipe
var _pending_path: String = ""

func _ready() -> void:
		# Catch every Control as it enters the tree. This keeps static scenes and
		# controls created later (challenge answers, lobby rows, dialogs) on the
		# same central type scale without scattering font numbers through scripts.
		get_tree().node_added.connect(_on_tree_node_added)
		# Apply the project theme after Godot's asset-import pass. Configuring it
		# through gui/theme/custom makes a fresh project load its unimported font.
		var theme := load(APP_THEME) as Theme
		if theme != null:
				get_tree().root.theme = theme
		else:
				push_error("Failed to load application theme: " + APP_THEME)
		_layer = CanvasLayer.new()
		_layer.layer = 120 # Above all scene UI.
		_wipe = NeuWipe.new()
		_wipe.name = "SpotWipe"
		_layer.add_child(_wipe)
		add_child(_layer)

func _on_tree_node_added(node: Node) -> void:
		if node is Control:
				# Deferred so each node's _ready() and script-defined font choices
				# have completed before we translate them into semantic type roles.
				call_deferred("_apply_typography_to_node", node)

func _apply_typography_to_node(node: Node) -> void:
		if is_instance_valid(node) and node is Control:
				SpotRushTypography.apply_control(node as Control)

func goto_scene(path: String) -> void:
		if is_transitioning:
				return
		is_transitioning = true
		_pending_path = path
		# Scenes use this to clear transient popups before the curtain starts moving.
		# Nothing should appear to be sliced in half by the closing or opening rim.
		transition_started.emit()
		Feel.sfx("whoosh")
		_wipe.covered.connect(_on_covered, CONNECT_ONE_SHOT)
		_wipe.revealed.connect(_on_revealed, CONNECT_ONE_SHOT)
		_wipe.cover(_cover_time(), WIPE_ACCENTS.get(path, NeuKit.COBALT))

## Boot handoff: the loading screen is styled to BE the closed curtain (same
## surface, same centre mark), so no cover animation is needed. Seal instantly,
## swap scenes, then play the regular open - the loading illustration appears to
## "open up" onto the main menu. Only BootScreen should call this.
func boot_to(path: String, mark_phase: float = 0.0) -> void:
		if is_transitioning:
				return
		is_transitioning = true
		_pending_path = path
		transition_started.emit()
		# Same ONE-SHOT reveal bookkeeping as goto_scene: without it, is_transitioning
		# would stay true and wait_until_idle() would block the new scene forever.
		_wipe.revealed.connect(_on_revealed, CONNECT_ONE_SHOT)
		_wipe.snap_closed(mark_phase)
		call_deferred("_swap_scene")

func _on_covered() -> void:
		# Deferred, as before: change_scene_to_file must not run inside the wipe callback.
		call_deferred("_swap_scene")

func _swap_scene() -> void:
		var perf_started_usec: int = Time.get_ticks_usec() if OS.is_debug_build() else 0
		var err := get_tree().change_scene_to_file(_pending_path)
		if OS.is_debug_build():
			var elapsed_usec := Time.get_ticks_usec() - perf_started_usec
			if elapsed_usec >= 8000:
				print("[PERF] Scene load %s: %.2f ms" % [_pending_path, float(elapsed_usec) / 1000.0])
		if err != OK:
				push_error("Failed to load scene %s: %d" % [_pending_path, err])
				_wipe.reveal(_reveal_time() * 0.5)
				return
		_wipe.reveal(_reveal_time())

func _on_revealed() -> void:
		is_transitioning = false
		transition_finished.emit()

## Await a completely open curtain before presenting first-screen overlays.
## Returns immediately when no scene transition is active.
func wait_until_idle() -> void:
		if is_transitioning:
				await transition_finished

func _cover_time() -> float:
		return 0.12 if Feel.reduced() else 0.32

func _reveal_time() -> float:
		return 0.16 if Feel.reduced() else 0.46

func goto_main_menu() -> void:
		goto_scene(SCENE_MAIN_MENU)

func goto_game() -> void:
		goto_scene(SCENE_GAME)

func goto_results() -> void:
		goto_scene(SCENE_RESULTS)

func goto_lobby() -> void:
		goto_scene(SCENE_LOCAL_LOBBY)

func goto_settings() -> void:
		goto_scene(SCENE_SETTINGS)
