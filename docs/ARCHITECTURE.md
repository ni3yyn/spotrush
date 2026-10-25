# SpotRush — Architecture Documentation

## 1. High-Level Architectural Principles
SpotRush is built as a modular, responsive 2D cognitive challenge game targeting Android (portrait) and PC Desktop using Godot 4.7 and GDScript.

The architecture enforces strict separation between:
1. **Challenge Data Model & Generators (`scripts/challenges`, `scripts/game`)**: Pure, testable logic completely decoupled from networking and UI rendering.
2. **Authoritative Match Progression & Scoring (`scripts/game`)**: State machines managing round timers, answer validation, deterministic integer scoring, and disconnect handling.
3. **Network Transport Abstraction (`scripts/networking`)**: ENet high-level multiplayer isolated behind `NetworkSession` and structured `NetworkProtocol` packet wrappers.
4. **Presentation & UI (`scenes/`, `scripts/ui`)**: Responsive Godot Control nodes listening to signals from `GameManager` and drawing challenges cleanly on any screen resolution.

```
       +-------------------------------------------------------------+
       |                         USER INTERFACE                      |
       |  MainMenu  |  LocalLobby  |  GameScreen  |  MatchResults   |
       +-------------------------------------------------------------+
                                      |
                           (Signals & UI Actions)
                                      v
       +-------------------------------------------------------------+
       |                      CORE / MANAGERS                        |
       |     GameManager (Autoload)     |   SceneRouter (Autoload)   |
       +-------------------------------------------------------------+
               |                                            |
         (Authoritative State)                    (Packets / RPC)
               v                                            v
+-------------------------------+             +------------------------------+
|       GAMEPLAY ENGINE         |             |       NETWORKING LAYER       |
|  - MatchController            |             |  - NetworkSession (Autoload) |
|  - ScoreManager               |             |  - NetworkProtocol           |
|  - ChallengeGenerator         |             |  - ENetMultiplayerPeer       |
|  - AnswerValidator            |             |                              |
|  - ChallengeDefinition        |             |                              |
+-------------------------------+             +------------------------------+
```

---

## 2. Core Modules

### 2.1 Challenge Definition (`ChallengeDefinition.gd`)
Represents structured challenge data:
- `id`: Unique identifier per challenge.
- `type`: Estimation count, Side comparison, Color target, Shape target, Don't tap, Combined conditional.
- `difficulty`: 1 (Easy) to 4 (Expert).
- `instruction`: Human-readable prompt.
- `time_limit`: Authoritative duration (seconds).
- `visual_data`: Coordinate map of objects (x, y normalized 0.0-1.0, shape, size, color, target flags).
- `options`: Array of selectable choices (for multiple-choice challenges).
- `correct_answer`: Expected answer (number, string, or boolean for withhold).
- `input_mode`: `"choice"`, `"tap_targets"`, or `"withhold_response"`.
- `to_dict()` and `from_dict()` for network serialization.

### 2.2 Procedural Generator (`ChallengeGenerator.gd`)
Generates validated, fair challenges:
- **Quantity Estimation**: Random dots placed across field, with distractor numbers calculated close to actual count.
- **Side Comparison**: Left vs Right field split with controlled margin based on difficulty.
- **Target Selection (Color & Shape)**: Targets mixed with distractors; coordinates normalized.
- **Don't Tap (Inhibition)**: Explicit instructions on whether to tap or withhold, scored on patience until round timeout.
- **Combined Conditional**: Multi-variable rule test (e.g. "Are there at least 15 RED dots?").

### 2.3 Answer Validator (`AnswerValidator.gd`)
Pure verification logic:
- Verifies option match or target hit completeness.
- Detects false positives (distractor taps).
- Enforces deadline with 500ms network jitter grace period; rejects late answers.
- Authoritatively scores withhold challenges upon timeout.

### 2.4 Score Manager (`ScoreManager.gd`)
- Fast correct answer bonus: up to +500 points depending on remaining time ratio.
- Base points: +1,000 for correct answer.
- Penalty: -150 for incorrect selection.
- Authoritative mirroring:
  - `set_player_score(player_id, score)`: Allows client to synchronize intermediate scores upon receiving `MSG_ANSWER_RESULT`.
  - `apply_authoritative_scores(scores_dict)`: Overwrites client scores to match host authoritative record on `MSG_ROUND_END`.
- In-memory stats recording: accuracy %, average response time, best round score, tie detection.

### 2.5 Match Controller (`MatchController.gd`)
Central authoritative state machine:
- States: `IDLE` -> `COUNTDOWN` -> `ACTIVE_ROUND` -> `FEEDBACK` -> `MATCH_OVER`.
- Controls round progression and prevents duplicate answers from the same player.
- **Disconnect Handling**: `handle_peer_disconnected(peer_id)` inspects active multiplayer participants. If a player disconnects mid-match, the controller cleanly finishes the match and declares the remaining player the victor.

