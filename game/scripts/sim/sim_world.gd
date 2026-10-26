class_name SimWorld
extends RefCounted
## The server's simulation. Plain objects, no scene tree: tests build one directly and step it
## with tick(delta); GameServer drives the same path. Keeps the chunks around players loaded,
## runs combat and enemies, drops loot that players walk over to pick up, handles inventories,
## crafting, hunger and eating, spawns more and stronger enemies at night and, with a store,
## saves what changed against the seed and the players.


class SimPlayer:
	var id: int
	var name: String
	var position: Vector2
	## Sim time of the last accepted move, for the speed check.
	var moved_at: float
	## Sim time of the last "inventory full" notice, so standing on loot doesn't spam it.
	var full_noticed_at := -INF
	var health := Content.tuning.max_health
	var stamina := Content.tuning.max_stamina
	var hunger := Content.tuning.max_hunger
	var inventory := Inventory.new(Content.tuning.inventory_size)
	var stamina_used_at := -INF
	var cooldown_until := -INF
	var dashed_at := -INF
	var gathered_at := -INF
	## Sim time of the respawn while dead, 0 while alive.
	var dead_until := 0.0

	func _init(player_id: int, player_name: String, spawn: Vector2, now: float) -> void:
		id = player_id
		name = player_name
		position = spawn
		moved_at = now

	## Base health plus what the worn gear adds.
	func max_health() -> float:
		return Content.tuning.max_health + inventory.worn("health")

	## Wears the item in an inventory slot.
	func equip(index: int) -> bool:
		if not inventory.equip(index):
			return false
		health = minf(health, max_health())
		return true

	## Eats one of the food in an inventory slot, the first food for -1, unless dead or full.
	func eat(index: int) -> bool:
		if index == -1:
			index = inventory.first_food()
		if index < 0 or index >= inventory.slots.size() or dead_until > 0:
			return false
		var slot := inventory.slots[index]
		if slot.is_empty() or hunger >= Content.tuning.max_hunger:
			return false
		var food := Content.item(slot.item).food
		if food <= 0:
			return false
		inventory.take_at(index, 1)
		hunger = minf(hunger + food, Content.tuning.max_hunger)
		return true

	## Takes off what is worn in an ItemDef.Slot, into inventory slot to if that is free.
	func unequip(kind: int, to := -1) -> bool:
		if not inventory.unequip(kind, to):
			return false
		health = minf(health, max_health())
		return true


## Items lying on the ground.
class SimDrop:
	var id: int
	var item: StringName
	var count: int
	var position: Vector2
	## Sim time it vanishes.
	var until: float


class SimChunk:
	## {id: WorldGen.Prop} as generated from the seed.
	var props: Dictionary
	## {id: true} of props removed since.
	var removed := {}
	var dirty := false


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
## Seconds between two "inventory full" notices to one player.
const FULL_NOTICE_INTERVAL := 3.0

var world_seed := 0
## Null in tests: nothing is saved.
var store: WorldStore
var time := 0.0
var players := {}  # id -> SimPlayer
var chunks := {}  # Vector2i -> SimChunk
var enemies := {}  # id -> SimEnemy
var drops := {}  # id -> SimDrop
## Off in tests that place their own enemies.
var spawn_enemies := true
## What happened this tick for clients to show, drained by GameServer: ["hit", enemy: bool,
## id, amount, position], ["windup", enemy id, position, seconds], ["respawn", player id,
## position], ["swing", player id, heavy, aim, position, weapon], ["loot", player id, item,
## count] for a pickup, ["full", player id] when loot didn't fit.
var events: Array[Array] = []
## Seeded by the balance sim for repeatable runs.
var rng := RandomNumberGenerator.new()
var _next_enemy_id := 1
var _next_drop_id := 1
var _spawn_due := 0.0


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
		if nearest_player(enemies[id].position, Content.tuning.despawn_radius, false) == 0:
			enemies.erase(id)
	_tick_drops(delta)


## Drops slide toward the closest living player within magnet_radius, who picks them up
## within pickup_radius, as much as fits; a full inventory gets a notice every
## FULL_NOTICE_INTERVAL. Drops vanish when their time is up or their chunk unloads.
# ponytail: drops are not saved; a restart or an unloaded chunk loses them.
func _tick_drops(delta: float) -> void:
	var t := Content.tuning
	for id: int in drops.keys():
		var drop: SimDrop = drops[id]
		if time >= drop.until or not chunks.has(WorldGen.chunk_of(drop.position)):
			drops.erase(id)
			continue
		var player: SimPlayer = players.get(nearest_player(drop.position, t.magnet_radius))
		if player == null:
			continue
		drop.position = drop.position.move_toward(player.position, t.magnet_speed * delta)
		if drop.position.distance_to(player.position) > t.pickup_radius:
			continue
		var left := player.inventory.add(drop.item, drop.count)
		if left < drop.count:
			events.append(["loot", player.id, drop.item, drop.count - left])
		elif time - player.full_noticed_at >= FULL_NOTICE_INTERVAL:
			player.full_noticed_at = time
			events.append(["full", player.id])
		drop.count = left
		if left == 0:
			drops.erase(id)


