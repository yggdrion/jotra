class_name GameClient
extends Node2D
## The client: moves its own player at once (client-authoritative), sends the position to the
## server at SEND_RATE and draws everyone else INTERP_DELAY_MS in the past, blended from the
## server's snapshots. Builds the chunks the server streams from the world seed; E removes the
## nearest prop.
##
## Bot mode (run headless by the network test) walks in a circle instead of reading the
## keyboard and exits 0 once it has chunks, the server echoes its own position and bot_expect
## other players have been seen moving; 1 on timeout or a lost server, 2 if it never connects.

const SEND_RATE := 20
const INTERP_DELAY_MS := 100
## Snapshots older than this are dropped from the buffer.
const BUFFER_MS := 1000
## Solo: the spawned server needs a moment before it listens.
const CONNECT_ATTEMPTS := 40
const RETRY_MS := 250
const BOT_TIMEOUT_MS := 20000
## How far a remote player must move before a bot counts it as moving.
const BOT_MOVE_PX := 20.0
## How close the server's copy of a bot's position must be to its own.
const BOT_ECHO_PX := 40.0
## How long a bot that passed keeps walking before it leaves, so slower bots still see it move.
const BOT_LINGER := 2.0
## Where the name of a player who passes no --name is kept.
const NAME_FILE := "user://player.txt"
## Chunks are freed this far out, one further than the server forgets them, so a chunk the
## server sends again is never one the client already dropped.
const KEEP_CHUNKS := SimWorld.VIEW_CHUNKS + 2

var net: Net
var bot := false
var bot_expect := 0
## Empty: use the one in NAME_FILE.
var player_name := ""

var _address := ""
var _port := 0
var _attempts := 0
var _me: PlayerView
var _views := {}  # peer id -> PlayerView
var _snapshots: Array[Dictionary] = []
var _send_due := 0.0
var _bot_start := {}  # peer id -> first seen position
var _bot_echoed := false
var _bot_done := false
var _world_seed := 0
var _chunks := {}  # Vector2i -> ChunkView


func _ready() -> void:
	y_sort_enabled = true
	if player_name == "":
		player_name = _stored_name()
	multiplayer.connected_to_server.connect(
		func() -> void: net.hello.rpc_id(1, Net.PROTOCOL_VERSION, player_name)
	)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	net.welcomed.connect(_on_welcomed)
	net.rejected.connect(_on_rejected)
	net.snapshot_received.connect(_on_snapshot)
	net.chunk_received.connect(_on_chunk)
	net.prop_removed_received.connect(
		func(coord: Vector2i, id: int) -> void:
			if _chunks.has(coord):
				_chunks[coord].remove_prop(id)
	)
	var overlay := DebugOverlay.new()
	overlay.client = self
	add_child(overlay)


## The F3 overlay's connection readout.
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray(["Build " + build_id()])
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var server := peer.get_peer(1) if peer != null else null
	if _me == null or server == null:
		lines.append("Net  connecting to %s:%d (try %d)" % [_address, _port, _attempts])
		return lines
	lines.append(
		"Net  %s:%d  id %d  %s" % [_address, _port, multiplayer.get_unique_id(), player_name]
	)
	lines.append(
		(
			"Ping %d ms  snapshots %d/s"
			% [server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), _snapshots.size()]
		)
	)
	var players: Dictionary = _snapshots[-1].players if not _snapshots.is_empty() else {}
	lines.append("Players %d" % players.size())
	lines.append("Pos  %d, %d" % [_me.position.x, _me.position.y])
	var chunk := WorldGen.chunk_of(_me.position)
	lines.append(
		"World seed %d  chunk %d, %d  %d loaded" % [_world_seed, chunk.x, chunk.y, _chunks.size()]
	)
	return lines


## A random name made once per install, so a player comes back as themselves.
static func _stored_name() -> String:
	var stored := FileAccess.get_file_as_string(NAME_FILE).strip_edges()
	if stored != "":
		return stored
	var made := "%08x%08x" % [randi(), randi()]
	var file := FileAccess.open(NAME_FILE, FileAccess.WRITE)
	if file:
		file.store_string(made)
	return made


## The commit tools/export.py baked into this build, or "dev" when run from source.
static func build_id() -> String:
	var text := FileAccess.get_file_as_string("res://build_id.txt").strip_edges()
	return text if text != "" else "dev"


func join(address: String, port: int) -> void:
	_address = address
	_port = port
	_connect()


