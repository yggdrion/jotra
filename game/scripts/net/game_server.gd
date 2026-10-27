class_name GameServer
extends Node
## The game server: owns the SimWorld, ticks it at TICK_RATE and sends snapshots to every
## client at SNAPSHOT_RATE, along with the chunks entering each player's view. Runs headless, in
## its own process even for solo. The world pauses and is saved while nobody is online.
## Players reach it over ENet by address, or with a lobby URL over WebRTC by room code (player
## host, PLAN §4.9): then the server opens the room and keeps it open while it runs.

const TICK_RATE := 30
const SNAPSHOT_RATE := 20
## Frames per second, i.e. how often incoming packets are handled. The sim still ticks at
## TICK_RATE.
const POLL_RATE := 240
const MAX_PLAYERS := 10
## Solo and host: how long the spawning client has to join before we give up on it.
const SOLO_JOIN_TIMEOUT := 30.0
## Host: seconds before opening a new room after the lobby was lost.
const LOBBY_RETRY := 10.0
## Seconds between saves while players are online.
const SAVE_INTERVAL := 60.0

var net: Net
## Solo: the server lives only as long as the client that spawned it, so it exits when that
## player leaves or never joins. (OS.is_process_running only sees our own child processes, so
## the parent's pid can't be watched.)
var solo := false
## Host: the name of the player whose game started this server. Like solo, the server exits
## when that player leaves or never joins; friends come and go.
var owner_name := ""
## Opens a room in this lobby and takes players over WebRTC instead of ENet.
var lobby_url := ""
## Host: where the room code goes once the room is open ("!reason" if it can't be), for the
## spawning client to read.
var room_file := ""
## The lobby room code, "" without one.
var room := ""
## When this file appears the server saves and exits: Godot dies on SIGTERM without running any
## code, so the Docker entrypoint creates it on docker stop instead.
var stop_file := ""
var world: SimWorld

var _snapshot_due := 0.0
var _save_due := SAVE_INTERVAL
## peer id -> {coord: true} of the chunks that client has.
var _sent_chunks := {}
var _name_pattern := RegEx.create_from_string("^[A-Za-z0-9_-]{1,32}$")
var _solo_wait := SOLO_JOIN_TIMEOUT
var _owner_joined := false
var _rtc: WebRTCMultiplayerPeer
var _started := Time.get_unix_time_from_system()
# Metrics counters.
var _ticks := 0
var _tick_usec := 0
var _tick_max_usec := 0
## Ticks that took longer than one tick (1 / TICK_RATE).
var _slow_ticks := 0
var _sent_bytes := 0
var _received_bytes := 0
var _save_usec := 0


