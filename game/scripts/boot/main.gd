extends Node
## Entry point. Picks the role from the user args (after `--`):
##   --server --port=N [--solo]               game server (headless); --solo: exits with its player
##     [--world=DIR]                          world save dir, created if missing (DEFAULT_WORLD)
##     [--metrics-port=N]                     also serve Prometheus metrics over HTTP
##     [--stop-file=PATH]                     save and exit once PATH exists (Docker stop)
##   --connect=host:port [--bot --expect=N]   client joining a running server
##   --name=NAME                              client player name (default: a token kept in user://)
##   (none)                                   solo: spawns a local --solo server, then joins it
##   --windowed                               client starts in a window instead of fullscreen

const DEFAULT_PORT := 17777
const DEFAULT_WORLD := "user://worlds/default"
const SOLO_WORLD := "user://worlds/solo"

@onready var _net: Net = $Net


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if args.has("server"):
		var server := GameServer.new()
		server.net = _net
		server.solo = args.has("solo")
		server.stop_file = args.get("stop-file", "")
		add_child(server)
		server.start(
			int(args.get("port", DEFAULT_PORT)),
			args.get("world", DEFAULT_WORLD),
			int(args.get("metrics-port", "0"))
		)
		return
	# Godot's own --windowed loses to the project's fullscreen setting, hence our own flag.
	if args.has("windowed"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size_changed.connect(_fit_viewport)
	_fit_viewport()
	var client := GameClient.new()
	client.net = _net
	client.bot = args.has("bot")
	client.bot_expect = int(args.get("expect", "0"))
	client.player_name = args.get("name", "")
	add_child(client)
	if args.has("connect"):
		var parts: PackedStringArray = args["connect"].rsplit(":", true, 1)
		client.join(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)
	else:
		client.join("127.0.0.1", _spawn_local_server())


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
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_WINDOWED
				if fullscreen
				else DisplayServer.WINDOW_MODE_FULLSCREEN
			)
		)
		get_viewport().set_input_as_handled()


## "--key=value" → {key: value}, "--flag" → {flag: ""}.
static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var args := {}
	for arg in user_args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


## Starts this same executable as a headless solo server. Returns its port.
func _spawn_local_server() -> int:
	var port := _free_port()
	var cmd: PackedStringArray = ["--headless"]
	# From source the executable is the Godot binary, which needs the project path.
	if not OS.has_feature("template"):
		cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
	cmd.append_array(["--", "--server", "--solo", "--port=%d" % port, "--world=" + SOLO_WORLD])
	OS.create_process(OS.get_executable_path(), cmd)
	return port


func _free_port() -> int:
	var udp := PacketPeerUDP.new()
	for i in 20:
		var port := randi_range(20000, 60000)
		if udp.bind(port) == OK:
			udp.close()
			return port
	return DEFAULT_PORT