### 2.6 Network Session & Protocol (`NetworkProtocol.gd`, `NetworkSession.gd`)
- **Transport**: ENet UDP transport on port 7000 (configurable).
- **Authoritative Model**: The host (Peer ID 1) is the sole authority for challenge generation, answer evaluation, score calculation, and phase progression. Clients only transmit their input payloads (`MSG_SUBMIT_ANSWER`).
- **Packet Validation**: Every payload is wrapped in `NetworkProtocol` with `PROTOCOL_VERSION = 1`, sender validation, and payload schema verification. Stale round IDs and malformed payloads are discarded.
- **RPC Routing**: Handled via `NetworkSession.gd` using `@rpc("any_peer", "reliable")` for data delivery and `@rpc("authority", "reliable")` for broadcast commands.

---

## 3. UI and Peer Identity Architecture

### 3.1 Local vs Opponent Perspective
Godot's multiplayer assigns Peer ID 1 to the host, while connecting clients receive dynamic peer IDs (e.g. `706392015`).
- The UI (`GameScreen.gd`, `MatchResults.gd`) never assumes Player 1 is the local user.
- Instead, the UI queries `local_id = NetworkSession.get_local_id()`.
- On both devices:
  - The local player's score and statistics are always presented under the label **"YOU"**.
  - The other player's score is presented under **"OPPONENT"**.
  - Victory and defeat outcomes reflect the perspective of the local device.

### 3.3 Visual Challenge Rendering Pipeline (`ChallengeCanvas.gd`, `ChallengeView.gd`)
The visual challenge area is decoupled into an orchestration view and a dedicated native rendering canvas:
```
GameScreen (HUD, Timer, Progression)
  └── ChallengeView (Instruction, Badge, Options/Actions)
        └── PlayFieldContainer (PanelContainer, rounded border frame)
              └── ChallengeCanvas (Dedicated Control with native _draw() override)
```
- **Native Hardware-Accelerated `_draw()`**: `ChallengeCanvas` extends `Control` and directly overrides `func _draw() -> void`. All geometric primitives (circles, squares, equilateral triangles, diamonds, dividing lines, pill headers, and checkmarks) are rendered within the engine's active `NOTIFICATION_DRAW` context.
- **Padded Playfield Coordinate Mapping**: Procedurally generated normalized coordinates `(0.0 to 1.0)` are mapped into an inset bounding rect with 24px padding (`pad + (x * playable_width)`), guaranteeing objects never clip into container borders.
- **Tactile Touch Collision**: In `tap_targets` mode, touch and mouse clicks are checked against item coordinates using distance checks with generous mobile touch margins (minimum 28px radius). Tapped items immediately render an expanding mint glowing aura and a dark checkmark badge.
- **Tactile Entrance & Animation**: Elastic scale pop-in is applied via Godot's native GPU transform matrix (`pivot_offset` and `scale`), ensuring shapes render immediately at full resolution without waiting on CPU tween callbacks.
- **Tailored Control Panels**: `ChallengeView` dynamically generates high-contrast touch controls based on challenge semantics:
  - Estimation: 4 wide numerical cards with mint accents.
  - Side Comparison: "LEFT" (mint) and "RIGHT" (amber) tactile buttons with corresponding on-canvas pill headers.
  - Target Selection: "CONFIRM SELECTIONS (X / Y TARGETS)" real-time counter button.
  - Inhibitory Control: Distinct "DON'T TAP! (WITHHOLD ACTION)" vs "TAP NOW!" action cues.
  - Conditional: Prominent "YES" (mint) and "NO" (coral) buttons.

---

## 4. Test Harness Architecture

1. **Unit & Logic Suites (`tests/test_*.gd`)**:
   - Decoupled tests run against pure GDScript classes (`ChallengeGenerator`, `AnswerValidator`, `ScoreManager`, `NetworkProtocol`, `MatchController`).
2. **Autoload-Aware Scene Runner (`tests/TestRunner.tscn`)**:
   - Executes headless within the complete Godot engine scene tree, with all autoload singletons initialized, verifying UI scene instantiation, node bindings, and rendering dispatch.
3. **Challenge Rendering Regression Suite (`tests/test_challenge_rendering.gd`)**:
   - Validates that every challenge family correctly populates `ChallengeCanvas`, verifies node hierarchy, validates color mapping, and simulates tap interactions.
4. **Real Multi-Process Integration Test (`tests/real_network/`)**:
   - PowerShell script spawns two distinct OS processes (`host_process.gd` and `client_process.gd`) communicating over OS UDP sockets via ENet to verify live handshake, challenge exchange, authoritative scoring, and exit codes.
5. **Real GPU Rasterization Visual Verifier (`tests/CapturePreview.tscn`)**:
   - Executes inside Godot's live compatibility graphics pipeline and exports PNG screenshots to `docs/screenshots/` verifying real pixels are rendered on screen.

