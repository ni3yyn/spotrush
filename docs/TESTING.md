# SpotRush — Testing & Validation Guide

## 1. Automated Test Suite
SpotRush contains an automated test harness designed to run via Godot 4's headless CLI.

### Running Headless Tests
From the project root:
```powershell
& 'C:\Users\HP\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe' --headless -s res://tests/test_runner.gd
```
Or if `godot` is in PATH:
```bash
godot --headless -s res://tests/test_runner.gd
```

### Verified Test Suites (78 Passed, 0 Failed)
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
4. **`TestNetworkingLogic` (5 tests)**:
   - Packet structure and version checking.
   - Stale/corrupt packet rejection.
   - Round answer state validation.
   - Duplicate round submission rejection.
5. **`TestFullGameLoop` (9 tests)**:
   - Complete 5-round single player match loop (Countdown -> Active -> Feedback -> Match Over).
   - Authoritative match conclusion.
   - Rematch pristine state reset.
6. **`TestMultiplayerSimulation` (6 tests)**:
   - Real ENet server and client peer creation on localhost.
   - Asynchronous handshake polling and connection confirmation.
   - Dual-player simultaneous answer submission.
   - Host authoritative scoring computation for both peers.

---

## 2. Desktop Dual-Instance Manual Testing (Localhost)
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
   - Submit answers on both screens: the host validates, updates scores, and advances rounds synchronously until the **Match Results** screen is shown.

---

## 3. Physical Android Hotspot Manual Test Procedure
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
   - Upon completing all 10 rounds, the Results screen appears with Victory/Defeat and accurate statistics.
