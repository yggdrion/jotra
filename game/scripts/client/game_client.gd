# gdlint: disable=max-file-lines
class_name GameClient
extends Node2D
## The client: moves its own player at once (client-authoritative), sends the position to the
## server at SEND_RATE and draws everyone else INTERP_DELAY_MS in the past, blended from the
## server's snapshots, enemies the same way. Builds the chunks the server streams from the world
## seed; E fells or breaks the prop in reach, which is outlined and named in a prompt.
## Left/right mouse swing the equipped weapon light/heavy toward the mouse and report what they
## hit; Space dashes. Stamina and cooldowns are checked
## here first, the server has the last word. Tab or I opens the inventory and crafting screen;
## while it is open the mouse is for the screen, not for swinging. Items on the ground slide
## to a player walking near and are picked up (server side). F eats; the world darkens at night
## by the server's clock, which the HUD shows and announces. E at the barrow near the spawn
## goes into a dungeon run, whose rooms and corridors the player can't walk out of; E at its
## way out comes back. Buffs picked up inside are listed in the HUD and speed up walking and
## swinging here as on the server. B toggles build mode (BuildMode) in the overworld: clicks
## build and remove pieces, which block walking here as on the server; E opens doors and chests,
## and crafting needs a station piece nearby, E on a bed makes it our respawn point. Dying in
## the overworld leaves the inventory in a grave, which E takes back and an arrow at the screen's
## edge points to. A minimap shows the chunks we have been near, M opens a big map of them
## (MapView).
##
## Reaches the server over ENet by address (join) or over WebRTC by lobby room code
## (join_room). A player who can't get in, is rejected or loses the server gets `left` with the
## reason; the game then goes back to its start menu.
##
## Bot mode (run headless by the network test) walks in a circle instead of reading the
## keyboard and exits 0 once it has chunks and its inventory, has seen an enemy, the server
## echoes its own position and bot_expect other players have been seen moving; 1 on timeout
## or a lost server, 2 if it never connects. With bot_duration (the load test) it instead roams
## a wide circle on its own bearing, swinging as it goes, and exits 0 once bot_duration is up if
## it passed by then.

## In the world: the server welcomed us.
signal joined
## Not a bot: out of the game, for this reason.
signal left(reason: String)

const SEND_RATE := 20
const INTERP_DELAY_MS := 100
## Snapshots older than this are dropped from the buffer.
const BUFFER_MS := 1000
## Solo: the spawned server needs a moment before it listens.
const CONNECT_ATTEMPTS := 40
const RETRY_MS := 250
## Generous for a bot that spawns its own host server and connects through a lobby.
const BOT_TIMEOUT_MS := 30000
## How far a remote player must move before a bot counts it as moving.
const BOT_MOVE_PX := 20.0
## How close the server's copy of a bot's position must be to its own.
const BOT_ECHO_PX := 40.0
## How long a bot that passed keeps walking before it leaves, so slower bots still see it move.
## An enemy a frost bolt slows is tinted this.
const SLOWED := Color(0.55, 0.8, 1.2)
const BOT_LINGER := 2.0
## A roaming bot turns this slowly (seconds per radian), so it circles walk_speed * this out.
const BOT_ROAM_TURN := 60.0
## Seconds between a roaming bot's swings.
const BOT_SWING_EVERY := 2.0
## Where the name of a player who passes no --name is kept.
const NAME_FILE := "user://player.txt"
## Hunger below this share of the max prompts to eat.
const HUNGRY := 0.25
## The world's tint at full night; day is untinted.
const NIGHT_TINT := Color("3a4466")
## The tint inside a dungeon, whatever the time of day.
const DUNGEON_TINT := Color("8b9bb4")
## Chunks are freed this far out, one further than the server forgets them, so a chunk the
## server sends again is never one the client already dropped.
const KEEP_CHUNKS := SimWorld.VIEW_CHUNKS + 2
## Seconds between pings where the transport measures none itself (WebRTC).
const PING_INTERVAL := 1.0
## How far in from the screen's edge the arrow to our grave stays.
const GRAVE_MARKER_MARGIN := 16.0

var net: Net
var bot := false
var bot_expect := 0
## Seconds a bot stays in the game (roaming) before it leaves; 0: leave once it passed.
var bot_duration := 0.0
## Empty: use the one in NAME_FILE.
var player_name := ""

