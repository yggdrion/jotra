class_name GameServer
extends Node
## The game server: owns the SimWorld, ticks it at TICK_RATE and sends snapshots to every
## client at SNAPSHOT_RATE. Runs headless, in its own process even for solo. The world pauses
## while nobody is online.

const TICK_RATE := 30
const SNAPSHOT_RATE := 20
## Frames per second, i.e. how often incoming packets are handled. The sim still ticks at
## TICK_RATE.
const POLL_RATE := 240
const MAX_PLAYERS := 10
## Solo: how long the spawning client has to join before we give up on it.
const SOLO_JOIN_TIMEOUT := 30.0

var net: Net
## Solo: the server lives only as long as the client that spawned it, so it exits when that
## player leaves or never joins. (OS.is_process_running only sees our own child processes, so
## the parent's pid can't be watched.)
var solo := false
var world := SimWorld.new()

var _snapshot_due := 0.0
var _solo_wait := SOLO_JOIN_TIMEOUT
var _started := Time.get_unix_time_from_system()
# Metrics counters.
var _ticks := 0
var _tick_usec := 0
var _sent_bytes := 0
var _received_bytes := 0


## metrics_port > 0 also serves Prometheus metrics on that TCP port.
func start(port: int, metrics_port := 0) -> void:
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


func _physics_process(delta: float) -> void:
	if world.players.is_empty():
		if solo:
			_solo_wait -= delta
			if _solo_wait <= 0.0:
				print("server: solo player never joined, exiting")
				get_tree().quit(1)
		return
	var started := Time.get_ticks_usec()
	world.tick(delta)
	_snapshot_due -= delta
	if _snapshot_due <= 0.0:
		_snapshot_due += 1.0 / SNAPSHOT_RATE
		net.snapshot.rpc(world.snapshot())
	_ticks += 1
	_tick_usec += Time.get_ticks_usec() - started


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


func _on_hello(id: int, version: int) -> void:
	if version != Net.PROTOCOL_VERSION:
		net.reject.rpc_id(id, "protocol %d, server speaks %d" % [version, Net.PROTOCOL_VERSION])
		return
	var player := world.add_player(id)
	net.welcome.rpc_id(id, player.position)
	print("server: player %d joined (%d online)" % [id, world.players.size()])


func _on_peer_disconnected(id: int) -> void:
	world.remove_player(id)
	print("server: player %d left (%d online)" % [id, world.players.size()])
	if solo:
		print("server: solo player left, exiting")
		get_tree().quit()
