# SpotRush – True Neumorphic UI (v2)

Merge over your project root (keep your own `project.godot`, assets, autoloads). Verified in Godot 4.7.2:
scenes load with zero script errors and were rendered/click-tested in-engine (Main menu, settings modal,
pressed states, plus Game/Results/Lobby smoke tests).

## Why the old one didn't look neumorphic
`StyleBoxFlat` has a single shadow. Neumorphism needs a light shadow top-left AND a dark shadow bottom-right,
convex sheen on raised parts, and genuine inset states. So this adds a custom StyleBox.

## New files
- `scripts/ui/NeuStyle.gd`  – the material (dual soft shadows, inset shadows, sheen, rim light). One `depth` value:
  >0 raised, <0 pressed-in, animatable.
- `scripts/ui/NeuKit.gd`    – palette, factories, click-depth animation, token/disc helpers, backdrop.
- `scripts/ui/NeuSwitch.gd` – sunken-track / raised-thumb toggle (replaces CheckButton visuals).
- `scripts/ui/NeuMenuBackdrop.gd` – static menu surface (drawn once, not every frame).

## Changed files
`SpotRushSkin.gd` (routes every Button/Panel/Progress/LineEdit/Tab through NeuStyle; public API unchanged),
`SpotRushGlyph.gd` (sockets, etched icons, LED dot), `SpotRushBackdrop.gd`, `MainMenuCanvas.gd`, `MainMenu.gd`,
`scenes/main/MainMenu.tscn` (PlaySheen gloss removed, 4-layer emboss wordmark, socketed icons, switches).

## Click depth
Buttons sink on press (70ms) and spring back (340ms, overshoot). Round-count selector: selected = pressed in.
Emblem and the two tappable tokens physically sink when tapped.

## Re-theming
Everything derives from `SURFACE / LIGHT / DARK` at the top of `NeuKit.gd`. Warm cream variant:
`E9E2D2 / FFFFFF / C9BDA3`-ish.

## Not done yet
In-match visuals (ChallengeView / ChallengeCanvas answer buttons, shape tokens, GameScreen HUD art) still use their
own hard-coded cream StyleBoxFlats, so they will look slightly off against the cool surface until they're ported.

---
# v3 – Gameplay screen (solo + multiplayer HUD)

Verified in Godot 4.7.2: live 3-round match with real countdown/timer/answers, real mouse clicks on tokens and
answer keys, all 6 challenge types, multiplayer HUD variant. No script errors.

## What changed
- **Timer**: the thin bar is replaced by `NeuTimerDial` – raised plate, sunken groove, lit arc that drains
  cobalt -> canary -> coral, raised knob with the seconds, pulsing glow when urgent. (`NeuTimerDial.gd`, `NeuTimerArc.gd`)
- **HUD**: sunken readouts for Round / Score; `NeuRoundPips` row fills mint (correct) / coral (wrong) per round.
- **Play field**: raised slab holding a sunken tray. Tokens (dots, squares, triangles, diamonds) are raised
  neumorphic objects; WHITE tokens are pure surface bumps. Tapped tokens animate down into the tray with a mint
  ring + check badge. Comparison mode = two trays; the chosen side presses deeper and tints cobalt/coral.
- **Answer keys**: raised keys that stay pressed-in once chosen (others dim). YES/NO are mint/coral accent keys.
  The confirm key recolours by state (plain -> mint when ready, coral when you must hold back).
  Tap/withhold rounds hide the empty key row, giving the field more space.
- **Feedback**: tactile mint/coral card (title + detail line) and a result ring flash around the tray;
  countdown gets a frosted scrim.
- Round/score now live in caption+value pairs (`CapScore`, `LblRound`, `LblScoreP1`...). `TimerBar` was removed.

## Files
New: `NeuTimerDial.gd`, `NeuTimerArc.gd`, `NeuRoundPips.gd`
Rewritten: `ChallengeCanvas.gd` (visuals only; input + signals unchanged), `GameScreen.tscn`
Changed: `GameScreen.gd`, `ChallengeView.gd/.tscn`, `SpotRushSkin.gd`, `NeuKit.gd`

## Not done
`MatchResults` screen still has the older compact layout (it inherits the neumorphic material through the skin).
Challenge generation / scoring / networking logic are untouched.

---
# v4 – Neumorphic text, pop-ups, game tokens, hierarchy

