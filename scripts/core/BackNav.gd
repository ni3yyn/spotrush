extends Node

# The hardware back router (v19).
#
# project.godot sets quit_on_go_back = false, so Android's back button never
# kills the app directly - every press lands here instead, where it is offered
# to registered handlers in registration order:
#
#   NeuDialog  (a confirmation sheet is up)  -> it closes / cancels itself
#   the screen (one scene is live at a time) -> navigate "up", confirm first
#                                             when leaving costs progress
#   nobody                                 (boot splash)  -> quit the app
#
# Escape plays the same role on desktop, so the whole flow is testable in the
# editor without a phone. A screen opts in with two lines:
#   BackNav.register(self)   in _ready()
#   BackNav.unregister(self) in _exit_tree()
# ...and one method:  func handle_back() -> bool   (true = consumed).

var _handlers: Array = []

func _ready() -> void:
        # Outlives every scene change; must never be paused by gameplay.
        process_mode = Node.PROCESS_MODE_ALWAYS

## Join the back chain. Handlers are consulted in registration order, so
## always-on layers (the dialog sheet) register at boot and stay in front,
## while the active screen - registered later - answers behind them.
func register(handler: Node) -> void:
        if handler == null or _handlers.has(handler):
                return
        _handlers.append(handler)

func unregister(handler: Node) -> void:
        _handlers.erase(handler)

func _notification(what: int) -> void:
        if what == NOTIFICATION_WM_GO_BACK_REQUEST:
                handle_back()

## Escape = back on desktop, so the flow is checkable without a device.
func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and not event.echo \
                        and event.keycode == KEY_ESCAPE:
                handle_back()
                get_viewport().set_input_as_handled()

func handle_back() -> void:
        # A press landing mid-wipe is noise: the navigation it asked for is
        # already unfolding behind the curtain.
        if SceneRouter.is_transitioning:
                return
        for handler in _handlers:
                if is_instance_valid(handler) and handler.has_method("handle_back") \
                                and handler.handle_back():
                        return
        # Nothing consumed it (boot splash, or a screen that opted out):
        # Android roots expect back to leave the app.
        get_tree().quit()
