extends Node
class_name LanDiscovery

# v21 LAN DISCOVERY - duels without typing.
#
# Before this, joining a duel meant the host reading an IP address out loud
# and the friend typing it digit by digit. Now the host's open room shouts a
# tiny UDP beacon onto the local network a few times a second ("SPOTRUSH1|7000")
# and every phone sitting on the JOIN tab hears it and lists the game. One tap
# joins. The game code well stays on the screen for the rare Wi-Fi (some hotel
# and office routers, "AP isolation") that blocks device-to-device broadcast.
#
# The transport is deliberately dumb and unauthenticated on purpose: the beacon
# carries no personal data and no game state - just a magic string and the ENet
# port. The ENet session itself keeps its versioned, validated protocol
# (NetworkProtocol), exactly as it did when codes were typed by hand.
#
# The static core (encode/parse/rank/note) is pure and unit-tested by section 9
# of ChallengeSystemSelfTest, so the codec and TTL logic are verified headless
# without opening any sockets.
#
# v21 QR: the same module also owns the JOIN CODE format - the text a host's
# QR square encodes ("SPOTRUSH:JOIN:<ip>:<port>", see QrCode.gd) and the
# clipboard parser that turns a friend's camera-app scan into a one-tap join.

## Emitted only when the visible set of games changes (a game appears or a
## stale one expires). Refreshes do not re-emit, so the lobby list stays calm.
signal games_changed

const BEACON_MAGIC := "SPOTRUSH1|"
const BEACON_INTERVAL_MSEC := 900   # beacon rhythm: fast enough to feel instant
const ENTRY_TTL_MSEC := 4000        # a game silent this long is gone from the list
const MAX_LISTED_GAMES := 3         # lobby shows at most this many rows

var _advertiser: PacketPeerUDP = null
var _advertising := false
var _advertising_port := 0
var _last_beacon_ms := -1000000

var _listener: PacketPeerUDP = null
var _scanning := false
var _listener_failed := false       # the OS refused the discovery port
var _entries: Dictionary = {}       # ip -> {"ip": String, "port": int, "seen_ms": int}
var _own_ips: PackedStringArray = []  # beacons from this very phone are ignored

func _process(_delta: float) -> void:
        var now := Time.get_ticks_msec()
        if _advertising and now - _last_beacon_ms >= BEACON_INTERVAL_MSEC:
                _last_beacon_ms = now
                _send_beacon()
        if _scanning:
                _drain_packets(now)
                _prune(now)

func _exit_tree() -> void:
        stop_advertising()
        stop_scanning()

# --- advertising (the host's phone) ---------------------------------------------------

func start_advertising(port: int) -> void:
        stop_advertising()
        var broadcaster := PacketPeerUDP.new()
        broadcaster.set_broadcast_enabled(true)
        var err := broadcaster.set_dest_address("255.255.255.255", GameConfig.DISCOVERY_PORT)
        if err != OK:
                push_warning("LanDiscovery: could not address broadcast (%d)" % err)
                broadcaster = null
                return
        _advertiser = broadcaster
        _advertising_port = port
        _advertising = true
        _last_beacon_ms = -1000000 # first beacon goes out on the next frame

func stop_advertising() -> void:
        _advertising = false
        if _advertiser != null:
                _advertiser.close()
                _advertiser = null

func is_advertising() -> bool:
        return _advertising

func _send_beacon() -> void:
        if _advertiser != null:
                _advertiser.put_packet(encode_beacon(_advertising_port))

# --- scanning (the joining phone) -----------------------------------------------------

func start_scanning() -> void:
        if _scanning:
                return
        if _listener == null:
                var socket := PacketPeerUDP.new()
                var err := socket.bind(GameConfig.DISCOVERY_PORT)
                if err != OK:
                        # Port taken (another instance on this device?) or blocked:
                        # the join tab simply falls back to the game code well.
                        push_warning("LanDiscovery: cannot bind discovery port (%d)" % err)
                        _listener_failed = true
                        games_changed.emit()
                        return
                _listener = socket
        _listener_failed = false
        _entries.clear()
        _scanning = true
        games_changed.emit()

func stop_scanning() -> void:
        _scanning = false
        _entries.clear()
        if _listener != null:
                _listener.close()
                _listener = null

func is_scanning() -> bool:
        return _scanning

## True when the discovery port could not be opened - the UI uses this to show
## its "type the code instead" fallback instead of an eternal "looking...".
func bind_failed() -> bool:
        return _listener_failed

## Feeds this phone's own addresses in, so a phone that is hosting and browsing
## at the same time never lists itself.
func set_own_ips(ips: PackedStringArray) -> void:
        _own_ips = ips

func _drain_packets(now: int) -> void:
        while _listener != null and _listener.get_available_packet_count() > 0:
                var sender_ip := _listener.get_packet_ip()
                var parsed := parse_beacon(_listener.get_packet())
                if parsed.is_empty():
                        continue
                note_beacon(sender_ip, int(parsed["port"]), now)

func _prune(now: int) -> void:
        var dropped: Array[String] = []
        for ip in _entries:
                if now - int(_entries[ip]["seen_ms"]) > ENTRY_TTL_MSEC:
                        dropped.append(ip)
        if dropped.is_empty():
                return
        for ip in dropped:
                _entries.erase(ip)
        games_changed.emit()

## The games visible right now (never stale ones). `now` defaults to real time;
## the self-test passes fixed timestamps so TTL logic is proven deterministically.
func games(now: int = -1) -> Array[Dictionary]:
        if now < 0:
                now = Time.get_ticks_msec()
        var out: Array[Dictionary] = []
        for ip in _entries:
                if now - int(_entries[ip]["seen_ms"]) <= ENTRY_TTL_MSEC:
                        out.append(_entries[ip])
        out.sort_custom(func(a, b): return str(a["ip"]) < str(b["ip"]))
        return out

