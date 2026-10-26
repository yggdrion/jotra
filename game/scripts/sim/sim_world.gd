class_name SimWorld
extends RefCounted
## The server's simulation. Plain objects, no scene tree: tests build one directly and step it
## with tick(delta); GameServer drives the same path. Keeps the chunks around players loaded,
## runs combat and enemies, and, with a store, saves what changed against the seed.


class SimPlayer:
	var id: int
	var name: String
	var position: Vector2
	## Sim time of the last accepted move, for the speed check.
	var moved_at: float
	var health := Combat.MAX_HEALTH
	var stamina := Combat.MAX_STAMINA
	var stamina_used_at := -INF
	var cooldown_until := -INF
	var dashed_at := -INF
	## Sim time of the respawn while dead, 0 while alive.
	var dead_until := 0.0

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
# ponytail: one constant until M4 moves gameplay numbers into .tres data.
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
var enemies := {}  # id -> SimEnemy
## Off in tests that place their own enemies.
var spawn_enemies := true
## What happened this tick for clients to show, drained by GameServer: ["hit", enemy: bool,
## id, amount, position], ["windup", enemy id, position], ["respawn", player id, position].
var events: Array[Array] = []
var _next_enemy_id := 1
var _spawn_due := 0.0
var _rng := RandomNumberGenerator.new()


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
	for player: SimPlayer in players.values():
		_tick_player(player, delta)
	for enemy: SimEnemy in enemies.values():
		enemy.tick(self, delta)
	if spawn_enemies:
		_spawn(delta)
	for id: int in enemies.keys():
		if nearest_player(enemies[id].position, Combat.DESPAWN_RADIUS, false) == 0:
			enemies.erase(id)


func _tick_player(player: SimPlayer, delta: float) -> void:
	if player.dead_until > 0:
		if time >= player.dead_until:
			player.dead_until = 0.0
			player.health = Combat.MAX_HEALTH
			player.stamina = Combat.MAX_STAMINA
			player.position = Combat.RESPAWN_AT
			player.moved_at = time
			events.append(["respawn", player.id, player.position])
		return
	if time - player.stamina_used_at >= Combat.STAMINA_DELAY:
		player.stamina = minf(player.stamina + Combat.STAMINA_REGEN * delta, Combat.MAX_STAMINA)


## Tops up the enemies around each living player, one per player per SPAWN_INTERVAL, in number
## and strength scaled by the players near that one.
func _spawn(delta: float) -> void:
	_spawn_due -= delta
	if _spawn_due > 0.0:
		return
	_spawn_due = Combat.SPAWN_INTERVAL
	for player: SimPlayer in players.values():
		if player.dead_until > 0:
			continue
		var scale := Combat.scaled(players_near(player.position))
		var want := roundi(Combat.ENEMIES_PER_PLAYER * scale.count)
		var have := 0
		for enemy: SimEnemy in enemies.values():
			if enemy.position.distance_to(player.position) <= Combat.SPAWN_RADIUS:
				have += 1
		if have >= want:
			continue
		var distance := _rng.randf_range(Combat.SPAWN_RING_MIN, Combat.SPAWN_RING_MAX)
		var at := player.position + Vector2.from_angle(_rng.randf() * TAU) * distance
		add_enemy(at, Combat.ENEMY_HEALTH * scale.health, Combat.ENEMY_DAMAGE * scale.damage)


func add_enemy(at: Vector2, health: float, damage: float) -> SimEnemy:
	var enemy := SimEnemy.new(_next_enemy_id, at, health, damage)
	enemies[enemy.id] = enemy
	_next_enemy_id += 1
	return enemy


## Living players within SCALE_RADIUS of a position.
func players_near(at: Vector2) -> int:
	var count := 0
	for player: SimPlayer in players.values():
		if player.dead_until == 0 and player.position.distance_to(at) <= Combat.SCALE_RADIUS:
			count += 1
	return count


## Id of the closest player within radius (only living ones if living), 0 if none.
func nearest_player(at: Vector2, radius: float, living := true) -> int:
	var best := 0
	var best_distance := radius
	for player: SimPlayer in players.values():
		var distance := player.position.distance_to(at)
		if distance <= best_distance and not (living and player.dead_until > 0):
			best = player.id
			best_distance = distance
	return best


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
		store.save_player(
			player.name, {x = player.position.x, y = player.position.y, health = player.health}
		)


## Joins at the saved position of that name, or at a fresh spawn.
func add_player(id: int, player_name: String) -> SimPlayer:
	var spawn := Vector2(players.size() * SPAWN_SPACING, 0)
	var saved := store.load_player(player_name) if store else {}
	if not saved.is_empty():
		spawn = Vector2(saved.x, saved.y)
	var player := SimPlayer.new(id, player_name, spawn, time)
	# Someone who left while dead comes back alive.
	var health := float(saved.get("health", Combat.MAX_HEALTH))
	player.health = health if health > 0 else Combat.MAX_HEALTH
	players[id] = player
	return player


