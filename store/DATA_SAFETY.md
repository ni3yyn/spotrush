# SpotRush - Data Safety Form (Play Console → App content → Data safety)

Ground truth first, then the form answers. Everything below describes what the
v21 codebase actually does — nothing here is aspirational.

## Ground truth (what the app really does)

- **No developer collection.** The game contains no analytics, no crash
  reporting, no ads, no accounts, no third-party SDKs. There is no code path
  that sends anything to a developer-owned endpoint.
- **Local storage only.** Settings, records, streaks live in the app's private
  storage (`user://`). Uninstall deletes it. `user_data_backup/allow=true`
  means Android may include it in the device's standard encrypted backup —
  that is OS/Google infrastructure under the user's control, not developer
  collection.
- **Peer-to-peer LAN traffic only.** Duels connect two phones directly over
  Wi-Fi (ENet/UDP on port 7000). The discovery beacon (UDP 42113) carries only
  a magic string + port number. No personal data, no identifiers, nothing
  stored, nothing leaves the LAN.
- **Clipboard** is read only when the player taps PASTE and written only when
  they tap COPY.
- **Permissions:** `INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE` (see
  `export_presets.cfg`). Nothing else.

## Form walkthrough

**Q: Does your app collect or share any of the required user data types?**
→ **No.**
Per Play's definitions, "collect" means transmitting data off the device in a
way the developer can access. Peer-to-peer LAN gameplay between two player
phones is not developer collection. Nothing else leaves the device.

Because the answer is **No**, the follow-up questions (data types matrix,
encryption in transit, deletion mechanism) do not apply — the form simply ends.

## What to answer in the permissions declarations section (if shown)

| Permission | Declared purpose |
|---|---|
| INTERNET | Local multiplayer gameplay between devices on the same network |
| ACCESS_NETWORK_STATE | Checking network availability for local multiplayer |
| VIBRATE | Haptic feedback (user-toggleable in Settings) |

## Honesty guards for future versions

If any of these change, this form MUST be redone before release:
- adding analytics / crash reporting → answer changes to Yes
- adding accounts or cloud saves → answer changes to Yes
- adding ads → new SDK disclosures required
- any server, ever → answer changes to Yes

The current architecture makes "No" the truthful answer. Keep it that way
until there is a reason not to.