## New: NeuText (scripts/ui/NeuText.gd)
Custom text control (Godot's Label has one hard shadow only). Four looks:
`DEBOSS` engraved into the surface, `EMBOSS` raised (decorative only: low contrast by nature),
`LIT` glowing LED digits (score), `ON_ACCENT` light letters on coloured surfaces (pop-ups, YES/NO keys).
Extras: real bold weight (works with any project font), letter-spacing, auto-highlight of ALL-CAPS key words
(`Tap ALL SQUARE shapes!`), and `bind_style()` so key labels dip with the key when pressed.

## Pop-ups
- GET READY / SPOT!: raised cobalt card; on SPOT! the card is pressed in then springs back, text turns lit canary.
- CORRECT / MISSED / STREAK / IMPULSE FAULT: accent card with a sunken check/cross badge (result is not colour-only),
  title, detail line, and the points as their own big readout.

## Games
- Tap rounds (colour / shape / don't-tap): every token sits in its own sunken socket and presses into it when tapped.
- Counting rounds stay uncluttered (no sockets). Tray chips LEFT/RIGHT larger.
- Instruction card: bold 30px engraved text with key words in cobalt; HUD captions are quiet, score is the lit hero.

## Engine note (important)
Inner shadows no longer use stacked border rings. Ten+ sockets of ring draws corrupted batching in the
Compatibility renderer at a non-1 stretch scale (large translucent polygons). Inner shadows are now ONE gradient
mesh each (smoother falloff, far fewer draw commands) with per-shape geometry caching.
Measured CPU cost to record (desktop, software GL): socket 49us (was 119us), tray 48us (was 361us).

## Files
New: NeuText.gd  Changed: NeuStyle.gd, NeuKit.gd, SpotRushSkin.gd, SpotRushGlyph.gd (check/cross),
GameScreen.tscn/.gd, ChallengeView.tscn/.gd, ChallengeCanvas.gd
Text nodes that were Labels are now NeuText (typed `NeuText` in GameScreen.gd/ChallengeView.gd).

---
# v5 – Results screen

Single-player and multiplayer, driven by real ScoreManager data (verified by playing a real match through to the router).

## Elements
- Hero card: rank medal (S >= 95% accuracy, A >= 80, B >= 60, else C - tweak `rank_for()` in MatchResults.gd),
  outcome headline, lit count-up score, NEW PERSONAL BEST chip (solo).
- Multiplayer: VICTORY / DEFEAT / TIE headline + tug-of-war versus bar (`NeuVersusBar`).
- Accuracy gauge (reuses `NeuTimerDial` with `custom_color`, sweeps in, colour by accuracy).
- Six sunken stat tiles: correct, wrong, timeouts, best streak, avg time, fastest.
- Round breakdown chart (`NeuRoundChart`): per-round raised bars - mint scored, coral lost points, hollow = timeout,
  gold + crown = best round. Staggered spring-in. Empty-state message when nothing scored.
- Actions: Play Again (accent key), Main Menu. Captions are NeuText children that dip with the key.
- Intro animation: cards rise in sequence, medal pops, numbers count up.

## New persistence
`scripts/core/Records.gd` stores the best solo score in `user://spotrush_records.cfg`.
The main menu's BEST SCORE now shows this real value (it was a hard-coded "12,480").

## Files
New: Records.gd, NeuMedal.gd, NeuRoundChart.gd, NeuVersusBar.gd
Rewritten: MatchResults.tscn / MatchResults.gd
Changed: SpotRushSkin.gd (new card/tile names), SpotRushGlyph.gd (clock, bolt, crown, star), NeuTimerDial.gd, MainMenu.gd

---
# v6 - Motion and feel

Neumorphism is visually quiet, so satisfaction comes from motion, sound and touch. One small "Feel" layer drives it all.

## The Feel layer (scripts/core)
- `Settings.gd`  persisted toggles in user://spotrush_settings.cfg: sfx, haptics, particles, reduce_motion.
- `Sfx.gd`       soft synthesized sound bank (no audio assets): press, release, pop, correct, wrong, tick, whoosh, spot,
                 pip, count, chime, fanfare, toggle on/off. Built once and cached (one sound per frame at startup),
                 8-voice round-robin, pitch variation. Tuned for phone speakers: nothing important lives below ~150 Hz,
                 and the "wrong" sound is softer than "correct" so failure never feels harsher than success.
- `Feel.gd`      single call site: Feel.sfx(name, pitch), Feel.haptic(kind), Feel.reduced().
  Haptics use Input.vibrate_handheld on Android/iOS only (desktop no-op).

## What you feel
- Every button (all NeuKit keys): soft "thock" on press, light tick on release, light haptic, 2.6% squish with a spring back.
- Menu: pieces rise in one after another. Settings now has Haptic Feedback and Reduce Motion switches (persisted).
- Game: GET READY whoosh, SPOT! punch + the card presses in; tokens rise out of their sockets as a diagonal wave
  (top-left to bottom-right, matching the light); tap = ripple + pop whose pitch climbs with each target collected;
  timer ticks in the last 3 seconds (rising pitch) and the knob bumps like a clock; pips pop with a ring;
  correct = chime (pitch rises with streak) + burst + the points number flies from the card into the score;
  wrong = soft bonk + field shake.
- Results: whoosh, ticking count-up, rank-pitched medal chime, fanfare + burst for NEW BEST or S rank.
- Scene changes: soft light cross-fade (the old curtain was near-black and flashed dark).

## Reduce Motion
Disables staggered entrances, tap ripples/rise, bursts, shake, squish, flying points and count-ups (Results shows final
numbers immediately); transitions shrink to ~50 ms. Sounds are controlled separately by Sound Effects.

## Files
New: Settings.gd, Sfx.gd, Feel.gd, NeuBurst.gd
Changed: NeuKit.gd, NeuSwitch.gd, NeuRoundPips.gd, NeuTimerDial.gd/NeuTimerArc.gd, ChallengeCanvas.gd, GameScreen.gd/.tscn,
         MatchResults.gd/.tscn, MainMenu.gd/.tscn, SceneRouter.gd
Removed: the menu's per-click WAV generator (it rebuilt samples in GDScript on every click and had one voice)

## Not verified
Audio was analysed numerically (levels, clipping, edge clicks, spectrum) and the pipeline was functionally tested,
but never listened to. Haptics could not be exercised off a real device. Please audition /sounds and test on a phone.
