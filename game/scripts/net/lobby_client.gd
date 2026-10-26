class_name LobbyClient
extends Node
## Player host (PLAN §4.9): finds the game server through the lobby (lobby/) and sets up the
## WebRTC connections. The lobby gives out a room code and relays WebRTC offers, answers and
## ICE candidates; game traffic then goes peer to peer (or through the TURN relay). Message
## format: lobby/src/rooms.ts.
##
## Server side (host): opens a room on a WebRTCMultiplayerPeer server and keeps the lobby
## socket open, pinging, for as long as the server runs, so friends can join any time. Each
## guest gets its own WebRTCPeerConnection under the peer id the lobby gave it, and the server
## makes the offer. Client side (join): makes a WebRTCMultiplayerPeer client for the id it was
## given, connects to the server (peer 1) and closes the lobby socket once connected.

## Client: the multiplayer peer to use, handed out as soon as it exists, so the multiplayer
## API polls it while it connects.
signal peer_created(peer: WebRTCMultiplayerPeer)
## Server: the room is open under this code.
signal room_opened(code: String)
## Something went wrong; reason is for the player. On the server the lobby is gone then, but
## players already connected stay.
signal failed(reason: String)

## The game's default lobby; --lobby=URL picks another.
const DEFAULT_URL := "wss://jotra.r4b2.de/ws"
## The lobby message format (lobby/src/server.ts PROTOCOL), apart from Net.PROTOCOL_VERSION
## so game-only changes need no lobby redeploy.
const PROTOCOL := 1
const SERVER_ID := 1
## Server: seconds between heartbeats; the lobby drops a room after 60 s without one.
const PING_INTERVAL := 20.0
## Seconds a guest's connection may take before it is given up.
const CONNECT_TIMEOUT := 30.0

var code := ""
## Client: the server's ICE candidates as "<type> <address>", for the debug overlay. Godot
## exposes no WebRTC stats, so this is what the server offered, not the pair that won: "host"
## candidates on the same network usually mean a direct LAN link, only "relay" goes through
## TURN.
var remote_candidates := PackedStringArray()
var _ws := WebSocketPeer.new()
## The first message, sent once the socket is open.
var _hello := {}
var _rtc: WebRTCMultiplayerPeer
var _ice: Array = []
var _hosting := false
## Server: guest id -> seconds left to connect, for connections still being set up.
var _pending := {}
var _ping_due := PING_INTERVAL
## Client: seconds left to connect, counting once the lobby gave us an id.
var _connect_left := CONNECT_TIMEOUT
var _done := false


## Server: opens a room for rtc, a WebRTCMultiplayerPeer in server mode. Hosting again after a
## failure opens a new room for the same peer, so connected players stay.
func host(url: String, rtc: WebRTCMultiplayerPeer) -> void:
	_hosting = true
	_rtc = rtc
	_open(url, {"type": "host", "protocol": PROTOCOL})


## Client: joins the room with this code.
func join(url: String, room_code: String) -> void:
	_open(url, {"type": "join", "code": room_code.strip_edges().to_upper(), "protocol": PROTOCOL})


func _open(url: String, hello: Dictionary) -> void:
	_hello = hello
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("Could not reach the lobby (%s)" % error_string(err))


func _process(delta: float) -> void:
	if _done:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello.is_empty():
		_send(_hello)
		_hello = {}
	while _ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			handle(msg)
	if _done:
		return
	if _hosting:
		_tick_server(delta)
	elif _rtc != null:
		_tick_client(delta)
	if not _done and state == WebSocketPeer.STATE_CLOSED:
		_fail("Lost the lobby" if code != "" else "Could not reach the lobby")


func _tick_server(delta: float) -> void:
	if code != "":
		_ping_due -= delta
		if _ping_due <= 0.0:
			_ping_due = PING_INTERVAL
			_send({"type": "ping"})
	for id: int in _pending.keys():
		var connection := _connection(id)
		var connection_state := (
			connection.get_connection_state() if connection else WebRTCPeerConnection.STATE_CLOSED
		)
		_pending[id] -= delta
		if connection_state == WebRTCPeerConnection.STATE_CONNECTED:
			_pending.erase(id)
		elif (
			_pending[id] <= 0.0
			or connection_state == WebRTCPeerConnection.STATE_FAILED
			or connection_state == WebRTCPeerConnection.STATE_CLOSED
		):
			print("lobby: guest %d never connected" % id)
			_drop(id)