## Rolls a drop table and scatters what it gives around at.
func _drop_loot(table: Array, at: Vector2) -> void:
	var scatter := Content.tuning.drop_scatter
	for got in Loot.roll(table, rng):
		var offset := Vector2(
			rng.randf_range(-scatter, scatter), rng.randf_range(-scatter, scatter)
		)
		add_drop(got[0], got[1], at + offset)


func add_drop(item: StringName, count: int, at: Vector2) -> SimDrop:
	var drop := SimDrop.new()
	drop.id = _next_drop_id
	drop.item = item
	drop.count = count
	drop.position = at
	drop.until = time + Content.tuning.drop_lifetime
	drops[drop.id] = drop
	_next_drop_id += 1
	return drop


func _tick_player(player: SimPlayer, delta: float) -> void:
	if player.dead_until > 0:
		if time >= player.dead_until:
			player.dead_until = 0.0
			player.health = player.max_health()
			player.stamina = Content.tuning.max_stamina
			player.hunger = maxf(player.hunger, Content.tuning.respawn_hunger)
			player.position = Content.tuning.respawn_at
			player.moved_at = time
			events.append(["respawn", player.id, player.position])
		return
	var t := Content.tuning
	player.hunger = maxf(player.hunger - t.hunger_drain * delta, 0.0)
	var regen := t.stamina_regen
	if player.hunger > 0:
		player.health = minf(player.health + t.health_regen * delta, player.max_health())
	else:
		regen *= t.starve_stamina
		player.health = maxf(player.health - t.starve_damage * delta, 0.0)
		if player.health == 0:
			_die(player)
	if time - player.stamina_used_at >= t.stamina_delay:
		player.stamina = minf(player.stamina + regen * delta, t.max_stamina)


func _die(player: SimPlayer) -> void:
	player.dead_until = time + Content.tuning.respawn_delay


## Tops up the enemies around each living player, one per player per spawn_interval, in number
## and strength scaled by the players near that one and, at night, by Survival.night_scale.
func _spawn(delta: float) -> void:
	_spawn_due -= delta
	if _spawn_due > 0.0:
		return
	var t := Content.tuning
	_spawn_due = t.spawn_interval
	var night := Survival.night_scale(time)
	for player: SimPlayer in players.values():
		if player.dead_until > 0:
			continue
		var scale := Combat.scaled(players_near(player.position))
		var want := roundi(t.enemies_per_player * scale.count * night.count)
		var have := 0
		for enemy: SimEnemy in enemies.values():
			if enemy.position.distance_to(player.position) <= t.spawn_radius:
				have += 1
		if have >= want:
			continue
		var distance := rng.randf_range(t.spawn_ring_min, t.spawn_ring_max)
		var at := player.position + Vector2.from_angle(rng.randf() * TAU) * distance
		var enemy := add_enemy(
			at,
			t.enemy.health * scale.health * night.health,
			t.enemy.damage * scale.damage * night.damage
		)
		enemy.speed *= night.speed


## An enemy of kind (Tuning.enemy by default) with health and damage already scaled.
func add_enemy(at: Vector2, health: float, damage: float, kind: EnemyDef = null) -> SimEnemy:
	var enemy := SimEnemy.new(
		_next_enemy_id, kind if kind else Content.tuning.enemy, at, health, damage
	)
	enemies[enemy.id] = enemy
	_next_enemy_id += 1
	return enemy


## Living players within scale_radius of a position.
func players_near(at: Vector2) -> int:
	var count := 0
	for player: SimPlayer in players.values():
		var near := player.position.distance_to(at) <= Content.tuning.scale_radius
		if player.dead_until == 0 and near:
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
		(
			store
			. save_player(
				player.name,
				{
					x = player.position.x,
					y = player.position.y,
					health = player.health,
					hunger = player.hunger,
					inventory = player.inventory.to_data(),
				}
			)
		)