func remove_player(id: int) -> void:
	if players.has(id):
		_save_player(players[id])
	players.erase(id)


func is_online(player_name: String) -> bool:
	return players.values().any(func(p: SimPlayer) -> bool: return p.name == player_name)


## Client-authoritative movement with a basic sanity check: a move further than the walk speed
## allows (plus slack, plus a dash's distance right after one) is a teleport and is dropped, as
## are moves of the dead. Returns whether it was accepted.
# ponytail: no correction sent back; a dropped move only holds the server copy until the next one.
func move_player(id: int, position: Vector2) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0:
		return false
	var allowed := MAX_SPEED * (time - player.moved_at + MOVE_SLACK)
	if time - player.dashed_at <= Combat.DASH_TIME + MOVE_SLACK:
		allowed += Combat.DASH_DISTANCE
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


## A light or heavy swing toward aim. The client reports the enemies it saw hit (PLAN §4.4); the
## server checks them against its own copy with some slack. Returns the enemies damaged, empty
## if the swing itself was refused (dead, cooling down, out of stamina).
func attack(id: int, heavy: bool, aim: Vector2, hits: PackedInt32Array) -> PackedInt32Array:
	var player: SimPlayer = players.get(id)
	var move: Dictionary = Combat.HEAVY if heavy else Combat.LIGHT
	var damaged := PackedInt32Array()
	if player == null or time < player.cooldown_until or not _spend(player, move.cost):
		return damaged
	player.cooldown_until = time + move.cooldown
	var reach: float = move.reach + Combat.HIT_SLACK
	var arc: float = move.arc + Combat.ARC_SLACK
	for enemy_id in hits:
		var enemy: SimEnemy = enemies.get(enemy_id)
		if enemy == null or not Combat.in_arc(player.position, aim, enemy.position, reach, arc):
			continue
		enemy.health -= move.damage
		enemy.position += (enemy.position - player.position).normalized() * move.knock
		enemy.provoke(id)
		events.append(["hit", true, enemy.id, move.damage, enemy.position])
		damaged.append(enemy.id)
		if enemy.health <= 0:
			enemies.erase(enemy.id)
	return damaged


## Starts a dash: i-frames now, and the next moves may cover its distance.
func dash(id: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or time - player.dashed_at < Combat.DASH_COOLDOWN:
		return false
	if not _spend(player, Combat.DASH_COST):
		return false
	player.dashed_at = time
	return true


## Spends stamina if the player is alive and has enough.
func _spend(player: SimPlayer, cost: float) -> bool:
	if player.dead_until > 0 or player.stamina < cost:
		return false
	player.stamina -= cost
	player.stamina_used_at = time
	return true


## An enemy hit lands, unless the player is dead or dashing. Returns whether it did.
func damage_player(id: int, amount: float) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0:
		return false
	if time - player.dashed_at <= Combat.IFRAMES + Combat.IFRAME_SLACK:
		return false
	player.health = maxf(player.health - amount, 0.0)
	events.append(["hit", false, id, amount, player.position])
	if player.health == 0:
		player.dead_until = time + Combat.RESPAWN_DELAY
	return true


## Ids of the props removed from a loaded chunk, as sent to clients and saved.
func removed_props(coord: Vector2i) -> PackedInt32Array:
	return PackedInt32Array(chunks[coord].removed.keys())


## The chunks a player sees.
func interest(id: int) -> Array[Vector2i]:
	return WorldGen.around(WorldGen.chunk_of(players[id].position), VIEW_CHUNKS)


## Whether a position is within a player's view.
func sees(id: int, at: Vector2) -> bool:
	return WorldGen.near(
		WorldGen.chunk_of(at), WorldGen.chunk_of(players[id].position), VIEW_CHUNKS
	)


## What one player's client is sent: {players: {id: Vector3(x, y, health 0..1)}, enemies: the
## same, me: Vector2(health, stamina)}, with only the players (itself included) and enemies
## near it.
func snapshot_for(id: int) -> Dictionary:
	var near := {}
	for other: SimPlayer in players.values():
		if sees(id, other.position):
			near[other.id] = Vector3(
				other.position.x, other.position.y, other.health / Combat.MAX_HEALTH
			)
	var near_enemies := {}
	for enemy: SimEnemy in enemies.values():
		if sees(id, enemy.position):
			near_enemies[enemy.id] = Vector3(
				enemy.position.x, enemy.position.y, enemy.health / enemy.max_health
			)
	var me: SimPlayer = players[id]
	return {players = near, enemies = near_enemies, me = Vector2(me.health, me.stamina)}