func _connect() -> void:
	_attempts += 1
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_address, _port)
	if err != OK:
		_on_connection_failed()
		return
	multiplayer.multiplayer_peer = peer


func _on_connection_failed() -> void:
	if _attempts >= CONNECT_ATTEMPTS:
		push_error("client: no server at %s:%d" % [_address, _port])
		get_tree().quit(2)
		return
	multiplayer.multiplayer_peer = null
	get_tree().create_timer(RETRY_MS / 1000.0).timeout.connect(_connect)


func _on_server_disconnected() -> void:
	print("client: server closed the connection")
	get_tree().quit(1 if bot else 0)


func _on_rejected(reason: String) -> void:
	push_error("client: server rejected us: %s" % reason)
	get_tree().quit(1)


func _on_welcomed(spawn: Vector2, world_seed: int) -> void:
	print("client: joined as %s (%d)" % [player_name, multiplayer.get_unique_id()])
	_world_seed = world_seed
	_me = PlayerView.new()
	_me.own = true
	_me.position = spawn
	_me.add_child(Camera2D.new())
	add_child(_me)


func _on_chunk(coord: Vector2i, removed: PackedInt32Array) -> void:
	if _chunks.has(coord):
		_chunks[coord].queue_free()
	_chunks[coord] = ChunkView.new(_world_seed, coord, removed)
	add_child(_chunks[coord])


func _drop_far_chunks() -> void:
	var center := WorldGen.chunk_of(_me.position)
	for coord: Vector2i in _chunks.keys():
		if not WorldGen.near(coord, center, KEEP_CHUNKS):
			_chunks[coord].queue_free()
			_chunks.erase(coord)


## E: asks the server to remove the nearest prop in reach.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _me == null or key == null or not key.pressed or key.echo or key.keycode != KEY_E:
		return
	var best := []
	var best_coord := Vector2i.ZERO
	for coord: Vector2i in _chunks:
		var found: Array = _chunks[coord].nearest_prop(_me.position, SimWorld.REACH)
		if not found.is_empty() and (best.is_empty() or found[1] < best[1]):
			best = found
			best_coord = coord
	if not best.is_empty():
		net.remove_prop.rpc_id(1, best_coord, best[0])
	get_viewport().set_input_as_handled()


func _on_snapshot(players: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	_snapshots.append({ms = now, players = players})
	while _snapshots[0].ms < now - BUFFER_MS:
		_snapshots.pop_front()


func _process(delta: float) -> void:
	if bot and not _bot_done and Time.get_ticks_msec() > BOT_TIMEOUT_MS:
		push_error("client: bot timed out (echoed %s, saw %s)" % [_bot_echoed, _bot_start])
		get_tree().quit(1)
		return
	if _me == null:
		return
	_me.position += _input_direction() * SimWorld.MAX_SPEED * delta
	_send_due -= delta
	if _send_due <= 0.0:
		_send_due += 1.0 / SEND_RATE
		net.move.rpc_id(1, _me.position)
		_drop_far_chunks()
	_show_remote_players(Interpolation.sample(_snapshots, Time.get_ticks_msec() - INTERP_DELAY_MS))


func _input_direction() -> Vector2:
	if bot:
		return Vector2.from_angle(Time.get_ticks_msec() / 500.0)
	var dir := Vector2(
		int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	)
	return dir.normalized()


func _show_remote_players(positions: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	for id: int in _views.keys():
		if not positions.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for id: int in positions:
		if id == me:
			continue
		if not _views.has(id):
			_views[id] = PlayerView.new()
			add_child(_views[id])
		_views[id].position = positions[id]
	if bot:
		_bot_check(positions)


func _bot_check(positions: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	var moving := 0
	for id: int in positions:
		if id == me:
			# The echo is INTERP_DELAY_MS old, so allow for that much walking.
			_bot_echoed = _bot_echoed or positions[id].distance_to(_me.position) < BOT_ECHO_PX
			continue
		if not _bot_start.has(id):
			_bot_start[id] = positions[id]
		if positions[id].distance_to(_bot_start[id]) > BOT_MOVE_PX:
			moving += 1
	if _bot_echoed and moving >= bot_expect and not _chunks.is_empty() and not _bot_done:
		_bot_done = true
		print("client: bot ok, %d chunks, saw %d moving player(s)" % [_chunks.size(), moving])
		await get_tree().create_timer(BOT_LINGER).timeout
		# Disconnect now, so the server sees us leave instead of timing us out.
		multiplayer.multiplayer_peer.close()
		get_tree().quit(0)
