extends Node

# The hardware-reality handler (v20).
#
# Android can yank the app into the background at any moment: Home, a phone
# call, an app switch, the notification shade. Before v20 the match kept
# ticking and audio kept playing over whatever the player switched to. Now:
#
#   APPLICATION_PAUSED  -> solo clock freezes (via AppLifecycle.is_background,
#                          checked by GameManager), Master bus mutes
#   APPLICATION_RESUMED -> everything returns exactly as it was left
#   FOCUS_OUT / IN      -> desktop parity: audio ducks when the window loses
#                          focus, so editor testing behaves like a phone
#
# Duels deliberately do NOT freeze: both phones must stay on the same beat,
# and the host is not pausing for you. The v19 disconnect sheet already
# catches the worst case (host vanished while you were away).

signal app_paused
signal app_resumed

var is_background: bool = false

var _soft_muted: bool = false

func _ready() -> void:
        # Outlives every scene change and must keep working while paused.
        process_mode = Node.PROCESS_MODE_ALWAYS
        # Party game: the screen must never sleep mid-round. DON'T TAP holds
        # and GET READY cards are long no-touch windows - one line saves the
        # duel from a blanking screen.
        DisplayServer.screen_set_keep_on(true)

func _notification(what: int) -> void:
        match what:
                NOTIFICATION_APPLICATION_PAUSED:
                        _pause_now()
                NOTIFICATION_APPLICATION_RESUMED:
                        _resume_now()
                NOTIFICATION_APPLICATION_FOCUS_OUT:
                        _soft_mute(true)
                NOTIFICATION_APPLICATION_FOCUS_IN:
                        _soft_mute(false)

## The real pause path (also used directly by the self-test).
func _pause_now() -> void:
        is_background = true
        _set_master_mute(true)
        app_paused.emit()

## The real resume path (also used directly by the self-test).
func _resume_now() -> void:
        is_background = false
        _set_master_mute(_soft_muted)
        app_resumed.emit()

## Desktop focus ducking: editor/alt-tab parity for the phone mute behaviour.
func _soft_mute(on: bool) -> void:
        _soft_muted = on
        _set_master_mute(on or is_background)

func _set_master_mute(muted: bool) -> void:
        AudioServer.set_bus_mute(0, muted)