## Serves the world saved in world_path (created if missing), on port or, with lobby_url, in a
## lobby room. metrics_port > 0 also serves Prometheus metrics on that TCP port.
func start(port: int, world_path: String, metrics_port := 0) -> void:
	world = SimWorld.open(world_path)
	if world == null:
		get_tree().quit(1)
		return
	print("server: world %s, seed %d" % [world.store.dir, world.world_seed])
	Engine.physics_ticks_per_second = TICK_RATE
	# Headless has no vsync; without a cap the idle server spins a core. The cap sits well above
	# TICK_RATE because ENet is only polled once per frame: at 30 fps every packet waited up to
	# 33 ms, which showed as ~35 ms ping on localhost.
	Engine.max_fps = POLL_RATE
	var err := OK
	if lobby_url != "":
		_rtc = WebRTCMultiplayerPeer.new()
		err = _rtc.create_server()
		if err != OK:
			_room_failed("WebRTC is not available (%s)" % error_string(err))
			return
		multiplayer.multiplayer_peer = _rtc
		_open_room()
	else:
		var peer := ENetMultiplayerPeer.new()
		err = peer.create_server(port, MAX_PLAYERS)
		if err != OK:
			push_error("server: cannot listen on port %d (%s)" % [port, error_string(err)])
			get_tree().quit(1)
			return
		multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.moved.connect(func(id: int, position: Vector2) -> void: world.move_player(id, position))
	net.prop_remove_requested.connect(_on_prop_remove_requested)
	net.attacked.connect(
		func(id: int, heavy: bool, aim: Vector2, hits: PackedInt32Array) -> void:
			world.attack(id, heavy, aim, hits)
	)
	net.shot.connect(func(id: int, aim: Vector2, drawn: float) -> void: world.shoot(id, aim, drawn))
	net.dashed.connect(func(id: int) -> void: world.dash(id))
	net.item_moved.connect(
		func(id: int, from: int, to: int) -> void:
			_act(id, func(p: SimWorld.SimPlayer) -> void: p.inventory.move(from, to))
	)
	net.equip_requested.connect(
		func(id: int, index: int) -> void:
			_act(id, func(p: SimWorld.SimPlayer) -> void: p.equip(index))
	)
	net.unequip_requested.connect(
		func(id: int, kind: int, to: int) -> void:
			_act(id, func(p: SimWorld.SimPlayer) -> void: p.unequip(kind, to))
	)
	net.craft_requested.connect(func(id: int, recipe: StringName) -> void: world.craft(id, recipe))
	net.eat_requested.connect(func(id: int, index: int) -> void: world.eat(id, index))
	net.draught_requested.connect(func(id: int) -> void: world.use_draught(id))
	net.ability_requested.connect(func(id: int, aim: Vector2) -> void: world.use_ability(id, aim))
	net.interact_requested.connect(func(id: int) -> void: world.interact(id))
	net.build_requested.connect(
		func(id: int, tile: Vector2i, piece: StringName) -> void: world.build(id, tile, piece)
	)
	net.unbuild_requested.connect(func(id: int, tile: Vector2i) -> void: world.unbuild(id, tile))
	net.use_requested.connect(func(id: int, tile: Vector2i) -> void: world.use_piece(id, tile))
	net.chest_move_requested.connect(
		func(id: int, from_chest: bool, index: int) -> void: world.chest_move(id, from_chest, index)
	)
	net.pinged.connect(func(id: int, sent_ms: int) -> void: net.pong.rpc_id(id, sent_ms))
	if lobby_url == "":
		print("server: listening on %d" % port)
	if metrics_port > 0:
		var metrics := MetricsServer.new()
		metrics.source = metrics_text
		add_child(metrics)
		err = metrics.start(metrics_port)
		if err != OK:
			push_error(
				"server: cannot serve metrics on %d (%s)" % [metrics_port, error_string(err)]
			)
			get_tree().quit(1)
			return
		print("server: metrics on %d" % metrics_port)


## Connects to the lobby and opens a room for the WebRTC peer.
func _open_room() -> void:
	var lobby := LobbyClient.new()
	add_child(lobby)
	lobby.room_opened.connect(
		func(code: String) -> void:
			room = code
			print("server: room %s" % code)
			_write_room_file(code)
			for id: int in world.players:
				net.room.rpc_id(id, code)
	)
	lobby.failed.connect(
		func(reason: String) -> void:
			lobby.queue_free()
			if room == "":
				_room_failed(reason)
				return
			# Players already in stay connected; new ones need the new code.
			push_warning("server: lost the lobby (%s), new room in %d s" % [reason, LOBBY_RETRY])
			room = ""
			get_tree().create_timer(LOBBY_RETRY).timeout.connect(_open_room)
	)
	lobby.host(lobby_url, _rtc)


## The first room could not be opened: nobody can join, so give up.
func _room_failed(reason: String) -> void:
	push_error("server: cannot open a room: %s" % reason)
	_write_room_file("!" + reason)
	get_tree().quit(1)


func _write_room_file(text: String) -> void:
	if room_file == "":
		return
	var file := FileAccess.open(room_file, FileAccess.WRITE)
	if file:
		file.store_string(text)


## Runs action on a player's SimPlayer, if that peer has joined.
func _act(id: int, action: Callable) -> void:
	if world.players.has(id):
		action.call(world.players[id])


