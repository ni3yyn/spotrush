# SpotRush Daily Spot reminders (Android)

The Daily Spot reminder uses Notification Scheduler v6.0 for local Android alarm scheduling. The native AAR is installed from the official release by the included checksum-verifying build workflow or local installer; the source ZIP intentionally does not include a stale v4.1 native binary. Permission requests are made through the bundled plugin's native Android
permission request API. Its native result callback emits explicit granted/denied
signals back to the `DailyReminder` autoload.

## Included wiring

- `scripts/core/DailyReminder.gd` is the autoload service.
- Settings stores the opt-in flag and a selectable local reminder hour (00:00–23:00; default 19:00).
- Android 13+ receives the runtime `POST_NOTIFICATIONS` permission prompt when
the player enables reminders or taps **SEND TEST NOTIFICATION**.
- The plugin creates the `daily_spot_reminders_v2` notification channel and
  schedules one repeating Daily Spot reminder (notification ID `1001`, every
  24 hours). Returning to SpotRush cancels the repeat; leaving again recalculates it.
- The test button is available in release and debug builds. It sends a separate
  notification (ID `1002`) after five seconds, without enabling the daily
  reminder or replacing/cancelling its pending notification.
- Daily reminders repeat every 24 hours while the app remains in the
  background. Returning to SpotRush cancels the repeat; the next background
  transition schedules it again only if today's Daily Spot is unfinished. A
  player with no existing streak can still receive a reminder and start one.
- Returning to the app cancels the pending daily reminder; backgrounding the
  app re-evaluates eligibility and schedules the next reminder.

## Android export requirements

- `project.godot` keeps `NotificationSchedulerPlugin` enabled as an editor
  export plugin.
- The Android export preset must keep `permissions/post_notifications=true`.
- The plugin export hook copies `assets/NotificationSchedulerPlugin/android/drawable-*/ic_default_notification.png` into the generated Gradle build's `res` directory. The included workflow stages these resources automatically; local builds use the installer script.
- Export with Gradle build enabled. The Android AAR is Notification Scheduler v6.0, built for Godot 4.7 and Android API 24+. The Android export preset sets minSdk 24 to match it. The included Android build workflow downloads the official v6.0 package and verifies its SHA-256 before export. For a local Windows/Godot export, run `scripts/dev/install_notification_plugin_v6.cmd` (or `scripts/dev/install_notification_plugin_v6.ps1`) first. This downloads the release, verifies its SHA-256, installs the debug/release AARs and stages the notification icons.

## Device test

1. Install the exported APK on Android 13 or newer with notifications not yet
   allowed for SpotRush.
2. Open Settings and tap **SEND TEST NOTIFICATION**. Android should show its
   notification permission prompt.
3. Grant permission. The test notification should appear in about five seconds.
4. Tap the reminder toggle, choose a time, and leave the app before that time.
   If Daily Spot is unfinished, a repeating daily reminder should be scheduled.
5. Complete Daily Spot and background the app again. No daily reminder should
   be pending for that day. If the app stays in the background without being
   opened, the reminder repeats every 24 hours.
6. Deny permission during the first step and tap **OPEN ANDROID NOTIFICATION
   SETTINGS** to enable it manually. Return to SpotRush and retry the test.

Desktop/editor runs cannot post Android notifications; the test button reports
that the feature requires an installed Android build.