## Joins at the saved position of that name with its saved inventory and hunger, or fresh at
## the spawn.
func add_player(id: int, player_name: String) -> SimPlayer:
	var spawn := Vector2(players.size() * SPAWN_SPACING, 0)
	var saved := store.load_player(player_name) if store else {}
	if not saved.is_empty():
		spawn = Vector2(saved.x, saved.y)
	var player := SimPlayer.new(id, player_name, spawn, time)
	player.inventory.load_data(saved.get("inventory", {}))
	# Someone who left while dead comes back alive.
	var health := minf(float(saved.get("health", player.max_health())), player.max_health())
	player.health = health if health > 0 else player.max_health()
	player.hunger = clampf(float(saved.get("hunger", player.hunger)), 0.0, player.hunger)
	if health <= 0:
		player.hunger = maxf(player.hunger, Content.tuning.respawn_hunger)
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
	var t := Content.tuning
	var allowed := t.walk_speed * (time - player.moved_at + MOVE_SLACK)
	if time - player.dashed_at <= t.dash_time + MOVE_SLACK:
		allowed += t.dash_distance
	if player.position.distance_to(position) > allowed:
		return false
	player.position = position
	player.moved_at = time
	return true


## Removes a prop the player stands next to, at most one per gather_time; it drops what it is
## made of. Returns whether it was removed.
func remove_prop(id: int, coord: Vector2i, prop_id: int) -> bool:
	var player: SimPlayer = players.get(id)
	var chunk: SimChunk = chunks.get(coord)
	if player == null or chunk == null or player.dead_until > 0:
		return false
	if time - player.gathered_at < Content.tuning.gather_time:
		return false
	if not chunk.props.has(prop_id) or chunk.removed.has(prop_id):
		return false
	var reach := player.position.distance_to(WorldGen.prop_position(coord, prop_id))
	if reach > REACH + REACH_SLACK:
		return false
	chunk.removed[prop_id] = true
	chunk.dirty = true
	player.gathered_at = time
	var t := Content.tuning
	_drop_loot(
		t.tree_drops if chunk.props[prop_id] == WorldGen.Prop.TREE else t.rock_drops,
		WorldGen.prop_position(coord, prop_id)
	)
	return true


## A light or heavy swing toward aim. The client reports the enemies it saw hit (PLAN §4.4); the
## server checks them against its own copy with some slack. The equipped weapon decides the
## swing. Returns the enemies damaged, empty if the swing itself was refused (dead, cooling
## down, out of stamina). Enemies killed drop their loot.
func attack(id: int, heavy: bool, aim: Vector2, hits: PackedInt32Array) -> PackedInt32Array:
	var player: SimPlayer = players.get(id)
	var damaged := PackedInt32Array()
	if player == null:
		return damaged
	var move := Content.attack(player.inventory.weapon(), heavy)
	if time < player.cooldown_until or not _spend(player, move.cost):
		return damaged
	player.cooldown_until = time + move.cooldown
	events.append(["swing", id, heavy, aim, player.position, player.inventory.weapon()])
	var reach := move.reach + Content.tuning.hit_slack
	var arc := move.arc + Content.tuning.arc_slack
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
			_drop_loot(enemy.def.drops, enemy.position)
	return damaged


## Starts a dash: i-frames now, and the next moves may cover its distance.
func dash(id: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or time - player.dashed_at < Content.tuning.dash_cooldown:
		return false
	if not _spend(player, Content.tuning.dash_cost):
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


## An enemy hit lands, less the player's armor, unless the player is dead or dashing. Returns
## whether it did.
func damage_player(id: int, amount: float) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0:
		return false
	if time - player.dashed_at <= Content.tuning.iframes + Content.tuning.iframe_slack:
		return false
	var taken := Combat.after_armor(amount, player.inventory.worn("armor"))
	player.health = maxf(player.health - taken, 0.0)
	events.append(["hit", false, id, taken, player.position])
	if player.health == 0:
		_die(player)
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
## same, drops: {id: Vector3(x, y, Content.item_index)}, me: Vector4(health, stamina, max
## health, hunger), time: the world's time for the day/night clock}, with only the players
## (itself included), enemies and drops near it.
func snapshot_for(id: int) -> Dictionary:
	var near := {}
	for other: SimPlayer in players.values():
		if sees(id, other.position):
			near[other.id] = Vector3(
				other.position.x, other.position.y, other.health / other.max_health()
			)
	var near_enemies := {}
	for enemy: SimEnemy in enemies.values():
		if sees(id, enemy.position):
			near_enemies[enemy.id] = Vector3(
				enemy.position.x, enemy.position.y, enemy.health / enemy.max_health
			)
	var near_drops := {}
	for drop: SimDrop in drops.values():
		if sees(id, drop.position):
			near_drops[drop.id] = Vector3(
				drop.position.x, drop.position.y, Content.item_index(drop.item)
			)
	var me: SimPlayer = players[id]
	return {
		players = near,
		enemies = near_enemies,
		drops = near_drops,
		me = Vector4(me.health, me.stamina, me.max_health(), me.hunger),
		time = time,
	}