var _address := ""
var _port := 0
var _attempts := 0
## Over WebRTC: the lobby that set up the connection and the room joined.
var _lobby: LobbyClient
var _room := ""
var _ping_ms := -1
var _gone := false
var _ping_due := 0.0
var _me: PlayerView
var _views := {}  # peer id -> PlayerView
var _snapshots: Array[Dictionary] = []
var _send_due := 0.0
var _bot_start := {}  # peer id -> first seen position
var _bot_echoed := false
var _bot_saw_enemy := false
var _bot_inventory := false
var _bot_done := false
var _bot_bearing := randf() * TAU
var _bot_swing_at := 0.0
var _world_seed := 0
var _chunks := {}  # Vector2i -> ChunkView
var _enemy_views := {}  # enemy id -> EnemyView
var _drop_views := {}  # drop id -> DropView
var _projectile_views := {}  # projectile id -> ProjectileView
var _graves := {}  # grave id -> GraveView
## Where our unlooted graves lie, anywhere in the world.
var _own_graves := PackedVector2Array()
## Our grave in reach that E loots, null if none.
var _grave: GraveView
## [chunk coord, prop id] of the prop E acts on, [] if none is in reach.
var _target := []
## The tile of the door or chest E acts on instead, null if none.
var _use_tile: Variant = null
## {global tile: Building.Piece} of the chunks we have, from the server.
var _pieces := {}
var _build := BuildMode.new()
var _hud := Hud.new()
var _inventory_ui := InventoryUi.new()
var _craft_menu := CraftMenu.new()
var _map := MapView.new()
var _pause := PauseMenu.new()
var _character := CharacterUi.new()
## The server's copy of our inventory, for finding food to eat.
var _inventory := Inventory.new(Content.tuning.inventory_size)
var _tint := CanvasModulate.new()
## From the server's snapshots, spent ahead of them here.
var _health := Content.tuning.max_health
var _max_health := Content.tuning.max_health
var _stamina := Content.tuning.max_stamina
var _hunger := Content.tuning.max_hunger
## The world's time from the newest snapshot, run on locally in between; -1 before the first.
var _time := -1.0
## Our dungeon buffs, from the server.
var _buffs := Buffs.new()
## The equipped weapon, from the server's inventory; "" bare-handed.
var _weapon := &""
var _attack_ready_ms := 0
var _dash_ready_ms := 0
## Ticks (Time.get_ticks_msec) the cooked-food regeneration ends and the draught and the rune
## ability are ready again, as the server last said.
var _regen_end_ms := 0
var _draught_ready_ms := 0
var _ability_ready_ms := 0
## When the bow in hand started being drawn (msec), 0 if it is not.
var _draw_started_ms := 0
var _dash_left := 0.0
var _dash_dir := Vector2.ZERO
var _sfx := Sfx.new()
var _camera := Camera2D.new()
## Screenshake in px, falling off, and the slide of a hit that hurt us (px a second).
var _shake := 0.0
var _knock_vel := Vector2.ZERO
## The swing we last made, and when: a hit on an enemy soon after is ours, for hitstop and shake.
var _last_move: AttackDef
var _last_swing_ms := 0
var _slow_motion := SlowMotion.new()
## The rooms and corridors of the dungeon run we are in, empty in the overworld, and its way
## out.
var _area: Array[Rect2] = []
var _exit := Vector2.ZERO
var _chest := Vector2.ZERO
var _chest_opened := false
var _dungeon_view: DungeonView


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
	net.room_received.connect(
		func(code: String) -> void:
			_room = code
			_hud.show_room(code)
	)
	net.ponged.connect(func(sent: int) -> void: _ping_ms = Time.get_ticks_msec() - sent)
	net.rejected.connect(_on_rejected)
	net.snapshot_received.connect(_on_snapshot)
	net.chunk_received.connect(_on_chunk)
	net.piece_received.connect(_on_piece)
	net.grave_received.connect(_on_grave)
	net.own_graves_received.connect(
		func(positions: PackedVector2Array) -> void:
			if positions.size() > _own_graves.size():
				_hud.announce("Your things lie in your grave", Color("feae34"))
			_own_graves = positions
	)
	net.bed_set_received.connect(func() -> void: _hud.announce("Respawn set", Color("feae34")))
	net.storage_received.connect(_inventory_ui.show_storage)
	net.prop_removed_received.connect(
		func(coord: Vector2i, id: int) -> void:
			if _chunks.has(coord):
				_chunks[coord].remove_prop(id)
	)
	add_child(_sfx)
	net.hit_received.connect(_on_hit)
	net.node_hit_received.connect(
		func(at: Vector2, note: String) -> void: _float_text(note, Color("c0cbdc"), at)
	)
	net.windup_received.connect(
		func(id: int, seconds: float, radius: float, line: Vector2, arc: float) -> void:
			if _enemy_views.has(id):
				_enemy_views[id].windup(seconds, radius, line, arc)
				_sfx.play(&"windup")
	)
	net.enemy_event_received.connect(_on_enemy_event)
	net.perfect_received.connect(_on_perfect)
	net.status_received.connect(_on_status)
	net.effect_received.connect(_on_effect)
	net.respawned_received.connect(
		func(at: Vector2) -> void:
			_me.position = at
			_dash_left = 0.0
			_health = _max_health
	)
	net.swing_received.connect(
		func(id: int, heavy: bool, aim: Vector2, weapon: StringName) -> void:
			if _views.has(id):
				_views[id].swing(aim, Content.attack(weapon, heavy), weapon)
				_sfx.play(&"swing_heavy" if heavy else &"swing")
	)
	net.inventory_received.connect(
		func(data: Dictionary) -> void:
			_bot_inventory = true
			_weapon = StringName(data.get("weapon", ""))
			if _me:
				_me.weapon = _weapon
			_inventory.load_data(data)
			_inventory_ui.show_inventory(data)
	)
	net.looted_received.connect(_on_looted)
	net.dungeon_received.connect(_on_dungeon)
	net.buffs_received.connect(_on_buffs)
	net.chest_opened_received.connect(
		func() -> void:
			_chest_opened = true
			if _dungeon_view:
				_dungeon_view.open_chest()
	)
	net.inventory_full_received.connect(
		func() -> void:
			if _me:
				_float_text("Inventory full", Color("e43b44"), _me.position)
	)
	_inventory_ui.move_requested.connect(
		func(from: int, to: int) -> void: net.move_item.rpc_id(1, from, to)
	)
	_inventory_ui.equip_requested.connect(func(index: int) -> void: net.equip.rpc_id(1, index))
	_inventory_ui.unequip_requested.connect(
		func(kind: int, to: int) -> void: net.unequip.rpc_id(1, kind, to)
	)
	_inventory_ui.craft_requested.connect(
		func(recipe: StringName) -> void: net.craft.rpc_id(1, recipe)
	)
	_craft_menu.craft_requested.connect(
		func(recipe: StringName) -> void: net.craft.rpc_id(1, recipe)
	)
	_inventory_ui.eat_requested.connect(func(index: int) -> void: net.eat.rpc_id(1, index))
	_inventory_ui.drink_requested.connect(func() -> void: net.drink.rpc_id(1))
	_inventory_ui.chest_move_requested.connect(
		func(from_chest: bool, index: int) -> void: net.chest_move.rpc_id(1, from_chest, index)
	)
	add_child(_tint)
	add_child(_build)
	add_child(_hud)
	add_child(_map)
	add_child(_inventory_ui)
	add_child(_craft_menu)
	add_child(_character)
	add_child(_pause)
	_pause.menu_chosen.connect(func() -> void: _leave("", 0))
	_pause.quit_chosen.connect(get_tree().quit)
	var overlay := DebugOverlay.new()
	overlay.client = self
	add_child(overlay)