func _physics_process(delta: float) -> void:
	if world == null:  # start() failed and is quitting
		return
	if stop_file != "" and FileAccess.file_exists(stop_file):
		print("server: stop requested, saving")
		set_physics_process(false)
		get_tree().quit()  # _exit_tree saves
		return
	if (solo or owner_name != "") and not _owner_joined:
		_solo_wait -= delta
		if _solo_wait <= 0.0:
			print("server: the player who started it never joined, exiting")
			get_tree().quit(1)
			return
	if world.players.is_empty():
		return
	var started := Time.get_ticks_usec()
	world.tick(delta)
	var simmed := Time.get_ticks_usec()
	_send_events()
	_snapshot_due -= delta
	if _snapshot_due <= 0.0:
		_snapshot_due += 1.0 / SNAPSHOT_RATE
		for id: int in world.players:
			_send_chunks(id)
			var snap := world.snapshot_for(id)
			var at: Vector2 = world.players[id].position
			net.snapshot.rpc_id(
				id,
				at,
				Net.pack_entities(snap.players, at),
				Net.pack_entities(snap.enemies, at),
				Net.pack_entities(snap.drops, at),
				Net.pack_entities(snap.projectiles, at),
				Net.pack_facings(snap.enemies, snap.facings),
				snap.me,
				snap.time
			)
	_save_due -= delta
	if _save_due <= 0.0:
		_save_due = SAVE_INTERVAL
		_save()
	var took := Time.get_ticks_usec() - started
	_ticks += 1
	_tick_usec += took
	_tick_max_usec = maxi(_tick_max_usec, took)
	if took > 1e6 / TICK_RATE:
		_slow_ticks += 1
		print(
			(
				"server: slow tick %.1f ms (sim %.1f ms, %d chunks, %d enemies)"
				% [took / 1e3, (simmed - started) / 1e3, world.chunks.size(), world.enemies.size()]
			)
		)


## Sends the chunks that entered a player's view and forgets those it has left. The client
## keeps chunks a little longer than this, so it never misses one coming back into view.
func _send_chunks(id: int) -> void:
	var sent: Dictionary = _sent_chunks[id]
	var center := WorldGen.chunk_of(world.players[id].position)
	for coord: Vector2i in sent.keys():
		if not WorldGen.near(coord, center, SimWorld.VIEW_CHUNKS + 1):
			sent.erase(coord)
	for coord in world.interest(id):
		if not sent.has(coord):
			sent[coord] = true
			net.chunk.rpc_id(id, coord, world.removed_props(coord), world.chunk_pieces(coord))


## Forwards what happened in the sim, including attacks handled between ticks, to the clients
## that see it, and changed inventories and buffs to their owners.
func _send_events() -> void:
	for id: int in world.players:
		var inventory: Inventory = world.players[id].inventory
		if inventory.changed:
			inventory.changed = false
			net.inventory.rpc_id(id, inventory.to_data())
		var buffs: Buffs = world.players[id].buffs
		if buffs.changed:
			buffs.changed = false
			net.buffs.rpc_id(id, buffs.to_data())
	for event in world.events:
		match event[0]:
			"respawn":
				net.respawned.rpc_id(event[1], event[2])
			"hit":
				for id: int in world.players:
					if world.sees(id, event[4]):
						net.hit.rpc_id(id, event[1], event[2], roundi(event[3]), event[5])
			"windup":
				for id: int in world.players:
					if world.sees(id, event[2]):
						net.windup.rpc_id(id, event[1], event[3], event[4], event[5])
			"enemy":
				for id: int in world.players:
					if world.sees(id, event[3]):
						net.enemy_event.rpc_id(id, event[1], event[2])
			"perfect":
				net.perfect.rpc_id(event[1])
			"status":
				net.status.rpc_id(event[1], event[2], event[3])
			"effect":
				for id: int in world.players:
					if world.sees(id, event[2]):
						net.effect.rpc_id(id, event[1], event[2], event[3], event[4])
			"swing":
				# The swinging client has drawn its own already.
				for id: int in world.players:
					if id != event[1] and world.sees(id, event[4]):
						net.swing.rpc_id(id, event[1], event[2], event[3], event[5])
			"node":
				net.node_hit.rpc_id(event[1], event[2], event[3])
			"prop_removed":
				for id: int in _sent_chunks:
					if _sent_chunks[id].has(event[1]):
						net.prop_removed.rpc_id(id, event[1], event[2])
			"loot":
				net.looted.rpc_id(event[1], event[2], event[3])
			"full":
				net.inventory_full.rpc_id(event[1])
			"dungeon":
				# Also sent for one who left the game inside a run, who is gone by now.
				if world.players.has(event[1]):
					net.dungeon.rpc_id(event[1], event[2], event[3], event[4], event[5])
			"chest":
				net.chest_opened.rpc_id(event[1])
			"piece":
				var coord := Building.chunk_of_tile(event[1])
				var piece: Building.Piece = world.pieces.get(event[1])
				var data := Building.to_net(piece) if piece else []
				for id: int in _sent_chunks:
					if _sent_chunks[id].has(coord):
						net.piece.rpc_id(id, coord, Building.index_in_chunk(event[1]), data)
			"storage":
				if world.players.has(event[1]):
					net.storage.rpc_id(event[1], event[2])
	world.events.clear()


