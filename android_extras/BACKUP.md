# Android Auto Backup - what ships and what it protects

## The one-line status

Auto Backup is **already enabled**: `export_presets.cfg` carries
`user_data_backup/allow=true`, which Godot translates to
`android:allowBackup="true"` in the merged manifest of every Gradle build.

## What the player gets

With Auto Backup on, Android (6.0+) periodically copies the app's data dir to
the player's Google Drive (up to 25 MB, private to their account), and
restores it automatically on:

- **Uninstall + reinstall** on the same device
- **New device** during setup or via backup & transfer (Android 12+ also
  mirrors backups across device-to-device migration)

## What SpotRush actually stores (all tiny, all covered)

`user://` on Android maps to the app's files directory, so everything the
game persists rides along:

| File | Contents |
|------|----------|
| `user://spotrush_settings.cfg` | sfx/haptics/particles/motion toggles, volume sliders, color-vision mode, daily-reminder opt-in |
| `user://spotrush_records.cfg` | best score / best round / best streak, skill rating, Daily Spot streak + results, rival challenge code |

Both files together are a few kilobytes - three orders of magnitude under the
25 MB cap. The generated music and SFX live only in memory, so nothing bulky
ever enters the backup.

## Android 12+ behaviour (no action needed)

When `dataExtractionRules` is absent from the manifest, Android 12+ keeps the
classic default: **cloud backup on, device-to-device transfer on**. That is
exactly what a streak-based game wants, so no custom rules XML ships.

If you ever want to exclude something (e.g. a future cache file):

1. Install the Android build template (editor: Project -> Install Android
   Build Template - see RELEASE_CHECKLIST step 3).
2. Add `android:fullBackupContent="@xml/backup_rules"` (API <= 30) and
   `android:dataExtractionRules="@xml/data_extraction_rules"` (API 31+) to
   the `<application>` tag in `android/build/AndroidManifest.xml`.
3. Create `android/build/res/xml/` with the two rules files listing `<include>`
   / `<exclude>` domain paths (`file` domain = `user://`).

## How to verify on a device

1. `adb shell bmgr list transports` -> confirm `android/com.google.android.gms` GMS transport exists.
2. Force a backup: `adb shell bmgr backupnow com.spotrush.game`.
3. Reinstall the app, then restore: `adb shell bmgr restore com.spotrush.game`.
4. Launch: settings toggles, records and the daily streak should all survive.
