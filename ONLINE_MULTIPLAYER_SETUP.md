# SpotRush online multiplayer — EOSG 2.3.1 (Godot 4.7.2)

## Current implementation

This integration adds the EOS lobby/P2P path while preserving the existing LAN/ENet path and the game's reliable RPC protocol.

- `NetworkSession` accepts a generic `MultiplayerPeer`; ENet and `EOSGMultiplayerPeer` use the same RPC/message layer.
- `EOSOnline` initializes EOS lazily, creates/reuses a Device ID, performs EOS Connect login without a player-facing login screen, creates public two-player lobbies, browses/searches rooms, joins a lobby, and opens the EOS P2P peer.
- A generated room has an eight-character room code and the name `SpotRush Duel <CODE>`.
- Exact eight-character codes use an EOS lobby-attribute equality query. Partial code/name searches filter the returned public open rooms locally. EOS's lobby query limit is 200 results, so this is a bounded discovery list, not an unlimited full-text search over every room worldwide.
- The host remains authoritative. `NetworkProtocol.gd` and the existing match RPCs are not replaced.
- LAN discovery/hosting through ENet remains available.
- Online QR invitations use `spotrush://join?code=<CODE>`. LAN QR invitations continue to use `spotrush://join?ip=<LAN-IP>&port=<PORT>`.
- EOS application foreground/background/network status follows the existing `AppLifecycle` autoload.

**Validation status:** the GDScript and build configuration have been statically checked against EOSG 2.3.1 source and Godot 4.7.2 template conventions. This environment does not have Godot 4.7.2 or an Android device, so it has not run a Godot import, native plugin load, Android export, or two-device network test. Treat the first test build as an integration test, not a release build.

## EOSG files and platform setup

SpotRush uses EOSG **2.3.1**. The 94 MB Windows + Android addon directory can stay on the developer's machine; it does not need to be uploaded to ChatGPT.

Expected local layout:

```text
addons/epic-online-services-godot/
  plugin.cfg                 # version 2.3.1
  eos.gd
  eosg.gdextension
  runtime.gd
  heos/                      # EOSG high-level scripts
  bin/android/               # Android ARM64/x86_64 GDExtension + EOS SDK AAR
  bin/windows/               # Windows x64 GDExtension + EOS SDK DLLs
```

Run the one-time EOSG 2.3.1/Godot 4.7 compatibility patch from the SpotRush project root before opening Godot:

```powershell
python tools/patch_eosg_autoload_scope.py
python tools/verify_eos_install.py --platform both
```

The first script modifies only the shared `addons/epic-online-services-godot/eos.gd` source. EOSG 2.3.1 references its `EOSGRuntime` autoload directly inside nested option-class defaults; the compatibility patch resolves those defaults through the scene tree so Godot's import pass does not need to resolve that singleton as a compile-time identifier. It is idempotent and does not touch native binaries. The validator checks required Windows/Android files, the compatibility patch and project wiring. It never prints credential values. Afterward, close and reopen the Godot editor so the updated project settings and addon scripts are reimported.

### Android CI package handling

The Android GitHub Actions workflow downloads the official EOSG 2.3.1 Android package, verifies its SHA-256, and installs the Android addon files on the runner. It then adds the Linux host binary needed by the Ubuntu Godot editor. This avoids committing the entire 94 MB Windows + Android directory to the source repository. Your Windows binaries stay local for Windows editor/testing builds.

For a separate Windows CI release workflow, install the matching EOSG 2.3.1 Windows release binaries on that runner as well.

## Local EOS credentials

`EOSLocalConfig.gd.example` contains the public Product, Sandbox, Deployment, and Client IDs. The private `scripts/networking/EOSLocalConfig.gd` is ignored by Git.

Create the local file securely from PowerShell:

```powershell
.\tools\set_eos_client_secret.ps1
```

The helper prompts for the EOS Client Secret and the 64-character hexadecimal EOS Encryption Key using hidden input. The previously exposed Client Secret should be rotated before public distribution; for a local test build, never paste it into chat or commit it. It creates `scripts/networking/EOSLocalConfig.gd` and does not print either value. Do not put the Client Secret in the `.example` file, the patch, or source control.