func _tick_client(delta: float) -> void:
	var connection := _connection(SERVER_ID)
	var connection_state := connection.get_connection_state() if connection else -1
	if connection_state == WebRTCPeerConnection.STATE_CONNECTED:
		# The lobby has done its part.
		_ws.close()
		_done = true
		return
	_connect_left -= delta
	if connection_state == WebRTCPeerConnection.STATE_FAILED:
		_fail("No connection to the host, even through the relay")
	elif _connect_left <= 0.0:
		_fail("The host did not answer in time")


## One message from the lobby.
func handle(msg: Dictionary) -> void:
	match str(msg.get("type")):
		"hosted":
			code = str(msg.get("code"))
			_ice = msg.get("ice", [])
			room_opened.emit(code)
		"joined":
			code = str(msg.get("code"))
			_ice = msg.get("ice", [])
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_client(int(msg.get("id")))
			if _add_connection(SERVER_ID):
				peer_created.emit(_rtc)
		"guest":
			# The server makes the offer.
			var id := int(msg.get("id"))
			if _hosting and _add_connection(id):
				_pending[id] = CONNECT_TIMEOUT
				_connection(id).create_offer()
		"left":
			# Not a reason to drop the guest: one that got through closes its socket at once,
			# often before this side sees the connection up. One that gave up times out.
			pass
		"signal":
			_on_signal(int(msg.get("from", 0)), msg.get("data", {}))
		"error":
			var reason := str(msg.get("reason", "lobby error"))
			_fail(reason.left(1).to_upper() + reason.substr(1))


func _add_connection(id: int) -> bool:
	var connection := WebRTCPeerConnection.new()
	var err := connection.initialize({"iceServers": _ice})
	if err != OK:
		_fail("WebRTC is not available (%s)" % error_string(err))
		return false
	connection.session_description_created.connect(
		func(kind: String, sdp: String) -> void:
			connection.set_local_description(kind, sdp)
			_signal(id, {"kind": kind, "sdp": sdp})
	)
	connection.ice_candidate_created.connect(
		func(mid: String, index: int, sdp: String) -> void:
			_signal(id, {"kind": "candidate", "mid": mid, "index": index, "sdp": sdp})
	)
	_rtc.add_peer(connection, id)
	return true


func _connection(id: int) -> WebRTCPeerConnection:
	if not _rtc.has_peer(id):
		return null
	return _rtc.get_peer(id).get("connection")


func _drop(id: int) -> void:
	_pending.erase(id)
	if _rtc.has_peer(id):
		_rtc.remove_peer(id)


## Sends signal data to the peer with this id: the guest from the server, the server from a
## guest (the lobby knows).
func _signal(id: int, data: Dictionary) -> void:
	if _hosting:
		_send({"type": "signal", "to": id, "data": data})
	else:
		_send({"type": "signal", "data": data})


func _on_signal(from: int, data: Variant) -> void:
	if not data is Dictionary:
		return
	var connection := _connection(from if _hosting else SERVER_ID) if _rtc else null
	if connection == null:
		return
	match str(data.get("kind")):
		"offer", "answer":
			# Setting the server's offer makes the guest create its answer.
			connection.set_remote_description(str(data["kind"]), str(data.get("sdp")))
		"candidate":
			var sdp := str(data.get("sdp"))
			connection.add_ice_candidate(str(data.get("mid")), int(data.get("index", 0)), sdp)
			var summary := candidate_summary(sdp)
			if not _hosting and summary != "" and not summary in remote_candidates:
				remote_candidates.append(summary)


## "<type> <address>" from an ICE candidate line
## ("candidate:<foundation> <component> <proto> <priority> <address> <port> typ <type> ..."),
## or "" if it doesn't parse.
static func candidate_summary(sdp: String) -> String:
	var fields := sdp.split(" ", false)
	var typ := fields.find("typ")
	if typ < 6 or typ + 1 >= fields.size():
		return ""
	return "%s %s" % [fields[typ + 1], fields[4]]


func _send(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_ws.close()
	failed.emit(reason)
