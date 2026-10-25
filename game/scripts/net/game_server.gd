class_name GameServer
extends Node
## The game server: owns the SimWorld, ticks it at TICK_RATE and sends snapshots to every
## client at SNAPSHOT_RATE. Runs headless, in its own process even for solo.

const TICK_RATE := 30
const SNAPSHOT_RATE := 20
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


func start(port: int) -> void:
	Engine.physics_ticks_per_second = TICK_RATE
	# Headless has no vsync; without a cap the idle server spins a core.
	Engine.max_fps = TICK_RATE
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


func _physics_process(delta: float) -> void:
	world.tick(delta)
	_snapshot_due -= delta
	if _snapshot_due <= 0.0:
		_snapshot_due += 1.0 / SNAPSHOT_RATE
		net.snapshot.rpc(world.snapshot())
	if solo and world.players.is_empty():
		_solo_wait -= delta
		if _solo_wait <= 0.0:
			print("server: solo player never joined, exiting")
			get_tree().quit(1)


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
