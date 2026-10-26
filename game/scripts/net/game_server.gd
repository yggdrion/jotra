class_name GameServer
extends Node
## The game server: owns the SimWorld, ticks it at TICK_RATE and sends snapshots to every
## client at SNAPSHOT_RATE, along with the chunks entering each player's view. Runs headless, in
## its own process even for solo. The world pauses and is saved while nobody is online.

const TICK_RATE := 30
const SNAPSHOT_RATE := 20
## Frames per second, i.e. how often incoming packets are handled. The sim still ticks at
## TICK_RATE.
const POLL_RATE := 240
const MAX_PLAYERS := 10
## Solo: how long the spawning client has to join before we give up on it.
const SOLO_JOIN_TIMEOUT := 30.0
## Seconds between saves while players are online.
const SAVE_INTERVAL := 60.0

var net: Net
## Solo: the server lives only as long as the client that spawned it, so it exits when that
## player leaves or never joins. (OS.is_process_running only sees our own child processes, so
## the parent's pid can't be watched.)
var solo := false
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
var _started := Time.get_unix_time_from_system()
# Metrics counters.
var _ticks := 0
var _tick_usec := 0
var _sent_bytes := 0
var _received_bytes := 0
var _save_usec := 0


## Serves the world saved in world_path (created if missing). metrics_port > 0 also serves
## Prometheus metrics on that TCP port.
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
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
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
	net.craft_requested.connect(
		func(id: int, recipe: StringName) -> void:
			_act(id, func(p: SimWorld.SimPlayer) -> void: Crafting.craft(p, recipe))
	)
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
	if world.players.is_empty():
		if solo:
			_solo_wait -= delta
			if _solo_wait <= 0.0:
				print("server: solo player never joined, exiting")
				get_tree().quit(1)
		return
	var started := Time.get_ticks_usec()
	world.tick(delta)
	_send_events()
	_snapshot_due -= delta
	if _snapshot_due <= 0.0:
		_snapshot_due += 1.0 / SNAPSHOT_RATE
		for id: int in world.players:
			_send_chunks(id)
			var snap := world.snapshot_for(id)
			net.snapshot.rpc_id(id, snap.players, snap.enemies, snap.drops, snap.me)
	_save_due -= delta
	if _save_due <= 0.0:
		_save_due = SAVE_INTERVAL
		_save()
	_ticks += 1
	_tick_usec += Time.get_ticks_usec() - started


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
			net.chunk.rpc_id(id, coord, world.removed_props(coord))


## Forwards what happened in the sim, including attacks handled between ticks, to the clients
## that see it, and changed inventories to their owners.
func _send_events() -> void:
	for id: int in world.players:
		var inventory: Inventory = world.players[id].inventory
		if inventory.changed:
			inventory.changed = false
			net.inventory.rpc_id(id, inventory.to_data())
	for event in world.events:
		match event[0]:
			"respawn":
				net.respawned.rpc_id(event[1], event[2])
			"hit":
				for id: int in world.players:
					if world.sees(id, event[4]):
						net.hit.rpc_id(id, event[1], event[2], roundi(event[3]))
			"windup":
				for id: int in world.players:
					if world.sees(id, event[2]):
						net.windup.rpc_id(id, event[1], event[3])
			"swing":
				# The swinging client has drawn its own already.
				for id: int in world.players:
					if id != event[1] and world.sees(id, event[4]):
						net.swing.rpc_id(id, event[1], event[2], event[3], event[5])
			"loot":
				net.looted.rpc_id(event[1], event[2], event[3])
			"full":
				net.inventory_full.rpc_id(event[1])
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
	var host := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	_sent_bytes += host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	_received_bytes += host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var lines := PackedStringArray()
	for metric: Array in [
		[
			"build_info",
			"gauge",
			'build="%s",protocol="%d"' % [GameClient.build_id(), Net.PROTOCOL_VERSION],
			1
		],
		["start_time_seconds", "gauge", "", _started],
		["players", "gauge", "", world.players.size()],
		["loaded_chunks", "gauge", "", world.chunks.size()],
		["enemies", "gauge", "", world.enemies.size()],
		["drops", "gauge", "", world.drops.size()],
		["save_seconds", "gauge", "", _save_usec / 1e6],
		["ticks_total", "counter", "", _ticks],
		["tick_seconds_total", "counter", "", _tick_usec / 1e6],
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
	var player := world.add_player(id, player_name)
	_sent_chunks[id] = {}
	net.welcome.rpc_id(id, player.position, world.world_seed)
	print("server: %s joined as %d (%d online)" % [player_name, id, world.players.size()])


func _on_prop_remove_requested(id: int, coord: Vector2i, prop_id: int) -> void:
	if not world.remove_prop(id, coord, prop_id):
		return
	for peer: int in _sent_chunks:
		if _sent_chunks[peer].has(coord):
			net.prop_removed.rpc_id(peer, coord, prop_id)


func _on_peer_disconnected(id: int) -> void:
	if not world.players.has(id):
		return
	world.remove_player(id)
	_sent_chunks.erase(id)
	print("server: player %d left (%d online)" % [id, world.players.size()])
	if world.players.is_empty():
		_save()
	if solo:
		print("server: solo player left, exiting")
		get_tree().quit()
