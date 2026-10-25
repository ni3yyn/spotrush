# SpotRush — Testing & Validation Guide

## 1. Automated Test Suite (Autoload-Aware)
SpotRush contains an automated test harness designed to run via Godot 4's headless CLI with full project autoload context (`NetworkSession`, `SceneRouter`, `GameManager`).

### Running the Full Test Suite
From the project root:
```powershell
& 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe' --headless res://tests/TestRunner.tscn
```
Or if `godot` is in your system PATH:
```bash
godot --headless res://tests/TestRunner.tscn
```

### Verified Test Suites (98 Passed, 0 Failed, 0 Errors, 0 Warnings)
1. **`TestChallengeGeneration` (44 tests)**:
   - Challenge generation across all difficulty tiers (Easy, Medium, Hard, Expert).
   - Quantity estimation option presence and visual count integrity.
   - Side comparison winner calculation.
   - Network dictionary serialization and deserialization round-trip.
2. **`TestAnswerValidation` (7 tests)**:
   - Valid correct answers in choice mode.
   - Valid incorrect answers in choice mode.
   - Late answer rejection beyond deadline.
   - Tap target positive and false-positive tracking.
   - Withhold response (Don't Tap) correct timeout vs premature tap.
3. **`TestScoring` (7 tests)**:
   - Deterministic speed bonus calculation (faster responses earn higher scores).
   - Wrong answer penalty deduction.
   - Timeout zero score.
   - Withhold challenge full point award.
   - Accuracy % and average response time calculations.
   - Winner determination and tie handling.
4. **`TestNetworkingLogic` (8 tests)**:
   - Packet structure and version checking.
   - Stale/corrupt packet rejection.
   - Round answer state validation.
   - Duplicate round submission rejection.
   - Unknown packet type rejection.
5. **`TestFullGameLoop` (10 tests)**:
   - Complete 5-round single player match loop (Countdown -> Active -> Feedback -> Match Over).
   - Authoritative match conclusion.
   - Rematch pristine state reset.
6. **`TestMultiplayerSimulation` (6 tests)**:
   - ENet server and client peer creation on localhost.
   - Asynchronous handshake polling and connection confirmation.
   - Dual-player simultaneous answer submission.
   - Host authoritative scoring computation for both peers.
7. **`TestUiSceneFlow` (6 tests)**:
   - `MainMenu.tscn` instantiation and control binding.
   - `LocalLobby.tscn` instantiation and host/join tabs.
   - `GameScreen.tscn` ChallengeView, TimerBar, and HUD bindings.
   - `MatchResults.tscn` labels and action buttons.
   - Multi-round match progression through `MatchController`.
   - Results scoring accuracy verification.
8. **`TestChallengeRendering` (10 tests)**:
   - `ChallengeView` and `ChallengeCanvas` scene node binding.
   - Estimation challenge data binding and 4-option generation.
   - Side comparison split view and LEFT/RIGHT options.
   - Color target selection and action button visibility.
   - Shape target selection and polygon geometry verification.
   - Don't Tap withhold stimulus and action button styling.
   - Combined conditional YES/NO button bindings.
   - Tap index recording on `ChallengeCanvas`.
   - Canvas input locking when match round ends.
   - Palette color mapping resolution.

---

## 2. Visual Gameplay Verification & Screenshot Capture
To prove visual correctness on the actual GPU renderer rather than relying on headless logic alone:
```powershell
& 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe' res://tests/CapturePreview.tscn
```
This launches Godot's live compatibility graphics pipeline, renders each challenge family, and saves 7 verified high-resolution PNG screenshots into `docs/screenshots/`:
- `challenge_estimation.png`: Quantity estimation with 4 option cards.
- `challenge_comparison.png`: Side-by-side comparison with LEFT/RIGHT pills, glowing divider, and action buttons.
- `challenge_color_target.png`: Color targets with distractors and progress counter.
- `challenge_shape_target.png`: Antialiased triangles, squares, and circles.
- `challenge_dont_tap.png`: Inhibitory stimuli with pulsing cue and dark red withhold button.
- `challenge_combined.png`: Multi-attribute conditional field with YES/NO buttons.
- `challenge_tapped_feedback.png`: Interactive tap highlights with mint glowing aura and checkmark icons.

---

## 3. Real Two-Process ENet Network Integration Test
To prove that networking functions over real OS network sockets and not merely within simulated in-memory objects, SpotRush includes a dual-process test harness.

### Running the Real Network Test
```powershell
powershell -ExecutionPolicy Bypass -File tests/real_network/run_real_enet_test.ps1
```

### What This Test Verifies
1. Process A launches as an independent OS process, initializing an authoritative ENet server on port `7025`.
2. Process B launches as a second independent OS process and connects over UDP socket `127.0.0.1:7025`.
3. The processes perform a live ENet handshake and assign real peer IDs.
4. The host transmits procedural challenge payloads over the network.
5. The client parses the challenge, formulates a response, and transmits an answer packet back to the host.
6. The host validates the packet authoritatively, computes points, synchronizes round scores, and dispatches match conclusion.
7. Both processes verify clean message sequences and exit with code 0.

---

## 3. Desktop Dual-Instance Manual Testing (Localhost)
To test the real UI and multiplayer experience locally on PC:

1. **Launch Instance 1 (Host)**:
   ```powershell
   & 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe'
   ```
   - In SpotRush Main Menu, click **LOCAL WI-FI MULTIPLAYER**.
   - Under the **HOST A GAME** tab, click **START HOST SERVER**.
   - The status updates to: *"Server listening on Port 7000"*.

2. **Launch Instance 2 (Client)**:
   Open a second terminal window and execute:
   ```powershell
   & 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe'
   ```
   - In SpotRush Main Menu, click **LOCAL WI-FI MULTIPLAYER**.
   - Switch to the **JOIN A GAME** tab.
   - Keep IP as `127.0.0.1` and click **CONNECT TO HOST**.

3. **Verify Connection & Play**:
   - Instance 1 (Host) displays: *"Players Connected: 2 (Ready to play!)"*.
   - Click **START MATCH** on Instance 1.
   - Both windows transition to `GameScreen.tscn` showing the exact same challenge simultaneously.
   - On each window, verify that:
     - The local player's score is labeled **"YOU"**.
     - The opposing player's score is labeled **"OPPONENT"**.
   - Submit answers on both screens: the host validates, updates scores, and advances rounds synchronously until the **Match Results** screen is shown.
   - The winner receives **"VICTORY"** and the loser receives **"DEFEAT"**.

---

## 4. Physical Android Hotspot Manual Test Procedure
Follow these exact steps to test multiplayer between two Android phones without an internet connection:

1. **Network Setup**:
   - On **Phone A (Host)**: Open Android Settings -> Network & Internet -> **Personal Hotspot** (or Portable Hotspot) -> Turn **ON**.
   - Note Phone A's Hotspot IP (standard default is `192.168.43.1`).
   - On **Phone B (Client)**: Open Android Settings -> Wi-Fi -> Scan and **Connect to Phone A's Hotspot**.
   - *(Note: Mobile data can be completely turned off on both phones; hotspot routing is purely local).*

2. **Host Session (Phone A)**:
   - Launch **SpotRush**.
   - Tap **LOCAL WI-FI MULTIPLAYER** -> **HOST A GAME**.
   - Tap **START HOST SERVER**.
   - Notice the IP address displayed on the screen.

3. **Join Session (Phone B)**:
   - Launch **SpotRush**.
   - Tap **LOCAL WI-FI MULTIPLAYER** -> **JOIN A GAME**.
   - Enter Phone A's IP address (e.g. `192.168.43.1`).
   - Tap **CONNECT TO HOST**.

4. **Match Progression**:
   - Phone A confirms: *"Players Connected: 2 (Ready to play!)"*.
   - Phone A taps **START MATCH**.
   - Both phones count down *"GET READY... SPOT!"* and display the identical cognitive challenge.
   - Both players submit their answers.
   - Verify that authoritative scores match across both screens.
   - Upon completing the configured rounds, the Results screen appears with Victory/Defeat and accurate statistics.

---

## 5. Android Build Readiness Status
- **Installed Dependencies**:
  - Java JDK: Present and verified.
  - Android SDK & Build Tools (36.0.0, 36.1.0, 37.0.0, android-36.1): Present.
  - ADB: Present at `C:\platform-tools\adb.exe`.
- **Export Templates**:
  - Missing: `%APPDATA%\Godot\export_templates\4.7.2.stable\android_debug.apk`.
  - Note: Per user directive, export templates were not downloaded or installed. Once installed via Godot Editor (`Manage Export Templates`) or CLI, the APK can be exported with:
    ```powershell
    & 'path/to/godot' --headless --export-debug "Android" build/SpotRush.apk
    ```
