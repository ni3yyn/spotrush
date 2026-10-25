# SpotRush — Architecture Documentation

## 1. High-Level Architectural Principles
SpotRush is built as a modular, responsive 2D cognitive challenge game targeting Android (portrait) and PC Desktop using Godot 4.7 and GDScript.

The architecture enforces strict separation between:
1. **Challenge Data Model & Generators (`scripts/challenges`, `scripts/game`)**: Pure, testable logic completely decoupled from networking and UI rendering.
2. **Authoritative Match Progression & Scoring (`scripts/game`)**: State machines managing round timers, answer validation, and deterministic integer scoring.
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
- In-memory stats recording: accuracy %, average response time, best round score, tie detection.

### 2.5 Match Controller (`MatchController.gd`)
Central authoritative state machine:
- States: `IDLE` -> `COUNTDOWN` -> `ACTIVE_ROUND` -> `FEEDBACK` -> `MATCH_OVER`.
- Controls round progression and prevents duplicate answers from the same player.

### 2.6 Network Session & Protocol (`NetworkProtocol.gd`, `NetworkSession.gd`)
- ENet UDP transport on port 7000.
- Host is fully authoritative.
- Packets validated with version checking (`PROTOCOL_VERSION = 1`).
- Clean separation from engine scene tree.
