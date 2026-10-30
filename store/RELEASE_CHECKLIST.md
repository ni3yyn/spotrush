# SpotRush v21 - Release Checklist (first Play Store submission)

Project facts this checklist assumes (all already set in the repo):

| Fact | Value |
|---|---|
| Package name | `com.spotrush.game` |
| versionName / versionCode | `1.0.0` / `1` |
| Permissions | INTERNET, ACCESS_NETWORK_STATE, VIBRATE, POST_NOTIFICATIONS |
| Orientation / mode | Portrait, immersive |
| Architectures | arm64-v8a + armeabi-v7a |
| Auto Backup | allowed (see `android_extras/BACKUP.md`) |
| Kit location | `store/` (excluded from the exported game via `exclude_filter`) |
| Extras docs | `android_extras/` (notifications + backup wiring; also excluded) |

---

## 0. Pre-flight (one-time machine setup)

1. Install **Godot 4.7** and open this project once (lets it import the new
   `store/feature_graphic_1024x500.png` and re-generate `.godot/`).
2. Run the self-test and expect `ALL PASSED`:
   ```
   godot --headless -s res://scripts/challenges/ChallengeSystemSelfTest.gd
   ```
3. Install the Android build templates: **Project → Install Android build
   template** (needs JDK 17 + Android SDK configured in Editor Settings).

## 1. Make your signing key (one-time, then guard it with your life)

```
keytool -genkeypair -v -keystore spotrush-release.keystore \
        -alias spotrush -keyalg RSA -keysize 2048 -validity 10000
```

- Answer the name/org prompts with your developer identity.
- **Back the .keystore file + both passwords up somewhere safe.** Lose it and
  you can never update the app under the same listing again.
- Test builds use Godot's debug keystore automatically; you only need the
  release keystore for the store upload.

## 2. Wire signing into the export preset

Open **Project → Export → Android** and fill:

- `Keystore / Release` → path to `spotrush-release.keystore`
- `Keystore / Release User` → `spotrush`
- `Keystore / Release Password` → your password

(or leave them and export from CI with env vars — editor fields are simpler
for a first release).

## 3. Build the AAB

For the Play Console you need an **Android App Bundle**, not an APK:

1. In the Android export preset set:
   - `gradle_build/export_format = 1` (0=APK, 1=AAB)
   - `export_path = build/SpotRush.aab`
2. Export. Command-line equivalent:
   ```
   godot --headless --export-release "Android" build/SpotRush.aab
   ```
3. Sanity check the bundle: install a debug APK build (`export_format=0`) on
   your phone first — menu boots, v21 chip shows, a nearby-games duel works
   with a second device or hotspot.
4. QR duel-join check (two phones): host creates a room — the QR square
   appears under the game code; friend scans it with their camera app, copies
   the code, taps PASTE on the JOIN tab → connects without typing anything.
5. Daily reminder check (opt-in): turn on "Daily Streak Reminder" in
   settings, grant the Android 13+ permission dialog, leave the app with the
   daily unplayed → a notification should land at 19:00 local. Playing the
   daily first = no notification. (Until the plugin drop-in from
   `android_extras/NOTIFICATIONS.md` is done, the log line
   `[DailyReminder] (no native bridge)...` is the expected behaviour instead.)
6. Auto Backup check: `adb shell bmgr backupnow com.spotrush.game`, then
   reinstall and confirm settings/records/streak survive
   (`android_extras/BACKUP.md` has the full command walk-through).

## 4. Play Console: create the app

1. [play.google.com/console](https://play.google.com/console) → **Create app**
2. Name: `SpotRush: Color Reflex Duel` · Default language: English (US)
3. App or game: **Game** · Free or paid: **Free**
4. Declarations: not a government app, not financial, no ads → continue.

## 5. Store listing (paste from `store/PLAY_STORE_LISTING.md`)

- App name, short description, full description → copy-paste.
- Icon: upload `assets/ui/AppIcon.png` (512×512 ✓).
- Feature graphic: upload `store/feature_graphic_1024x500.png` (1024×500 ✓).
- Phone screenshots: capture per the shot list in the listing doc (min 2).

## 6. App content

| Section | What to do |
|---|---|
| Privacy policy | Host `store/PRIVACY_POLICY.html` (GitHub Pages: push it, enable Pages, use the URL). **Replace the [REPLACE-ME] fields first.** Paste the URL. |
| Data safety | Fill exactly per `store/DATA_SAFETY.md` → final answer "No collection, no sharing". |
| Content rating | Answer the IARC questionnaire per `store/IARC_RATING.md` → expect Everyone / PEGI 3. |
| Target audience | 13+ is the simplest truthful choice (the game is also fine for kids — it collects nothing — but 13+ avoids the whole "Designed for Families" review track). |
| News / COVID / government / financial | All "No". |
| Ads | Contains no ads. |

## 7. Release

1. **Internal testing** track first: upload the AAB, add yourself as tester,
   install from the Play Store link, play one full duel on two phones.
2. Check the boring-but-fatal things: icon renders correctly on the launcher,
   no security warning about unknown sources (signed properly), back button
   flow, pause/resume mid-duel, volume sliders persist.
3. Create a **release notes** line for the first build, e.g.:
   `First release. 6 mini-games, adaptive runs, daily spot, Wi-Fi duels, rival codes.`
4. Promote Internal → Closed (optional) → **Production** with a staged
   rollout (20% is a good first step for a solo dev).

## 8. Every future update

- Bump `version/code` (e.g. 1 → 2) and `version/name` (1.0.0 → 1.0.1) in
  `export_presets.cfg`, and `GameConfig.APP_VERSION` so the menu chip matches.
- Re-run the self-test before every export.
- If you ever touch data handling, redo Data Safety + privacy policy FIRST
  (see the honesty guards at the bottom of `store/DATA_SAFETY.md`).
- Never lose the keystore.