## The F3 overlay's connection readout.
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray(["Build " + build_id()])
	var where := "%s:%d" % [_address, _port]
	if _lobby:
		where = "room %s (WebRTC)" % _room
	if _me == null:
		lines.append("Net  connecting to %s%s" % [where, "" if _lobby else " (try %d)" % _attempts])
		return lines
	lines.append("Net  %s  id %d  %s" % [where, multiplayer.get_unique_id(), player_name])
	var ping := _ping_ms
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(1):
		ping = enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	lines.append("Ping %d ms  snapshots %d/s" % [ping, _snapshots.size()])
	if _lobby:
		lines.append("ICE  host offered %s" % ", ".join(_lobby.remote_candidates))
	var players: Dictionary = _snapshots[-1].players if not _snapshots.is_empty() else {}
	lines.append(
		(
			"Players %d  enemies %d  drops %d"
			% [players.size(), _enemy_views.size(), _drop_views.size()]
		)
	)
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


## Joins a lobby room by code, over WebRTC.
func join_room(lobby_url: String, code: String) -> void:
	_lobby = LobbyClient.new()
	_room = code.strip_edges().to_upper()
	add_child(_lobby)
	_lobby.peer_created.connect(
		func(peer: WebRTCMultiplayerPeer) -> void: multiplayer.multiplayer_peer = peer
	)
	_lobby.failed.connect(
		func(reason: String) -> void:
			push_error("client: %s" % reason)
			_leave(reason, 2)
	)
	_lobby.join(lobby_url, _room)


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
		_leave("No server at %s:%d" % [_address, _port], 2)
		return
	multiplayer.multiplayer_peer = null
	get_tree().create_timer(RETRY_MS / 1000.0).timeout.connect(_connect)


func _on_server_disconnected() -> void:
	print("client: server closed the connection")
	_leave("The server closed the connection", 1)


func _on_rejected(reason: String) -> void:
	push_error("client: server rejected us: %s" % reason)
	_leave("The server turned us away: %s" % reason, 1)


## Out of the game: a bot exits with code, a player hears why.
func _leave(reason: String, code: int) -> void:
	if bot:
		get_tree().quit(code)
		return
	if _gone:
		return
	_gone = true
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	left.emit(reason)


func _on_welcomed(spawn: Vector2, world_seed: int) -> void:
	print("client: joined as %s (%d)" % [player_name, multiplayer.get_unique_id()])
	joined.emit()
	_world_seed = world_seed
	_map.load_world(world_seed, player_name)
	_me = PlayerView.new()
	_me.own = true
	_me.position = spawn
	_me.holding = true
	_me.weapon = _weapon
	_me.add_child(_camera)
	add_child(_me)
	var entrance := PortalView.new()
	entrance.label = "Barrow"
	entrance.position = Content.tuning.dungeon_entrance
	add_child(entrance)


## area empty: back in the overworld, else in a run of these rooms and corridors with its way
## out.
func _on_dungeon(area: Array, exit: Vector2, chest: Vector2, at: Vector2) -> void:
	_area.assign(area)
	_build.visible = false
	_exit = exit
	_chest = chest
	_chest_opened = false
	_me.position = at
	_dash_left = 0.0
	_map.visible = _area.is_empty()
	if _dungeon_view:
		_dungeon_view.queue_free()
		_dungeon_view = null
	if _area.is_empty():
		if _health <= 0:
			_hud.announce("What you found in the barrow is lost", Color("e43b44"))
		else:
			_hud.announce("Back in the open", Color("feae34"))
		return
	_dungeon_view = DungeonView.new()
	_dungeon_view.area = _area
	_dungeon_view.exit = exit
	_dungeon_view.chest = chest
	add_child(_dungeon_view)
	_hud.announce("Die in here and you lose what you found", Color("e43b44"))


## Floats the buffs just gained, announces synergies just completed and lists them all.
func _on_buffs(data: Dictionary) -> void:
	var had := _buffs.stacks.duplicate()
	var had_synergies := _buffs.synergies()
	_buffs.load_data(data)
	var lines := []
	for id: StringName in Content.buff_ids:
		if not _buffs.stacks.has(id):
			continue
		var def: BuffDef = Content.buffs[id]
		var color := ItemDef.RARITY_COLORS[def.rarity]
		var count: int = _buffs.stacks[id]
		lines.append(["%s x%d  %s" % [def.display_name, count, def.description], color])
		if count > had.get(id, 0) and _me:
			_float_text("+" + def.display_name, color, _me.position)
	for id in _buffs.synergies():
		var synergy: SynergyDef = Content.synergies[id]
		lines.append(["* %s  %s" % [synergy.display_name, synergy.description], Color("feae34")])
		if id not in had_synergies:
			_hud.announce("Synergy: %s" % synergy.display_name, Color("feae34"))
	_hud.show_buffs(lines)


## Our own grave, the entrance, or in a run its end chest or way out, when we stand at one:
## [what interact does there, "" if nothing, and whether interact may be sent]. A chest an
## enemy is near says so but may not, as the server would refuse it.
func _interaction() -> Array:
	var reach := Content.tuning.portal_reach
	if _grave:
		return ["Take back your things", true]
	if _area.is_empty():
		var near := _me.position.distance_to(Content.tuning.dungeon_entrance) <= reach
		return ["Enter the barrow", true] if near else ["", false]
	if _me.position.distance_to(_chest) <= reach and not _chest_opened:
		var enemies: Array[Vector2] = []
		for view: EnemyView in _enemy_views.values():
			enemies.append(view.position)
		if Dungeon.locked(_chest, enemies):
			return ["Clear the chamber to open the chest", false]
		return ["Open the chest", true]
	if _me.position.distance_to(_exit) <= reach:
		return ["Leave with your loot", true]
	return ["", false]