## Record one heard beacon. Returns true only when the game is NEW to the list.
## Off-tree callable with a fixed clock: this is the heart the self-test drives.
func note_beacon(ip: String, port: int, now: int) -> bool:
        if ip.is_empty() or _own_ips.has(ip):
                return false
        if _entries.has(ip):
                var entry: Dictionary = _entries[ip]
                entry["port"] = port
                entry["seen_ms"] = now
                return false
        _entries[ip] = {"ip": ip, "port": port, "seen_ms": now}
        games_changed.emit()
        return true

# --- static core (pure - covered by the self-test) -------------------------------------

## The beacon wire format: "SPOTRUSH1|<port>" as UTF-8. A future protocol bump
## changes the magic digit, and every old phone silently ignores every new
## beacon (and vice versa) instead of choking on it.
static func encode_beacon(port: int) -> PackedByteArray:
        return (BEACON_MAGIC + str(clampi(port, 1, 65535))).to_utf8_buffer()

static func parse_beacon(data: PackedByteArray) -> Dictionary:
        if data.size() < BEACON_MAGIC.length() + 1 or data.size() > 32:
                return {}
        var text := data.get_string_from_utf8()
        if text.is_empty() or not text.begins_with(BEACON_MAGIC):
                return {}
        var port_text := text.substr(BEACON_MAGIC.length())
        if port_text.is_empty() or port_text.length() > 5:
                return {}
        for ch in port_text:
                if ch < "0" or ch > "9":
                        return {}
        var port := int(port_text)
        if port < 1 or port > 65535:
                return {}
        return {"port": port}

## Rank for one IPv4 address: lower sorts first. Home/hotspot Wi-Fi ranges are
## what a duel actually runs on, so 192.168.x wins; cellular (carrier-grade
## NAT), VPN tunnels and public addresses are the addresses that used to be
## handed to friends by mistake when _local_ips[0] picked the first thing the
## OS listed.
static func ip_rank(ip: String) -> int:
        var parts := ip.split(".", false)
        if parts.size() != 4:
                return 90
        var a := int(parts[0])
        var b := int(parts[1])
        if a == 127 or a == 0:
                return 95 # loopback / unspecified
        if a == 169 and b == 254:
                return 94 # link-local: not on any network yet
        if a == 100 and b >= 64 and b <= 127:
                return 80 # carrier-grade NAT (mobile data)
        if a == 198 and (b == 18 or b == 19):
                return 85 # benchmark range (some VPN tunnels)
        if a == 192 and b == 0:
                return 85 # protocol assignments, not a home LAN
        if a == 192 and b == 168:
                return 10 # home / hotspot Wi-Fi - the usual duel range
        if a == 10:
                return 20 # private
        if a == 172 and b >= 16 and b <= 31:
                return 30 # private
        return 70 # public / anything else

## The lobby's game code is the first address of this ordering. IPv6 and
## duplicates are dropped, ties break alphabetically so the order is stable.
static func rank_local_ips(ips: PackedStringArray) -> PackedStringArray:
        var seen := {}
        var list: Array = []
        for ip in ips:
                if not ip.is_empty() and not ip.contains(":") and not seen.has(ip):
                        seen[ip] = true
                        list.append(ip)
        list.sort_custom(func(x, y):
                var rx := ip_rank(x)
                var ry := ip_rank(y)
                if rx != ry:
                        return rx < ry
                return x < y)
        var out := PackedStringArray()
        for x in list:
                out.append(x)
        return out

# --- join codes (the QR payload) ---------------------------------------------------------

const JOIN_CODE_MAGIC := "SPOTRUSH:JOIN:"

## The text a host's QR square encodes (QrCode.gd draws it). The friend's
## camera app reads it; the JOIN tab's PASTE key parses it back out below.
static func encode_join_code(ip: String, port: int) -> String:
        return JOIN_CODE_MAGIC + ip + ":" + str(clampi(port, 1, 65535))

## Finds a join code anywhere in free-form clipboard text. Camera apps wrap
## the raw code in all kinds of chrome ("Scan result:", quotes, links), so
## the search is tolerant: the magic may sit anywhere, and everything after
## the address that isn't part of a code is ignored. Returns
## {"ip": String, "port": int}, or {} when no valid code is present.
static func parse_join_code(text: String) -> Dictionary:
        var idx := text.find(JOIN_CODE_MAGIC)
        if idx < 0:
                return {}
        var rest := text.substr(idx + JOIN_CODE_MAGIC.length())
        # Keep only the characters an "ip:port" code is made of.
        var token := ""
        for ch in rest:
                if (ch >= "0" and ch <= "9") or ch == "." or ch == ":":
                        token += ch
                else:
                        break
        var sep := token.rfind(":")
        if sep < 0:
                return {}
        var ip := token.substr(0, sep)
        var port_text := token.substr(sep + 1)
        if not is_valid_ipv4(ip):
                return {}
        if port_text.is_empty() or port_text.length() > 5:
                return {}
        for ch in port_text:
                if ch < "0" or ch > "9":
                        return {}
        var port := int(port_text)
        if port < 1 or port > 65535:
                return {}
        return {"ip": ip, "port": port}

## Shared strict IPv4 check (four 0..255 octets, digits only). Used by the
## typed game-code path, the clipboard parser and the self-test alike.
static func is_valid_ipv4(ip: String) -> bool:
        var parts := ip.split(".", false)
        if parts.size() != 4:
                return false
        for p in parts:
                if p.is_empty() or p.length() > 3:
                        return false
                for ch in p:
                        if ch < "0" or ch > "9":
                                return false
                if int(p) > 255:
                        return false
        return true
