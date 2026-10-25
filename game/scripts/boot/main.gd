extends Node
## Entry point. Picks the role from the user args (after `--`):
##   --server --port=N [--solo]               game server (headless); --solo: exits with its player
##   --connect=host:port [--bot --expect=N]   client joining a running server
##   (none)                                   solo: spawns a local --solo server, then joins it

const DEFAULT_PORT := 17777

@onready var _net: Net = $Net


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if args.has("server"):
		var server := GameServer.new()
		server.net = _net
		server.solo = args.has("solo")
		add_child(server)
		server.start(int(args.get("port", DEFAULT_PORT)))
		return
	var client := GameClient.new()
	client.net = _net
	client.bot = args.has("bot")
	client.bot_expect = int(args.get("expect", "0"))
	add_child(client)
	if args.has("connect"):
		var parts: PackedStringArray = args["connect"].rsplit(":", true, 1)
		client.join(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)
	else:
		client.join("127.0.0.1", _spawn_local_server())


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
	cmd.append_array(["--", "--server", "--solo", "--port=%d" % port])
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