Validate local credentials without displaying them:

```powershell
python tools/verify_eos_install.py --platform both --require-local-config
```

For GitHub Actions, add Actions secrets named `EOS_CLIENT_SECRET` and `EOS_ENCRYPTION_KEY`. The Android workflow generates the ignored config file during the build.

**Client credential warning:** the Client Secret is used by the client-side EOS SDK and is included in the exported game if this configuration script is exported. A GitHub Actions secret protects the source value during CI, but does not make the value secret inside the APK. Use a least-privilege EOS Client Policy with `User Required`, only the Connect Device ID login/create-user actions and Lobby/P2P actions the game actually uses. Do not grant Trusted Server, administrative, or unrelated service permissions. The Client Secret previously pasted into chat should be rotated before any public distribution; update the local config and GitHub Actions secret after rotation.

### Encryption key

EOSG's initialization guide asks for a random 64-character hexadecimal encryption key and passes it to `EOS.Platform.CreateOptions`. SpotRush stores it only in the ignored local config and supplies it during platform initialization. It is separate from the OTA updater/signing key; do not reuse the OTA key. Keep the EOS key consistent across builds for this Product.

## Required EOS Product configuration

In the Epic Developer Portal, confirm:

1. The Product, Sandbox, and Deployment IDs in `EOSLocalConfig.gd.example` match the intended development deployment.
2. The Client Policy is a **game client / User Required** policy, not a Trusted Server policy.
3. The policy permits the Connect Device ID login flow, Connect CreateUser for first-time anonymous identities, public Lobby create/search/join/update/leave/destroy, and P2P connectivity/relay fallback.
4. The active Deployment has Game Services / Lobbies enabled.

The player does not sign into an Epic Games account. EOS Connect creates/reuses an anonymous Device ID identity internally so EOS can identify each lobby member and establish P2P connections.

## Android export setup

The existing Android export preset and its `min_sdk="24"` value are deliberately unchanged. EOSG's documented minimum is lower; do not lower SpotRush's current minimum.

For a local Android export:

1. In Godot 4.7.2, install the Android build template from the Project menu (Install Android Build Template / Gradle Build Template). Godot documents that this creates the Gradle project under `res://android/build`, including the manifest and Gradle files. If `android/build` does not exist, the template is not installed yet.
2. From the SpotRush project root, run:

   ```powershell
   python tools/patch_android_template.py
   python tools/patch_eos_android_template.py
   ```

3. Export the Android preset. The scripts patch only the generated `android/build` template: the first registers `spotrush://join` on the launcher activity; the second adds EOS's Android SDK AAR/dependencies, the EOS client-scheme resource, native library load, and EOS Android initialization. Both are idempotent. The updated patcher handles the generated Gradle template's comments and string forms, verifies exactly one target block, and is idempotent. It preserves SpotRush's existing `minSdk` value (24) because it already exceeds EOS's documented minimum (23).

The exported APK must be installed fresh after the Android manifest/activity changes. PCK-only OTA updates cannot change Android intent filters or Java activity initialization.

The GitHub Actions workflow performs these template steps automatically before exporting.

## First test sequence

1. Run SpotRush in the Windows Godot editor with the local Windows EOSG binaries installed. Confirm the EOSG native class is loaded and anonymous initialization succeeds.
2. Create a public room. Confirm the returned room code is eight characters and the lobby is visible in the Join tab.
3. On a second device, install the new Android APK and use mobile data or a different Wi-Fi network (not the same LAN).
4. Search for the exact room code and join. Confirm the EOS P2P connection reaches `NetworkSession.connection_succeeded`.
5. Play a complete duel and verify the existing reliable RPC flow, host authority, disconnect cleanup, room status updates, and return-to-lobby cleanup.
6. Scan the host's online QR with the phone camera. Android should offer/open SpotRush; the game should route to Join and resolve the room code. Test both a cold launch and a warm/background launch.
7. Repeat with two devices behind different NATs. EOS direct connectivity is preferred; EOS relay fallback is allowed when direct NAT traversal fails. Relay paths may have higher latency than direct paths.

Do not call the feature release-ready until these device tests pass. Godot import/export success alone does not prove cross-network P2P connectivity.
