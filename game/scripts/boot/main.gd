extends Node
## Entry point. Picks the role from the user args (after `--`):
##   --server --port=N [--solo]               game server (headless); --solo: exits with its player
##     [--lobby=URL [--room-file=PATH]]       instead of a port: open a room in this lobby, take
##                                            players over WebRTC, write the code to PATH
##     [--owner=NAME]                         exit when player NAME leaves or never joins (host)
##     [--world=DIR]                          world save dir, created if missing (DEFAULT_WORLD)
##     [--metrics-port=N]                     also serve Prometheus metrics over HTTP
##     [--stop-file=PATH]                     save and exit once PATH exists (Docker stop)
##   --connect=host:port                      client joining a running server over ENet
##   --join=CODE                              client joining a lobby room over WebRTC
##   --host                                   spawns a local server with a lobby room, joins it
##   --lobby=URL                              lobby for --join and --host (LobbyClient.DEFAULT_URL)
##   --bot [--expect=N]                       headless test client (solo unless joining or hosting)
##     [--duration=SECS]                      roam this long instead of leaving once it passed
##   --name=NAME                              client player name (default: a token kept in user://)
##   (none)                                   start menu: solo (a local --solo server), host, join
##   --windowed                               client starts in a window instead of fullscreen

const DEFAULT_PORT := 17777
const DEFAULT_WORLD := "user://worlds/default"
## The world a --bot or --host command line plays; the start menu picks from WorldList.
const SOLO_WORLD := "user://worlds/solo"
## Where a host server writes its room code for the client that spawned it.
const ROOM_FILE := "user://host_room.txt"
## Seconds a spawned host server gets to open its room.
const ROOM_TIMEOUT := 20.0

## Why the last game ended; the start menu shows it after the scene reloads.
static var _menu_message := ""
## The scene was reloaded for the start menu, so the command line's choice is spent.
static var _back := false

var _args := {}
var _client: GameClient
var _menu: StartMenu

@onready var _net: Net = $Net


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	_args = args
	if args.has("server"):
		var server := GameServer.new()
		server.net = _net
		server.solo = args.has("solo")
		server.owner_name = args.get("owner", "")
		server.lobby_url = args.get("lobby", "")
		server.room_file = args.get("room-file", "")
		server.stop_file = args.get("stop-file", "")
		add_child(server)
		server.start(
			int(args.get("port", DEFAULT_PORT)),
			args.get("world", DEFAULT_WORLD),
			int(args.get("metrics-port", "0"))
		)
		return
	if not _back:
		Settings.load_file()
	Settings.apply()
	# Godot's own --windowed loses to the project's fullscreen setting, hence our own flag.
	if args.has("windowed") or (not Settings.fullscreen and not _back):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size_changed.connect(_fit_viewport)
	_fit_viewport()
	if args.has("connect") and not _back:
		var parts: PackedStringArray = args["connect"].rsplit(":", true, 1)
		_new_client().join(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)
	elif args.has("join") and not _back:
		_join(args["join"])
	elif args.has("host") and not _back:
		_host()
	elif args.has("bot"):
		_solo()
	else:
		_show_menu()


func _show_menu() -> void:
	_menu = StartMenu.new()
	add_child(_menu)
	_menu.show_status(_menu_message)
	_menu.solo_chosen.connect(func(world: String) -> void: _solo(_world_dir(world)))
	_menu.host_chosen.connect(func(world: String) -> void: _host(_world_dir(world)))
	_menu.join_chosen.connect(_join)


func _new_client() -> GameClient:
	_client = GameClient.new()
	_client.net = _net
	_client.bot = _args.has("bot")
	_client.bot_expect = int(_args.get("expect", "0"))
	_client.bot_duration = float(_args.get("duration", "0"))
	_client.player_name = _args.get("name", "")
	add_child(_client)
	_client.joined.connect(
		func() -> void:
			if _menu:
				_menu.queue_free()
	)
	_client.left.connect(_back_to_menu)
	return _client


func _status(text: String) -> void:
	if _menu:
		_menu.show_status(text, true)


func _solo(world := SOLO_WORLD) -> void:
	_status("Starting the world...")
	var port := _free_port()
	_spawn_server(world, ["--solo", "--port=%d" % port])
	_new_client().join("127.0.0.1", port)


## Starts a local server that opens a lobby room, waits for its code and joins it like any
## friend would (PLAN §4.2: in player host everyone uses WebRTC, the host too).
func _host(world := SOLO_WORLD) -> void:
	_status("Opening a room...")
	var lobby := _lobby_url()
	var client := _new_client()
	var room_file := ProjectSettings.globalize_path(ROOM_FILE)
	DirAccess.remove_absolute(room_file)
	var pid := _spawn_server(
		world, ["--owner=" + client.player_name, "--lobby=" + lobby, "--room-file=" + room_file]
	)
	var waited := 0.0
	while waited < ROOM_TIMEOUT:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		var text := FileAccess.get_file_as_string(room_file).strip_edges()
		if text.begins_with("!"):
			_back_to_menu("Could not open a room: " + text.substr(1))
			return
		if text != "":
			_status("Room %s is open, joining..." % text)
			client.join_room(lobby, text)
			return
	OS.kill(pid)
	_back_to_menu("The local server did not open a room")


func _join(code: String) -> void:
	_status("Joining %s..." % code.to_upper())
	_new_client().join_room(_lobby_url(), code)


func _lobby_url() -> String:
	return _args.get("lobby", LobbyClient.DEFAULT_URL)


## Out of a game (or never got in): back to a fresh start menu that says why. A bot just exits.
func _back_to_menu(reason: String) -> void:
	if _args.has("bot"):
		get_tree().quit(2)
		return
	_menu_message = reason
	_back = true
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene.call_deferred()


## Zooms all 2D by the largest whole number at which the project's 640×360 still fits the
## window. The game draws at the window's real size (stretch mode disabled), so any size or
## aspect is filled edge to edge with crisp pixels and bigger windows see more world.
## Godot's integer stretch modes can't do this: they letterbox whatever a whole-number scale of
## the base aspect leaves (1264×680 showed a 668×360 picture), and after leaving fullscreen
## their output got resampled to the wrong size.
func _fit_viewport() -> void:
	var window := get_window()
	var size := Vector2(window.size)
	if size.x < 1 or size.y < 1:  # minimized
		return
	var base := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	window.content_scale_factor = maxf(1.0, floorf(minf(size.x / base.x, size.y / base.y)))


## F11 or Alt+Enter switches between borderless fullscreen and a window.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
		Settings.set_fullscreen(
			DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		Settings.save_file()
		get_viewport().set_input_as_handled()


## "--key=value" → {key: value}, "--flag" → {flag: ""}.
static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var args := {}
	for arg in user_args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


static func _world_dir(world: String) -> String:
	return WorldList.ROOT.path_join(world)


## Starts this same executable as a headless server on a world dir. Returns its pid.
func _spawn_server(world: String, server_args: PackedStringArray) -> int:
	var cmd: PackedStringArray = ["--headless"]
	# From source the executable is the Godot binary, which needs the project path.
	if not OS.has_feature("template"):
		cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
	cmd.append_array(["--", "--server", "--world=" + world])
	cmd.append_array(server_args)
	return OS.create_process(OS.get_executable_path(), cmd)


func _free_port() -> int:
	var udp := PacketPeerUDP.new()
	for i in 20:
		var port := randi_range(20000, 60000)
		if udp.bind(port) == OK:
			udp.close()
			return port
	return DEFAULT_PORT
