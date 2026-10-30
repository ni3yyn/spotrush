# SpotRush Visual Upgrade — merge notes

This bundle is a **visual-layer update** for the supplied SpotRush scene/script slice. It does not include a full Godot project: the source archive provided for this pass did not contain `project.godot`, project assets, or the automated test suite.

## Merge into your existing project

1. Back up the current SpotRush project folder or commit your current state.
2. Extract this archive into the existing project root, preserving the `scenes/` and `scripts/` directories and choosing **merge/overwrite** when prompted.
3. Keep your existing `project.godot`, assets, tests, and any files that are not in this bundle. Do **not** replace your project folder wholesale with this archive.
4. Open the existing project in Godot 4.7.2 and use **Run Project** as usual. No export templates, cloud services, or new plugins are required.

## Main menu — reference-image match

- Rebuilt the main-menu layout as responsive native Godot controls rather than using a flattened screenshot.
- Added a sculpted cream orbit plate, soft corner blobs, floating cobalt/yellow/coral/mint geometry, a two-colour SpotRush wordmark, the spaced tagline, a cobalt Solo Play capsule, raised Friends and How to Play capsules, and a trophy-style Best Score footer.
- Added `scripts/ui/SpotRushGlyph.gd`, a tiny vector-drawing Control used for the gear, play, people, book, trophy, dot, and chevron symbols; no external icon assets are required.
- Kept menu actions wired to the existing single-player, friends/LAN, settings, profile, how-to-play, and score-modal flows.
- The `12,480` score is currently the **reference artwork's sample display value**. It is not yet connected to persistent high-score storage.

## Other screens

- `scripts/ui/SpotRushSkin.gd` provides the shared raised-paper, cobalt, warm-shadow, and inset-control styling.
- `scripts/ui/SpotRushBackdrop.gd` and the updated game, challenge, lobby, and results scenes carry the cream/cobalt/coral/lavender/mint identity through gameplay.
- Preserved challenge generation, answer validation, scoring rules, timers, and networking authority.

## Verification note

Static scene checks passed for this bundle: external resource paths resolve, node parent paths resolve, there are no duplicate properties within scene sections, and every `%Node` reference used by `MainMenu.gd` resolves to a unique scene node.

The container did not include a Godot executable, `project.godot`, assets, or the test suite, so this update has **not** been runtime-compiled or visually verified inside Godot here. After merging, run your existing project in Godot 4.7.2 and check the menu at 360×640 and 390×844, then open every menu modal and verify gameplay/lobby/results before keeping the patch.
