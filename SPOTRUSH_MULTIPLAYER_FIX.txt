SpotRush multiplayer handoff fix
=================================

This patch replaces the competing application-level match-start ACK/retry flow
with one host-authoritative, reliable start packet.

Flow
----
1. The host's Start Duel button is enabled only after Godot reports the peer
   connected and EOSG's get_all_peers() contains that remote peer.
2. The host queues the round count and enters GameScreen. It does not wait for
   an EOS lobby metadata update while navigating.
3. GameScreen prepares the host match and sends one reliable MSG_MATCH_START
   broadcast to the connected EOSG peer(s).
4. EOSG uses server peer ID 1. The joiner accepts this command only from peer
   ID 1, initializes a fresh client match (including rematches), and enters
   GameScreen.
5. The normal reliable RPC channel then carries countdown, round, clock, and
   result packets in order. There is no separate ACK/retry loop.

EOSG-specific notes
-------------------
- The project uses EOSG's client/server P2P peer mode, not mesh mode.
- EOSG assigns server peer ID 1. The client sends to peer 1; the server
  broadcasts with the normal Godot RPC broadcast path.
- get_all_peers() is used as the server-side source of truth for connected
  remote peer IDs (with the existing ENet peer list retained as a fallback).
- Reliable RPC is used for the match-start command and game-state messages.
- Lobby capacity remains two. The match start does not need to await a lobby
  attribute update; the full lobby has no available slots for another joiner.

Protocol
--------
NetworkProtocol is version 4. Export fresh Windows and Android builds from the
same patched source. Do not run a v3 build against a v4 build.

Files changed
-------------
scripts/core/GameManager.gd
scripts/networking/NetworkProtocol.gd
scripts/networking/NetworkSession.gd
scripts/ui/LocalLobby.gd

Validation limitation
---------------------
The uploaded archive did not include addons/epic-online-services-godot, and a
Godot executable was not available in the inspection environment. The source
was inspected and statically checked, but this patch has NOT been compiled in
Godot or tested on Windows/Android hardware. Keep the EOSG addon already
installed in your existing project when applying the patch.