## pieces: [index in chunk, Building.to_net...] each; graves: [id, x, y, owner name] each.
func _on_chunk(coord: Vector2i, removed: PackedInt32Array, pieces: Array, graves: Array) -> void:
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_forget_pieces(coord)
	_chunks[coord] = ChunkView.new(_world_seed, coord, removed)
	_map.explore(coord)
	add_child(_chunks[coord])
	for entry: Array in pieces:
		_on_piece(coord, entry[0], entry.slice(1))
	for entry: Array in graves:
		_on_grave(coord, entry[0], entry.slice(1))


## data: [x, y, owner name], [] when the grave is gone.
func _on_grave(coord: Vector2i, id: int, data: Array) -> void:
	if not _chunks.has(coord):
		return
	if data.is_empty():
		if _graves.has(id):
			_graves[id].queue_free()
			_graves.erase(id)
		return
	if not _graves.has(id):
		var view := GraveView.new()
		view.coord = coord
		view.own = data[2] == player_name
		_graves[id] = view
		add_child(view)
	_graves[id].position = Vector2(data[0], data[1])


## data: Building.to_net, [] when the piece is gone.
func _on_piece(coord: Vector2i, index: int, data: Array) -> void:
	if not _chunks.has(coord):
		return
	var tile := Building.tile_at(coord, index)
	var piece: Building.Piece = null if data.is_empty() else Building.from_net(data)
	if piece:
		_pieces[tile] = piece
	else:
		_pieces.erase(tile)
	_chunks[coord].set_piece(index, piece)
	_refresh_joins(tile)


## Redraws the piece on a tile and its four neighbours by what stands next to each (walls join).
func _refresh_joins(tile: Vector2i) -> void:
	var tiles: Array[Vector2i] = [tile]
	for dir in Building.JOIN_DIRS:
		tiles.append(tile + dir)
	for at in tiles:
		var there: Building.Piece = _pieces.get(at)
		var view: ChunkView = _chunks.get(Building.chunk_of_tile(at))
		if there and view:
			var mask := Building.join_mask(_pieces, at, there.id)
			view.set_join_mask(Building.index_in_chunk(at), mask)


## Also the graves lying in the chunk.
func _forget_pieces(coord: Vector2i) -> void:
	for tile: Vector2i in _pieces.keys():
		if Building.chunk_of_tile(tile) == coord:
			_pieces.erase(tile)
	for id: int in _graves.keys():
		if _graves[id].coord == coord:
			_graves[id].queue_free()
			_graves.erase(id)


func _drop_far_chunks() -> void:
	var center := WorldGen.chunk_of(_me.position)
	for coord: Vector2i in _chunks.keys():
		if not WorldGen.near(coord, center, KEEP_CHUNKS):
			_chunks[coord].queue_free()
			_chunks.erase(coord)
			_forget_pieces(coord)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var escape := key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	if _me == null or _pause.visible or _health <= 0:
		# Dead or paused, only Escape counts.
		if escape and _me != null:
			_pause.escape()
			get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouseButton
	if mouse and (_inventory_ui.visible or _craft_menu.visible):
		return
	if mouse and mouse.pressed and _build.visible:
		_build_click(mouse.button_index)
		get_viewport().set_input_as_handled()
		return
	if mouse and mouse.pressed and mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var bow := Content.item(_weapon)
		if mouse.button_index == MOUSE_BUTTON_LEFT and bow and bow.ammo != &"":
			_begin_draw(bow)
		else:
			_attack(mouse.button_index == MOUSE_BUTTON_RIGHT)
		get_viewport().set_input_as_handled()
		return
	if key == null or not key.pressed or key.echo:
		return
	var digit := key.keycode - KEY_1
	if event.is_action_pressed(&"inventory"):
		_inventory_ui.toggle()
	elif event.is_action_pressed(&"character"):
		_character.toggle(_inventory, _buffs, player_name, _regen_text())
	elif escape and _inventory_ui.visible:
		_inventory_ui.toggle()
	elif (escape or event.is_action_pressed(&"interact")) and _craft_menu.visible:
		_craft_menu.toggle()
	elif escape and _character.visible:
		_character.visible = false
	elif event.is_action_pressed(&"build") and _area.is_empty():
		_build.visible = not _build.visible
	elif escape and _build.visible:
		_build.visible = false
	elif event.is_action_pressed(&"map") and _area.is_empty():
		_map.toggle_big()
	elif escape and _map.is_big():
		_map.toggle_big()
	elif escape:
		_pause.escape()
	elif _build.visible and digit >= 0 and digit < BuildMenu.HOTBAR:
		_build.select_slot(digit)
	elif event.is_action_pressed(&"interact"):
		if _use_tile != null:
			net.use_piece.rpc_id(1, _use_tile)
		elif not _target.is_empty():
			net.remove_prop.rpc_id(1, _target[0], _target[1])
		elif _interaction()[1]:
			net.interact.rpc_id(1)
		elif not _inventory_ui.stations.is_empty():
			_craft_menu.toggle()
	elif event.is_action_pressed(&"dash"):
		_dash()
	elif event.is_action_pressed(&"eat"):
		net.eat.rpc_id(1, -1)
	elif event.is_action_pressed(&"heal"):
		net.drink.rpc_id(1)
	elif event.is_action_pressed(&"ability"):
		net.ability.rpc_id(1, _aim())
	else:
		return
	get_viewport().set_input_as_handled()


