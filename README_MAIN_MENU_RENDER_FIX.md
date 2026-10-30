# SpotRush main menu render-matching patch

This patch addresses the actual in-Godot screenshot supplied after the first menu implementation. It keeps the existing portrait composition and navigation wiring, but fixes the mismatched proportions visible in the render.

## What changed

- Enlarges the SPOTRUSH wordmark according to logical viewport width, with two offset native RichTextLabel layers to add a subtle highlight and colored extrusion.
- Scales tagline, Play, Friends, How to Play, Online and score typography from the viewport instead of keeping small fixed sizes.
- Reduces the header bar's height so Settings and Online become horizontal pills instead of tall vertical capsules.
- Enlarges the core action glyphs and adds a subtle native-panel sheen to Solo Play.
- Narrows the Best Score capsule to about 30% of the screen and changes it from strong yellow to soft ivory.
- Keeps the earlier parser fix in MainMenuCanvas.gd by explicitly typing the mouse event and normalized Vector2.

## Installation

Merge the paths under this archive into the existing SpotRush project root, replacing files when prompted. Do not replace `project.godot` or other project files. Open the existing project in Godot and run the MainMenu scene/project normally.

## Validation status

The modified scene and script resource references were checked statically. This archive does not include `project.godot`, so a Godot runtime parse or in-engine screenshot could not be run in this environment.
