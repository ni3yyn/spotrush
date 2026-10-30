# Daily Streak Reminders - Android Wiring (one-time, ~2 minutes)

The game side is complete and shipping: `scripts/core/DailyReminder.gd`
(autoload), the opt-in "Daily Streak Reminder" toggle on the settings sheet,
and the `POST_NOTIFICATIONS` manifest permission (export preset).

Godot 4 has no built-in local notifications, so posting is done by the
**NotificationScheduler** Android plugin - which now SHIPS IN THIS PROJECT:

- `addons/NotificationSchedulerPlugin/` - prebuilt AAR (v4.1, release +
  debug), GDScript wrapper and model classes. The plugin is already enabled
  in project.godot (`[editor_plugins]`), so the export step bundles the AAR,
  its manifest entries (receivers + the tap-open activity) and its
  appcompat dependency automatically. Source:
  github.com/cengiz-pz/godot-android-notification-scheduler-plugin (MIT).
- `android_extras/res/drawable-*/ic_notification.png` - the ready-made
  monochrome status-bar icon (the streak flame) at all densities. Android
  crashes a notification whose small icon is missing, so do not skip the
  copy below. Icon: Google Material Icons "whatshot" (Apache License 2.0).

Until the plugin is active on a device, desktop/editor/device logs say
`[DailyReminder] (no native bridge) would notify in ...` instead - every
other behaviour is identical.

## Step 1 - Copy the notification icon into the gradle build template (once)

After installing the Android build template in the Godot editor
(Project -> Install Android Build Template - see store/RELEASE_CHECKLIST.md),
copy the bundled icon set in:

    # Linux / macOS
    cp -r android_extras/res/. android/build/res/

    # Windows (cmd)
    xcopy /E /I android_extras\res android\build\res

Result: `android/build/res/drawable-<density>/ic_notification.png`, exactly
the name DailyReminder.gd posts with (`REMINDER_ICON = "ic_notification"`).

## Step 2 - Export

Export with Gradle build (already the preset default). Nothing else to
configure: the runtime permission is requested from the settings toggle the
moment the player turns the reminder on (the polite moment), and Android 13+
shows the system dialog. If the player declines, the toggle stays on but no
notification can appear - the plugin's permission query makes re-prompts
possible from the app's system settings.

## Behaviour contract (what ships in code)

- OFF by default; nothing is scheduled unless the player opts in.
- One notification pending at most, fixed id 1001 - re-scheduling overwrites.
- Fires at 19:00 local time (today if the hour has not passed, otherwise
  tomorrow), only when the daily is unplayed AND the streak is alive.
- Content: "A quick run keeps your N-day streak alive."
- Opening the app cancels the pending nudge; leaving re-evaluates.
- All decision logic is pure/static and covered by the self-test (section 11).

## On-device verification (2 minutes)

1. Play the Daily Spot at least once so a streak exists; leave the app with
   the daily unplayed the NEXT day, or just lower the device clock past
   19:00 with the app backgrounded after toggling the reminder on.
2. Expect one notification: "SpotRush daily is waiting / A quick run keeps
   your N-day streak alive."
3. Open the app - the notification clears; toggle off - nothing schedules.