func _save() -> void:
	var started := Time.get_ticks_usec()
	world.save()
	_save_usec = Time.get_ticks_usec() - started


## Also covers every quit() and a clean shutdown.
func _exit_tree() -> void:
	if world:
		_save()


## Prometheus text format. Tick counters only count ticks that ran, not paused ones.
func metrics_text() -> String:
	# WebRTC has no traffic statistics in Godot; its byte counters stay at 0.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		_sent_bytes += enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		_received_bytes += enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var lines := PackedStringArray()
	for metric: Array in [
		[
			"build_info",
			"gauge",
			(
				'build="%s",protocol="%d",transport="%s"'
				% [GameClient.build_id(), Net.PROTOCOL_VERSION, "webrtc" if _rtc else "enet"]
			),
			1
		],
		["start_time_seconds", "gauge", "", _started],
		["players", "gauge", "", world.players.size()],
		["loaded_chunks", "gauge", "", world.chunks.size()],
		["enemies", "gauge", "", world.enemies.size()],
		["drops", "gauge", "", world.drops.size()],
		["dungeon_runs", "gauge", "", world.dungeons.size()],
		["save_seconds", "gauge", "", _save_usec / 1e6],
		["ticks_total", "counter", "", _ticks],
		["tick_seconds_total", "counter", "", _tick_usec / 1e6],
		["tick_seconds_max", "gauge", "", _tick_max_usec / 1e6],
		["slow_ticks_total", "counter", "", _slow_ticks],
		["sent_bytes_total", "counter", "", _sent_bytes],
		["received_bytes_total", "counter", "", _received_bytes],
	]:
		var key: String = "jotra_" + metric[0]
		var labels: String = "{%s}" % metric[2] if metric[2] != "" else ""
		lines.append("# TYPE %s %s" % [key, metric[1]])
		lines.append("%s%s %s" % [key, labels, metric[3]])
	return "\n".join(lines) + "\n"


func _on_hello(id: int, version: int, player_name: String) -> void:
	if version != Net.PROTOCOL_VERSION:
		net.reject.rpc_id(id, "protocol %d, server speaks %d" % [version, Net.PROTOCOL_VERSION])
		return
	# The name becomes a file name in the world's save.
	if _name_pattern.search(player_name) == null:
		net.reject.rpc_id(id, "invalid player name")
		return
	if world.is_online(player_name):
		net.reject.rpc_id(id, "%s is already online" % player_name)
		return
	# ENet caps its peers itself; a lobby room lets anyone with the code in.
	if world.players.size() >= MAX_PLAYERS:
		net.reject.rpc_id(id, "the world is full (%d players)" % MAX_PLAYERS)
		return
	var player := world.add_player(id, player_name)
	_sent_chunks[id] = {}
	_owner_joined = _owner_joined or solo or player_name == owner_name
	net.welcome.rpc_id(id, player.position, world.world_seed)
	if room != "":
		net.room.rpc_id(id, room)
	print("server: %s joined as %d (%d online)" % [player_name, id, world.players.size()])


func _on_prop_remove_requested(id: int, coord: Vector2i, prop_id: int) -> void:
	world.remove_prop(id, coord, prop_id)


func _on_peer_disconnected(id: int) -> void:
	if not world.players.has(id):
		return
	var was_owner: bool = owner_name != "" and world.players[id].name == owner_name
	world.remove_player(id)
	_sent_chunks.erase(id)
	print("server: player %d left (%d online)" % [id, world.players.size()])
	if world.players.is_empty():
		_save()
	if solo or was_owner:
		print("server: the player who started it left, exiting")
		get_tree().quit()
