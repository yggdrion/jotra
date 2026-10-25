class_name SimWorld
extends RefCounted
## The server's simulation. Plain objects, no scene tree: tests build one directly and step it
## with tick(delta); GameServer drives the same path. Keeps the chunks around players loaded
## and, with a store, saves what changed against the seed.


class SimPlayer:
	var id: int
	var name: String
	var position: Vector2
	## Sim time of the last accepted move, for the speed check.
	var moved_at: float

	func _init(player_id: int, player_name: String, spawn: Vector2, now: float) -> void:
		id = player_id
		name = player_name
		position = spawn
		moved_at = now


class SimChunk:
	## {id: WorldGen.Prop} as generated from the seed.
	var props: Dictionary
	## {id: true} of props removed since.
	var removed := {}
	var dirty := false


## Player walk speed in px/s. Client movement uses the same number.
# ponytail: one constant until M3 moves gameplay numbers into .tres data.
const MAX_SPEED := 120.0
## Extra time allowed per move, so packets that arrive bunched up still pass.
const MOVE_SLACK := 0.5
const SPAWN_SPACING := 24.0
## Chunks a player sees in each direction from its own: 2 covers 1024 px or more, over half the
## widest view (1280×360 at 32:9, PLAN §6) plus a margin. Chunks stay loaded one further out.
const VIEW_CHUNKS := 2
## How far from a prop a player can remove it, in px. The client uses the same number.
const REACH := 32.0
## Extra reach the server allows, as its copy of the player lags the client's.
const REACH_SLACK := 16.0

var world_seed := 0
## Null in tests: nothing is saved.
var store: WorldStore
var time := 0.0
var players := {}  # id -> SimPlayer
var chunks := {}  # Vector2i -> SimChunk


## Loads the world in path, or creates it with a random seed. Null if it can't be read.
static func open(path: String) -> SimWorld:
	var world := SimWorld.new()
	world.store = WorldStore.new(path)
	var meta: Variant = world.store.load_meta()
	if meta == null:
		return null
	if meta.is_empty():
		world.world_seed = randi()
		world.save()
	else:
		world.world_seed = int(meta.seed)
		world.time = meta.time
	return world


## Paused while nobody is online: time stands still.
func tick(delta: float) -> void:
	if players.is_empty():
		return
	time += delta
	_stream_chunks()


## Loads every chunk a player sees, unloads (and saves) those no player is near any more.
func _stream_chunks() -> void:
	var keep := {}
	for player: SimPlayer in players.values():
		var center := WorldGen.chunk_of(player.position)
		for coord in WorldGen.around(center, VIEW_CHUNKS + 1):
			keep[coord] = true
		for coord in WorldGen.around(center, VIEW_CHUNKS):
			if not chunks.has(coord):
				_load_chunk(coord)
	for coord: Vector2i in chunks.keys():
		if not keep.has(coord):
			_save_chunk(coord)
			chunks.erase(coord)


func _load_chunk(coord: Vector2i) -> void:
	var chunk := SimChunk.new()
	chunk.props = WorldGen.chunk(world_seed, coord).props
	if store:
		for id in store.load_chunk(coord):
			chunk.removed[id] = true
	chunks[coord] = chunk


func _save_chunk(coord: Vector2i) -> void:
	var chunk: SimChunk = chunks[coord]
	if store and chunk.dirty:
		store.save_chunk(coord, removed_props(coord))
		chunk.dirty = false


## Meta, changed chunks and everyone online.
func save() -> void:
	if store == null:
		return
	store.save_meta({seed = world_seed, time = time})
	for coord: Vector2i in chunks:
		_save_chunk(coord)
	for player: SimPlayer in players.values():
		_save_player(player)


func _save_player(player: SimPlayer) -> void:
	if store:
		store.save_player(player.name, {x = player.position.x, y = player.position.y})


## Joins at the saved position of that name, or at a fresh spawn.
func add_player(id: int, player_name: String) -> SimPlayer:
	var spawn := Vector2(players.size() * SPAWN_SPACING, 0)
	var saved := store.load_player(player_name) if store else {}
	if not saved.is_empty():
		spawn = Vector2(saved.x, saved.y)
	var player := SimPlayer.new(id, player_name, spawn, time)
	players[id] = player
	return player


func remove_player(id: int) -> void:
	if players.has(id):
		_save_player(players[id])
	players.erase(id)


func is_online(player_name: String) -> bool:
	return players.values().any(func(p: SimPlayer) -> bool: return p.name == player_name)


## Client-authoritative movement with a basic sanity check: a move further than the walk speed
## allows (plus slack) is a teleport and is dropped. Returns whether it was accepted.
# ponytail: no correction sent back; a dropped move only holds the server copy until the next one.
func move_player(id: int, position: Vector2) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null:
		return false
	var allowed := MAX_SPEED * (time - player.moved_at + MOVE_SLACK)
	if player.position.distance_to(position) > allowed:
		return false
	player.position = position
	player.moved_at = time
	return true


## Removes a prop the player stands next to. Returns whether it was removed.
func remove_prop(id: int, coord: Vector2i, prop_id: int) -> bool:
	var player: SimPlayer = players.get(id)
	var chunk: SimChunk = chunks.get(coord)
	if player == null or chunk == null:
		return false
	if not chunk.props.has(prop_id) or chunk.removed.has(prop_id):
		return false
	var reach := player.position.distance_to(WorldGen.prop_position(coord, prop_id))
	if reach > REACH + REACH_SLACK:
		return false
	chunk.removed[prop_id] = true
	chunk.dirty = true
	return true


## Ids of the props removed from a loaded chunk, as sent to clients and saved.
func removed_props(coord: Vector2i) -> PackedInt32Array:
	return PackedInt32Array(chunks[coord].removed.keys())


## The chunks a player sees.
func interest(id: int) -> Array[Vector2i]:
	return WorldGen.around(WorldGen.chunk_of(players[id].position), VIEW_CHUNKS)


## {id: position} of the players near one player (itself included), as sent to its client.
func snapshot_for(id: int) -> Dictionary:
	var center := WorldGen.chunk_of(players[id].position)
	var out := {}
	for other: SimPlayer in players.values():
		if WorldGen.near(WorldGen.chunk_of(other.position), center, VIEW_CHUNKS):
			out[other.id] = other.position
	return out