## In build mode: left builds (or repairs) the chosen piece where the ghost is green, right
## takes down the piece under the mouse, the wheel picks another piece.
func _build_click(button: MouseButton) -> void:
	match button:
		MOUSE_BUTTON_LEFT:
			if _build.status in [Building.Status.OK, Building.Status.REPAIR]:
				net.build.rpc_id(1, _build.tile, _build.piece_id())
		MOUSE_BUTTON_RIGHT:
			if _pieces.has(_build.tile):
				net.unbuild.rpc_id(1, _build.tile)
		MOUSE_BUTTON_WHEEL_UP:
			_build.select(_build.selected - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_build.select(_build.selected + 1)


## Moves our player by step unless a piece blocks it, sliding along the piece if only one axis
## is blocked.
func _walk(step: Vector2) -> void:
	var from := _me.position
	for to: Vector2 in [from + step, from + Vector2(step.x, 0), from + Vector2(0, step.y)]:
		if Building.can_walk(_pieces, from, to):
			_me.position = to
			return


## Swings at once and tells the server which enemies, as drawn here, the swing hit.
func _attack(heavy: bool) -> void:
	var move := Content.attack(_weapon, heavy)
	var now := Time.get_ticks_msec()
	if now < _attack_ready_ms or _stamina < move.cost:
		return
	_attack_ready_ms = now + int(Combat.cooldown(move, _buffs) * 1000)
	_stamina -= move.cost
	var aim := _aim()
	var hits := PackedInt32Array()
	for id: int in _enemy_views:
		if Combat.in_arc(_me.position, aim, _enemy_views[id].position, move.reach, move.arc):
			hits.append(id)
	_me.swing(aim, move)
	_last_move = move
	_last_swing_ms = now
	_sfx.play(&"swing_heavy" if heavy else &"swing")
	net.attack.rpc_id(1, heavy, aim, hits)


## Starts drawing the bow in hand, if it is ready, there is an arrow and stamina for the shot.
func _begin_draw(bow: ItemDef) -> void:
	if Time.get_ticks_msec() < _attack_ready_ms or _stamina < bow.draw_cost:
		return
	if _inventory.count_of(bow.ammo) < 1:
		_float_text("No arrows", Color("e43b44"), _me.position)
		return
	_draw_started_ms = Time.get_ticks_msec()


## The share (0..1) of the bow's draw time the button has been held, 0 when not drawing.
func _drawn(bow: ItemDef) -> float:
	if _draw_started_ms == 0:
		return 0.0
	return clampf((Time.get_ticks_msec() - _draw_started_ms) / 1000.0 / bow.draw_time, 0.0, 1.0)


## While the bow is drawn: shows the draw, and shoots when the button is let go (anywhere, also
## over the UI). It is dropped without a shot when the bow is put away, the inventory opens or
## the draw was too short (any menu opening counts).
func _tick_draw(bow: ItemDef) -> void:
	var drawn := _drawn(bow)
	_me.draw_share = drawn
	if _inventory_ui.visible or _craft_menu.visible or _pause.visible or _health <= 0:
		_draw_started_ms = 0
		_me.draw_share = 0.0
		return
	if _draw_started_ms == 0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_draw_started_ms = 0
	_me.draw_share = 0.0
	if drawn >= bow.min_draw:
		_stamina -= bow.draw_cost
		net.shoot.rpc_id(1, _aim(), drawn)


## Dashes in the walking direction, or toward the mouse when standing still.
func _dash() -> void:
	var now := Time.get_ticks_msec()
	var t := Content.tuning
	if now < _dash_ready_ms or _stamina < t.dash_cost:
		return
	_dash_ready_ms = now + int(t.dash_cooldown * 1000)
	_stamina -= t.dash_cost
	var dir := _input_direction()
	_dash_dir = dir if dir != Vector2.ZERO else _aim().normalized()
	_dash_left = t.dash_time
	_sfx.play(&"dash")
	net.dash.rpc_id(1)


func _aim() -> Vector2:
	if bot:
		return _input_direction()
	var aim := get_global_mouse_position() - _me.position
	return aim if aim != Vector2.ZERO else Vector2.RIGHT


## Picks our grave, or else the prop, door, chest or bed in reach that E acts on, outlines it,
## and prompts for it or, failing that, for a station nearby; in build mode the prompt is the
## build mode's.
func _update_target() -> void:
	var grave := _own_grave_near()
	if grave != _grave:
		if _grave:
			_grave.highlighted = false
		if grave:
			grave.highlighted = true
		_grave = grave
	var best := []
	var best_distance := INF if grave == null else -1.0
	var center := WorldGen.chunk_of(_me.position)
	for coord in WorldGen.around(center, 1):
		if not _chunks.has(coord) or grave:
			continue
		var found: Array = _chunks[coord].nearest_prop(_me.position, SimWorld.REACH)
		if not found.is_empty() and found[1] < best_distance:
			best = [coord, found[0]]
			best_distance = found[1]
	var usable := Building.nearest_usable(_pieces, _me.position, SimWorld.REACH)
	var use_tile: Variant = null
	if not usable.is_empty() and usable[1] < best_distance:
		use_tile = usable[0]
		best = []
	if use_tile != _use_tile:
		for tile: Variant in [_use_tile, use_tile]:
			var chunk: ChunkView = (
				_chunks.get(Building.chunk_of_tile(tile)) if tile != null else null
			)
			if chunk:
				chunk.highlight_piece(Building.index_in_chunk(tile), tile == use_tile)
		_use_tile = use_tile
	if best != _target:
		if not _target.is_empty() and _chunks.has(_target[0]):
			_chunks[_target[0]].highlight(_target[1], false)
		_target = best
		if not best.is_empty():
			_chunks[best[0]].highlight(best[1], true)
	var prompt := ""
	var use := KeyHint.tag(&"interact")
	var food := _inventory.first_food()
	var hungry := _hunger < Content.tuning.max_hunger * HUNGRY
	if _health <= 0:
		prompt = ""
	elif hungry and food != -1:
		var meal := Content.item(_inventory.slots[food].item).display_name
		var hunger := "Starving" if _hunger <= 0 else "Hungry"
		prompt = "%s: %s Eat %s" % [hunger, KeyHint.tag(&"eat"), meal.to_lower()]
	elif _hunger <= 0:
		prompt = "Starving: fell trees for berries"
	elif _build.visible:
		prompt = _build.prompt(_inventory)
	elif _use_tile != null:
		var piece: Building.Piece = _pieces[_use_tile]
		var verb := "Open"
		if piece.def().door and piece.open:
			verb = "Close"
		prompt = "%s %s %s" % [use, verb, piece.def().display_name.to_lower()]
		if piece.def().bed:
			prompt = "%s Respawn at this %s" % [use, piece.def().display_name.to_lower()]
	elif not _target.is_empty():
		var stick: bool = _chunks[_target[0]].kind_of(_target[1]) == WorldGen.Prop.STICK
		prompt = "%s Pick up %s" % [use, "stick" if stick else "pebble"]
	elif _interaction()[0] != "":
		var here: Array = _interaction()
		prompt = "%s %s" % [use, here[0]] if here[1] else here[0]
	elif not _inventory_ui.stations.is_empty():
		var station: StringName = _inventory_ui.stations.keys()[0]
		prompt = "%s Craft at the %s" % [use, Content.piece(station).display_name.to_lower()]
	_hud.show_prompt(prompt)


## Our grave within reach, null if none (or inside a run).
func _own_grave_near() -> GraveView:
	var best: GraveView = null
	if not _area.is_empty() or _health <= 0:
		return null
	for view: GraveView in _graves.values():
		var distance := view.position.distance_to(_me.position)
		if view.own and distance <= SimWorld.REACH:
			if best == null or distance < best.position.distance_to(_me.position):
				best = view
	return best


## Points the HUD's arrow at our closest grave while it is off screen, from the screen's edge.
func _update_grave_marker() -> void:
	var hidden := Vector2(NAN, 0)
	if _own_graves.is_empty() or not _area.is_empty():
		_hud.show_grave_marker(hidden, Vector2.RIGHT)
		return
	var closest := _own_graves[0]
	for at in _own_graves:
		if at.distance_to(_me.position) < closest.distance_to(_me.position):
			closest = at
	var screen := get_viewport().get_visible_rect()
	var on_screen := get_viewport().get_canvas_transform() * closest
	var inner := screen.grow(-GRAVE_MARKER_MARGIN)
	if inner.has_point(on_screen):
		_hud.show_grave_marker(hidden, Vector2.RIGHT)
		return
	var center := screen.get_center()
	var dir := (on_screen - center).normalized()
	var half := inner.size / 2
	var reach := minf(
		half.x / absf(dir.x) if dir.x != 0 else INF, half.y / absf(dir.y) if dir.y != 0 else INF
	)
	_hud.show_grave_marker(center + dir * reach, dir)


func _on_snapshot(
	players: Dictionary,
	enemies: Dictionary,
	drops: Dictionary,
	projectiles: Dictionary,
	facings: Dictionary,
	me: Vector4,
	time: float
) -> void:
	var now := Time.get_ticks_msec()
	var turned := {}
	for id: int in facings:
		turned[id] = Vector2.from_angle(facings[id])
	_snapshots.append({ms = now, players = players, enemies = enemies, facings = turned})
	while _snapshots[0].ms < now - BUFFER_MS:
		_snapshots.pop_front()
	_health = me.x
	_stamina = me.y
	_max_health = me.z
	_hunger = me.w
	var t := Content.tuning
	_hud.show_stats(_health / _max_health, _stamina / t.max_stamina, _hunger / t.max_hunger)
	_hud.show_status(_status_text())
	if _time >= 0 and Survival.is_night(_time) != Survival.is_night(time):
		if Survival.is_night(time):
			_hud.announce("Night falls: enemies grow stronger", Color("8b9bb4"))
		else:
			_hud.announce("Day %d dawns" % Survival.day_number(time), Color("feae34"))
	_time = time
	if _me:
		_me.health = _health / _max_health
	_show_drops(drops)
	_show_projectiles(projectiles)


## projectiles: {id: Vector3(x, y, flight angle)}.
func _show_projectiles(projectiles: Dictionary) -> void:
	for id: int in _projectile_views.keys():
		if not projectiles.has(id):
			_projectile_views[id].queue_free()
			_projectile_views.erase(id)
	for id: int in projectiles:
		var p: Vector3 = projectiles[id]
		if not _projectile_views.has(id):
			_projectile_views[id] = ProjectileView.new()
			add_child(_projectile_views[id])
		_projectile_views[id].update(Vector2(p.x, p.y), p.z)


## drops: {id: Vector3(x, y, item index, or -1 - buff index for an orb)}. Most lie still;
## those sliding to a player glide toward their newest position instead of being interpolated.
func _show_drops(drops: Dictionary) -> void:
	for id: int in _drop_views.keys():
		if not drops.has(id):
			_drop_views[id].queue_free()
			_drop_views.erase(id)
	for id: int in drops:
		var drop: Vector3 = drops[id]
		var at := Vector2(drop.x, drop.y)
		if _drop_views.has(id):
			_drop_views[id].target = at
			continue
		var view := DropView.new()
		if drop.z < 0:
			view.buff = Content.buffs[Content.buff_ids[-1 - int(drop.z)]]
		else:
			view.item = Content.item(Content.item_ids[int(drop.z)])
		view.position = at
		view.target = at
		add_child(view)
		_drop_views[id] = view


func _on_looted(item: StringName, count: int) -> void:
	var def := Content.item(item)
	if _me and def:
		_float_text(
			"+%d %s" % [count, def.display_name], ItemDef.RARITY_COLORS[def.rarity], _me.position
		)


func _on_hit(enemy: bool, id: int, amount: int, push: Vector2) -> void:
	var view: PlayerView
	if enemy:
		view = _enemy_views.get(id)
	else:
		view = _me if id == multiplayer.get_unique_id() else _views.get(id)
	if view == null:
		return
	view.flash()
	_float_text(str(amount), Color.WHITE if enemy else Color("e43b44"), view.position)
	var heavy := push.length() > 15.0 or amount > 30
	add_child(HitSpark.burst(view.position + Vector2(0, -8), push, 8 if heavy else 4))
	if enemy:
		(view as EnemyView).recoil(push)
		_sfx.play(&"hit_heavy" if heavy else &"hit")
		var mine := _last_move != null and Time.get_ticks_msec() - _last_swing_ms < 300
		if mine:
			_shake = maxf(_shake, _last_move.shake)
			_hitstop(_last_move.hitstop)
	elif view == _me:
		view.hurt()
		_hud.hurt()
		_sfx.play(&"hurt")
		_shake = maxf(_shake, Content.tuning.hurt_shake)
		_knock_vel = push * Content.tuning.knock_decay


func _on_enemy_event(id: int, kind: int) -> void:
	var view: EnemyView = _enemy_views.get(id)
	if view == null:
		return
	match kind:
		Net.EnemyEvent.STAGGER:
			view.stagger()
		Net.EnemyEvent.STRIKE:
			view.strike()
		Net.EnemyEvent.DIED:
			view.die()
			_sfx.play(&"death")
		Net.EnemyEvent.BLOCK:
			view.block()
			_float_text("Blocked", Color("c0cbdc"), view.position)
			_sfx.play(&"block")
		Net.EnemyEvent.GAVE_UP:
			view.give_up()
			_float_text("?", Color("c0cbdc"), view.position)
			_sfx.play(&"give_up")


## A countdown of ours starts: the draught's or the rune ability's cooldown, or a regeneration.
func _on_status(kind: int, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	match kind:
		Net.Status.DRAUGHT:
			_draught_ready_ms = end
		Net.Status.ABILITY:
			_ability_ready_ms = end
			_sfx.play(&"dash")
		Net.Status.REGEN:
			_regen_end_ms = end


## An ability's area in view.
func _on_effect(kind: int, at: Vector2, radius: float, seconds: float) -> void:
	var view := EffectView.new()
	view.kind = kind
	view.radius = radius
	view.seconds = seconds
	view.position = at
	add_child(view)


## "8 s left" while cooked food regenerates health, "" otherwise.
func _regen_text() -> String:
	var left := (_regen_end_ms - Time.get_ticks_msec()) / 1000.0
	return "%d s left" % ceili(left) if left > 0 else ""


## The HUD's timers: regeneration, the draught if we carry one and the rune ability if worn.
func _status_text() -> String:
	var now := Time.get_ticks_msec()
	var parts := PackedStringArray()
	if _regen_end_ms > now:
		parts.append("Regen %ds" % ceili((_regen_end_ms - now) / 1000.0))
	if _inventory.first_draught() != -1:
		parts.append(_timer("Draught", _draught_ready_ms, &"heal", now))
	var ability := _inventory.ability()
	if ability:
		parts.append(_timer(ability.display_name, _ability_ready_ms, &"ability", now))
	return "  ".join(parts)


func _timer(label: String, ready_ms: int, action: StringName, now: int) -> String:
	var wait := ceili((ready_ms - now) / 1000.0)
	return "%s %s %s" % [KeyHint.tag(action), label, "%ds" % wait if wait > 0 else "ready"]


## The dash we just made dodged a hit perfectly: a flourish and a beat of slow motion.
func _on_perfect() -> void:
	_float_text("Perfect!", Color("feae34"), _me.position + Vector2(0, -8))
	_sfx.play(&"perfect")
	_slow(0.3, 0.2)


## Freezes the game for seconds of real time (hitstop), unless a longer freeze is on.
func _hitstop(seconds: float) -> void:
	_slow(0.02, seconds)


func _slow(time_scale: float, seconds: float) -> void:
	if not bot:
		_slow_motion.start(time_scale, seconds, Time.get_ticks_msec())


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## A number or note rising from above a position and fading out.
func _float_text(text: String, color: Color, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.modulate = color
	label.position = at + Vector2(-4, -36)
	label.z_index = 10
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 12, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _process(delta: float) -> void:
	Engine.time_scale = _slow_motion.scale_at(Time.get_ticks_msec())
	if bot and not _bot_done and Time.get_ticks_msec() > BOT_TIMEOUT_MS:
		push_error(
			(
				"client: bot timed out (echoed %s, enemy %s, inventory %s, saw %s)"
				% [_bot_echoed, _bot_saw_enemy, _bot_inventory, _bot_start]
			)
		)
		get_tree().quit(1)
		return
	if bot_duration > 0.0 and Time.get_ticks_msec() > bot_duration * 1000:
		if not _bot_done:
			push_error("client: bot never passed its check")
		_bot_leave(0 if _bot_done else 1)
		return
	if _me == null:
		return
	if bot_duration > 0.0 and _health > 0:
		_bot_swing_at -= delta
		if _bot_swing_at <= 0.0:
			_bot_swing_at = BOT_SWING_EVERY
			_attack(false)
	var bow := Content.item(_weapon)
	if bow == null or bow.ammo == &"":
		_draw_started_ms = 0
		_me.draw_share = 0.0
	else:
		_tick_draw(bow)
	_shake = move_toward(_shake, 0.0, 20.0 * delta)
	_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * Settings.shake
	if _knock_vel != Vector2.ZERO:
		_walk(_knock_vel * delta)
		_knock_vel *= exp(-Content.tuning.knock_decay * delta)
		if _knock_vel.length() < 4.0:
			_knock_vel = Vector2.ZERO
	if _dash_left > 0.0:
		var step := minf(delta, _dash_left)
		_dash_left -= step
		var t := Content.tuning
		_walk(_dash_dir * t.dash_distance / t.dash_time * step)
	elif _health > 0:
		var speed := Content.tuning.walk_speed * (1.0 + _buffs.stat("move_speed"))
		_walk(_input_direction() * speed * delta)
	if not _area.is_empty():
		_me.position = Dungeon.clamp_to(_area, _me.position)
	_send_due -= delta
	if _send_due <= 0.0:
		_send_due += 1.0 / SEND_RATE
		net.move.rpc_id(1, _me.position)
		_drop_far_chunks()
	_ping_due -= delta
	if _lobby and _ping_due <= 0.0:
		_ping_due = PING_INTERVAL
		net.ping.rpc_id(1, Time.get_ticks_msec())
	var at := Time.get_ticks_msec() - INTERP_DELAY_MS
	_show_enemies(
		Interpolation.sample(_snapshots, at, "enemies"),
		Interpolation.sample(_snapshots, at, "facings")
	)
	_show_remote_players(Interpolation.sample(_snapshots, at))
	_map.me = _me.position
	_map.players.assign(
		_views.values().map(func(view: PlayerView) -> Vector2: return view.position)
	)
	_map.refresh()
	_inventory_ui.stations = Building.stations_near(_pieces, _me.position)
	_craft_menu.stations = _inventory_ui.stations
	_craft_menu.inventory = _inventory
	if _craft_menu.visible and _craft_menu.stations.is_empty():
		_craft_menu.toggle()
	# Building puts the weapon away, so the menu and the ghost have the player's attention.
	_me.holding = not _build.visible
	if _build.visible:
		var bodies: Array[Vector2] = [_me.position]
		for view: Node2D in _views.values() + _enemy_views.values():
			bodies.append(view.position)
		_build.update(
			get_global_mouse_position(), _pieces, _chunks, _inventory, _me.position, bodies
		)
	_update_target()
	_update_grave_marker()
	if _time >= 0:
		_time += delta
		_show_clock()


## Tints the world by daylight and shows the day in the HUD.
func _show_clock() -> void:
	_tint.color = NIGHT_TINT.lerp(Color.WHITE, Survival.daylight(_time))
	if not _area.is_empty():
		_tint.color = DUNGEON_TINT
	var night := Survival.is_night(_time)
	var left := ceili(Survival.until_change(_time))
	_hud.show_clock(
		(
			"%s %d  %d:%02d to %s"
			% [
				"Night" if night else "Day",
				Survival.day_number(_time),
				left / 60,
				left % 60,
				"dawn" if night else "dusk"
			]
		),
		night
	)


func _input_direction() -> Vector2:
	if bot and bot_duration > 0.0:
		return Vector2.from_angle(_bot_bearing + Time.get_ticks_msec() / 1000.0 / BOT_ROAM_TURN)
	if bot:
		return Vector2.from_angle(Time.get_ticks_msec() / 500.0)
	if _pause.visible or _craft_menu.typing():
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


## players: {id: Vector3(x, y, health)}.
func _show_remote_players(players: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	var positions := {}
	for id: int in players:
		positions[id] = Vector2(players[id].x, players[id].y)
	for id: int in _views.keys():
		if not players.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for id: int in players:
		if id == me:
			continue
		if not _views.has(id):
			_views[id] = PlayerView.new()
			add_child(_views[id])
		_views[id].position = positions[id]
		_views[id].health = players[id].z
	if bot:
		_bot_check(positions)


## enemies: {id: Vector3(x, y, Net.enemy_z)}, facings: {id: Vector2} of those with a shield. The
## HUD's boss bar follows the first boss in view.
func _show_enemies(enemies: Dictionary, facings: Dictionary) -> void:
	for id: int in _enemy_views.keys():
		if not enemies.has(id):
			# A dead one frees itself once it has fallen.
			if not _enemy_views[id].dying:
				_enemy_views[id].queue_free()
			_enemy_views.erase(id)
	var boss: EnemyView = null
	for id: int in enemies:
		var enemy: Vector3 = enemies[id]
		if not _enemy_views.has(id):
			_enemy_views[id] = EnemyView.new()
			_enemy_views[id].def = Content.enemies[Content.enemy_ids[Net.enemy_kind(enemy.z)]]
			add_child(_enemy_views[id])
		var view: EnemyView = _enemy_views[id]
		if view.dying:
			continue
		view.position = Vector2(enemy.x, enemy.y)
		view.health = Net.enemy_health(enemy.z)
		view.modulate = SLOWED if Net.enemy_slowed(enemy.z) else Color.WHITE
		if facings.has(id):
			view.facing = facings[id]
		if boss == null and view.def.size > 1:
			boss = view
	_hud.show_boss(boss.def.display_name if boss else "", boss.health if boss else 0.0)
	_bot_saw_enemy = _bot_saw_enemy or not enemies.is_empty()


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
	var seen_all := _bot_echoed and _bot_saw_enemy and _bot_inventory and not _chunks.is_empty()
	if seen_all and moving >= bot_expect and not _bot_done:
		_bot_done = true
		print(
			(
				"client: bot ok, %d chunks, saw enemies and %d moving player(s)"
				% [_chunks.size(), moving]
			)
		)
		if bot_duration > 0.0:
			return
		await get_tree().create_timer(BOT_LINGER).timeout
		_bot_leave(0)


func _bot_leave(code: int) -> void:
	set_process(false)
	# Disconnect now, so the server sees us leave instead of timing us out.
	multiplayer.multiplayer_peer.close()
	get_tree().quit(code)
