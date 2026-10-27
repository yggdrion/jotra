# gdlint: disable=max-public-methods,max-file-lines
# Every request a client can make lands on the world, so it outgrows the public method limit
# and, with the rules it runs, the file length limit.
class_name SimWorld
extends RefCounted
## The server's simulation. Plain objects, no scene tree: tests build one directly and step it
## with tick(delta); GameServer drives the same path. Keeps the chunks around players loaded,
## runs combat and enemies, drops loot that players walk over to pick up, handles inventories,
## crafting, building (Building), hunger and eating, spawns more and stronger enemies at night,
## runs dungeon instances (Dungeon) with their buffs (Buffs), leaves a grave of the inventory
## where a player dies in the overworld and respawns it at its bed, and, with a store, saves what
## changed against the seed and the players.


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
	## Sim time of the last bow shot, for the draw time check.
	var shot_at := -INF
	var gathered_at := -INF
	## Sim time of the respawn while dead, 0 while alive.
	var dead_until := 0.0
	## The dungeon run the player is in, null in the overworld.
	var run: Dungeon
	## Inventory.to_data from entering the run, restored on dying inside (PLAN §4.8).
	var snapshot := {}
	## Dungeon buffs, held only inside a run.
	var buffs := Buffs.new()
	## The tile of the chest the player has open, null if none.
	var open_chest: Variant = null
	## Health per second from cooked food, for regen_left more seconds.
	var regen := 0.0
	var regen_left := 0.0
	## Sim times the next healing draught and the next rune ability may be used.
	var draught_ready_at := -INF
	var ability_ready_at := -INF
	## The tile of the bed it respawns at, null for the spawn.
	var bed: Variant = null
	## Where its unlooted graves lie, for the client's marker.
	var graves: Array[Vector2] = []

	func _init(player_id: int, player_name: String, spawn: Vector2, now: float) -> void:
		id = player_id
		name = player_name
		position = spawn
		moved_at = now

	## Base health plus what the worn gear and buffs add.
	func max_health() -> float:
		return Content.tuning.max_health + inventory.worn("health") + buffs.stat("max_health")

	## Health or stamina back, up to the max.
	func heal(health_back: float, stamina_back := 0.0) -> void:
		health = minf(health + health_back, max_health())
		stamina = minf(stamina + stamina_back, Content.tuning.max_stamina)

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
		var def := Content.item(slot.item)
		if def.food <= 0:
			return false
		inventory.take_at(index, 1)
		hunger = minf(hunger + def.food, Content.tuning.max_hunger)
		if def.regen > 0:
			regen = def.regen
			regen_left = def.regen_time
		return true

	## Takes off what is worn in an ItemDef.Slot, into inventory slot to if that is free.
	func unequip(kind: int, to := -1) -> bool:
		if not inventory.unequip(kind, to):
			return false
		health = minf(health, max_health())
		return true


## A healing ward standing on the ground until a sim time.
class SimWard:
	var id: int
	var position: Vector2
	var radius: float
	## Health per second to every player within radius.
	var heal_per_second: float
	var until: float


## Items lying on the ground, or a buff orb inside a run.
class SimDrop:
	var id: int
	var item: StringName
	## The buff an orb gives, "" for items.
	var buff := &""
	var count: int
	var position: Vector2
	## Sim time it vanishes.
	var until: float


## The inventory slots of a player who died in the overworld, lying where it died until that
## player takes them all back.
class SimGrave:
	var id: int
	## The name of the player it belongs to.
	var owner: String
	var position: Vector2
	var items := Inventory.new(Content.tuning.inventory_size)


class SimChunk:
	## {id: WorldGen.Prop} as generated from the seed.
	var props: Dictionary
	## {id: true} of props removed since.
	var removed := {}
	## {id: health left} of trees and rocks swung at, only while the chunk stays loaded.
	var node_health := {}
	## {global tile: Building.Piece} built in it.
	var pieces := {}
	## {id: SimGrave} lying in it.
	var graves := {}
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
## Pack members spawn this far (px) around the first.
const PACK_SPREAD := 28.0
## Tiles all enemies' path searches may expand in one tick (Pathing.find); those left over
## search on a later tick.
const PATH_BUDGET := 600

var world_seed := 0
## Null in tests: nothing is saved.
var store: WorldStore
var time := 0.0
var players := {}  # id -> SimPlayer
var chunks := {}  # Vector2i -> SimChunk
var enemies := {}  # id -> SimEnemy
var drops := {}  # id -> SimDrop
var projectiles := {}  # id -> SimProjectile
var wards := {}  # id -> SimWard
var dungeons := {}  # slot -> Dungeon
## {global tile: Building.Piece} of every loaded chunk.
var pieces := {}
## Goes up whenever a piece that blocks may have come or gone (built, broken, a door, a chunk
## loaded or unloaded), so enemies search their paths again.
var pieces_version := 0
## Tiles path searches may still expand this tick.
var path_budget := PATH_BUDGET
## {id: SimGrave} of every loaded chunk.
var graves := {}
## Off in tests that place their own enemies.
var spawn_enemies := true
## Spawns only this kind instead of the day and night mix (tests, the balance sim).
var spawn_kind: EnemyDef
## What happened this tick for clients to show, drained by GameServer: ["hit", enemy: bool,
## id, amount, position, push: the way and px the hit shoves the one hit],
## ["windup", enemy id, position, seconds, radius of the area it will hit, line: the unit
## vector of an arrow line of that length instead of the disc, zero for a disc],
## ["enemy", enemy id, Net.EnemyEvent, position], ["perfect", player id] for a perfectly
## dodged hit,
## ["respawn", player id, position], ["swing", player id, heavy, aim, position, weapon],
## ["loot", player id, item, count] for a pickup, ["full", player id] when loot didn't fit,
## ["dungeon", player id, area, exit, chest, position] when a player entered a run or (area
## empty) is back in the overworld, ["chest", player id] when one opened its run's end
## chest, ["node", player id, position, note] when a swing hit a tree or rock (the damage, or
## what it needs), ["prop_removed", chunk, prop id], ["piece", tile] when a piece was built,
## changed (damage, door) or is gone,
## ["storage", player id, Inventory.to_data of its open chest, {} once closed],
## ["grave", chunk, grave id] when a grave appeared, changed or is gone, ["graves", player id]
## when where its graves lie changed, ["bed", player id] when it set its respawn at a bed.
var events: Array[Array] = []
## Seeded by the balance sim for repeatable runs.
var rng := RandomNumberGenerator.new()
var _next_enemy_id := 1
var _next_drop_id := 1
var _next_projectile_id := 1
var _next_pack_id := 1
var _next_ward_id := 1
var _next_grave_id := 1
var _spawn_due := 0.0
var _blocked := {}
var _blocked_version := -1


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
	path_budget = PATH_BUDGET
	for player: SimPlayer in players.values():
		_tick_player(player, delta)
	# After the players: a respawn moves one, and its new view must be loaded before it is sent.
	_stream_chunks()
	for run: Dungeon in dungeons.values():
		_wake_rooms(run)
	for enemy: SimEnemy in enemies.values():
		enemy.tick(self, delta)
		if time < enemy.bleed_until and enemies.has(enemy.id):
			_hurt_enemy(enemy, enemy.bleed_dps * delta, players.get(enemy.bleed_by), false)
		var run := _run_at(enemy.position)
		if run:
			enemy.position = Dungeon.clamp_to(run.area, enemy.position)
	_tick_projectiles(delta)
	_tick_wards(delta)
	if spawn_enemies:
		_spawn(delta)
	for id: int in enemies.keys():
		if nearest_player(enemies[id].position, Content.tuning.despawn_radius, false) == 0:
			enemies.erase(id)
	_tick_drops(delta)


## Drops slide toward the closest living player within magnet_radius, who picks them up
## within pickup_radius, as much as fits (a buff orb: unless at its max stacks); a full
## inventory gets a notice every FULL_NOTICE_INTERVAL. Drops vanish when their time is up or
## their chunk unloads.
# ponytail: drops are not saved; a restart or an unloaded chunk loses them.
func _tick_drops(delta: float) -> void:
	var t := Content.tuning
	for id: int in drops.keys():
		var drop: SimDrop = drops[id]
		var loaded := chunks.has(WorldGen.chunk_of(drop.position)) or _run_at(drop.position)
		if time >= drop.until or not loaded:
			drops.erase(id)
			continue
		var player: SimPlayer = players.get(nearest_player(drop.position, t.magnet_radius))
		if player == null:
			continue
		drop.position = drop.position.move_toward(player.position, t.magnet_speed * delta)
		if drop.position.distance_to(player.position) > t.pickup_radius:
			continue
		if drop.buff != &"":
			# One at max stacks leaves the orb for someone else.
			if player.buffs.add(drop.buff):
				drops.erase(id)
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
			player.position = _respawn_point(player)
			# Death inside a run takes back what was found there, and leaves it at the entrance.
			if player.run:
				player.position = Content.tuning.dungeon_entrance
				_leave_run(player, true)
			player.health = player.max_health()
			player.stamina = Content.tuning.max_stamina
			player.hunger = maxf(player.hunger, Content.tuning.respawn_hunger)
			player.moved_at = time
			events.append(["respawn", player.id, player.position])
		return
	var t := Content.tuning
	if player.open_chest != null and not _chest_in_reach(player, player.open_chest):
		_close_chest(player)
	player.hunger = maxf(player.hunger - t.hunger_drain * delta, 0.0)
	var regen := t.stamina_regen * (1.0 + player.buffs.stat("stamina_regen"))
	if player.regen_left > 0:
		var span := minf(delta, player.regen_left)
		player.regen_left -= span
		player.heal(player.regen * span)
	if player.hunger > 0:
		player.health = minf(player.health + t.health_regen * delta, player.max_health())
	else:
		regen *= t.starve_stamina
		player.health = maxf(player.health - t.starve_damage * delta, 0.0)
		if player.health == 0:
			_die(player)
	if time - player.stamina_used_at >= t.stamina_delay:
		player.stamina = minf(player.stamina + regen * delta, t.max_stamina)


## Dead until respawn_delay is up. In the overworld its inventory slots stay behind in a grave
## (a run takes back its snapshot on respawn instead).
func _die(player: SimPlayer) -> void:
	player.regen_left = 0.0
	player.dead_until = time + Content.tuning.respawn_delay
	if player.run == null:
		_add_grave(player)


## Moves a player's inventory slots (not what it wears) into a new grave where it stands, unless
## they are empty. A grave already lying elsewhere stays as it is.
func _add_grave(player: SimPlayer) -> void:
	var grave := SimGrave.new()
	var empty := true
	for i in player.inventory.slots.size():
		if not player.inventory.slots[i].is_empty():
			grave.items.slots[i] = player.inventory.slots[i]
			player.inventory.slots[i] = {}
			empty = false
	if empty:
		return
	player.inventory.changed = true
	grave.owner = player.name
	grave.position = player.position
	var coord := WorldGen.chunk_of(grave.position)
	if not chunks.has(coord):
		_load_chunk(coord)
	_place_grave(chunks[coord], grave)
	chunks[coord].dirty = true
	player.graves.append(grave.position)
	events.append(["grave", coord, grave.id])
	events.append(["graves", player.id])


func _place_grave(chunk: SimChunk, grave: SimGrave) -> void:
	grave.id = _next_grave_id
	_next_grave_id += 1
	chunk.graves[grave.id] = grave
	graves[grave.id] = grave


## The owner's grave closest to at within reach, null if none.
func own_grave(player_name: String, at: Vector2, reach: float) -> SimGrave:
	var best: SimGrave = null
	for grave: SimGrave in graves.values():
		var distance := grave.position.distance_to(at)
		if grave.owner == player_name and distance <= reach:
			if best == null or distance < best.position.distance_to(at):
				best = grave
	return best


## Takes what fits of a grave back into its owner's inventory; an emptied grave is gone. Returns
## whether anything was taken.
func _loot_grave(player: SimPlayer, grave: SimGrave) -> bool:
	var took := false
	for slot in grave.items.slots:
		if slot.is_empty():
			continue
		var left := player.inventory.add(slot.item, slot.count)
		if left < slot.count:
			events.append(["loot", player.id, slot.item, slot.count - left])
			took = true
		slot.count = left
		if left == 0:
			slot.clear()
	var coord := WorldGen.chunk_of(grave.position)
	chunks[coord].dirty = true
	if grave.items.slots.all(func(slot: Dictionary) -> bool: return slot.is_empty()):
		chunks[coord].graves.erase(grave.id)
		graves.erase(grave.id)
		for i in player.graves.size():
			if player.graves[i].is_equal_approx(grave.position):
				player.graves.remove_at(i)
				break
		events.append(["graves", player.id])
	events.append(["grave", coord, grave.id])
	if not took:
		events.append(["full", player.id])
	return took


## The tile center of the player's bed if it still stands, else the spawn (and the bed is
## forgotten). The bed's chunk is loaded for the check if no one is near it.
func _respawn_point(player: SimPlayer) -> Vector2:
	if player.bed != null:
		var coord := Building.chunk_of_tile(player.bed)
		if not chunks.has(coord):
			_load_chunk(coord)
		var piece: Building.Piece = pieces.get(player.bed)
		if piece and piece.def().bed:
			return Building.tile_center(player.bed)
		player.bed = null
	return Content.tuning.respawn_at


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
		if player.dead_until > 0 or player.run:
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
		if Building.blocker(pieces, at) != null:
			continue
		var kind := _pick_kind(Survival.is_night(time))
		var members := rng.randi_range(kind.pack_min, kind.pack_max)
		var pack := _next_pack_id if members > 1 else 0
		_next_pack_id += 1 if members > 1 else 0
		for i in members:
			var enemy := add_enemy(
				at + Vector2.from_angle(rng.randf() * TAU) * (0.0 if i == 0 else PACK_SPREAD),
				kind.health * scale.health * night.health,
				kind.damage * scale.damage * night.damage,
				kind
			)
			enemy.speed *= night.speed
			enemy.pack = pack


## A kind for the overworld spawner to add, by the weights of Content.enemies for day or night.
func _pick_kind(night: bool) -> EnemyDef:
	if spawn_kind:
		return spawn_kind
	var total := 0.0
	for kind: EnemyDef in Content.enemies.values():
		total += kind.spawn_weight_night if night else kind.spawn_weight_day
	if total <= 0.0:
		return Content.tuning.enemy
	var roll := rng.randf() * total
	for id in Content.enemy_ids:
		var kind: EnemyDef = Content.enemies[id]
		roll -= kind.spawn_weight_night if night else kind.spawn_weight_day
		if roll < 0.0:
			return kind
	return Content.tuning.enemy


## An exploder's blast: everyone and every piece within its slam_radius takes its damage, and
## it dies without dropping anything.
func explode(enemy: SimEnemy) -> void:
	var radius := enemy.def.slam_radius
	for player: SimPlayer in players.values():
		if player.position.distance_to(enemy.position) <= radius:
			damage_player(player.id, enemy.damage, enemy)
	for tile: Vector2i in pieces.keys():
		if Building.tile_center(tile).distance_to(enemy.position) <= radius:
			damage_piece(tile, enemy.damage)
	events.append(["enemy", enemy.id, Net.EnemyEvent.DIED, enemy.position])
	enemies.erase(enemy.id)


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
		if player.run:
			continue
		var center := WorldGen.chunk_of(player.position)
		for coord in WorldGen.around(center, VIEW_CHUNKS + 1):
			keep[coord] = true
		for coord in WorldGen.around(center, VIEW_CHUNKS):
			if not chunks.has(coord):
				_load_chunk(coord)
	for coord: Vector2i in chunks.keys():
		# Without a store a grave would be gone for good, so its chunk stays (tests, balance sim).
		if keep.has(coord) or (store == null and not chunks[coord].graves.is_empty()):
			continue
		_save_chunk(coord)
		for tile: Vector2i in chunks[coord].pieces:
			pieces.erase(tile)
			pieces_version += 1
		for id: int in chunks[coord].graves:
			graves.erase(id)
		chunks.erase(coord)


func _load_chunk(coord: Vector2i) -> void:
	var chunk := SimChunk.new()
	chunk.props = WorldGen.chunk(world_seed, coord).props
	chunks[coord] = chunk
	if store == null:
		return
	var saved := store.load_chunk(coord)
	for id in saved.removed:
		chunk.removed[id] = true
	for entry: Dictionary in saved.pieces:
		var id := StringName(entry.get("id", ""))
		if Content.piece(id) == null:
			continue  # a piece this build doesn't know any more
		var piece := Building.Piece.new(id)
		piece.health = minf(float(entry.get("hp", piece.health)), piece.health)
		piece.open = bool(entry.get("open", false))
		if piece.items:
			piece.items.load_data(entry.get("items", {}))
		var tile := Building.tile_at(coord, int(entry.get("t", 0)))
		chunk.pieces[tile] = piece
		pieces[tile] = piece
		pieces_version += 1
	for entry: Dictionary in saved.graves:
		var grave := SimGrave.new()
		grave.owner = str(entry.get("owner", ""))
		grave.position = Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		grave.items.load_data(entry.get("items", {}))
		_place_grave(chunk, grave)


func _save_chunk(coord: Vector2i) -> void:
	var chunk: SimChunk = chunks[coord]
	if store == null or not chunk.dirty:
		return
	var saved := []
	for tile: Vector2i in chunk.pieces:
		var piece: Building.Piece = chunk.pieces[tile]
		var entry := {t = Building.index_in_chunk(tile), id = str(piece.id), hp = piece.health}
		if piece.open:
			entry.open = true
		if piece.items:
			entry.items = piece.items.to_data()
		saved.append(entry)
	var saved_graves := []
	for grave: SimGrave in chunk.graves.values():
		(
			saved_graves
			. append(
				{
					owner = grave.owner,
					x = grave.position.x,
					y = grave.position.y,
					items = grave.items.to_data(),
				}
			)
		)
	store.save_chunk(coord, removed_props(coord), saved, saved_graves)
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


## Inside a run, as if it had died there: at the entrance with the snapshot, so a crash or a
## restart never leaves anyone in an instance that is gone or keeps what they found in it.
func _save_player(player: SimPlayer) -> void:
	if store == null:
		return
	var at := Content.tuning.dungeon_entrance if player.run else player.position
	var data := {
		x = at.x,
		y = at.y,
		health = player.health,
		hunger = player.hunger,
		inventory = player.snapshot if player.run else player.inventory.to_data(),
		graves = player.graves.map(func(g: Vector2) -> Array: return [g.x, g.y]),
	}
	if player.bed != null:
		data.bed = [player.bed.x, player.bed.y]
	store.save_player(player.name, data)


## Joins at the saved position of that name with its saved inventory and hunger, or fresh at
## the spawn.
func add_player(id: int, player_name: String) -> SimPlayer:
	var spawn := Vector2(players.size() * SPAWN_SPACING, 0)
	var saved := store.load_player(player_name) if store else {}
	if not saved.is_empty():
		spawn = Vector2(saved.x, saved.y)
	var player := SimPlayer.new(id, player_name, spawn, time)
	player.inventory.load_data(saved.get("inventory", {}))
	for g: Array in saved.get("graves", []):
		player.graves.append(Vector2(g[0], g[1]))
	var bed: Array = saved.get("bed", [])
	if bed.size() == 2:
		player.bed = Vector2i(int(bed[0]), int(bed[1]))
	# Someone who left while dead comes back alive.
	var health := minf(float(saved.get("health", player.max_health())), player.max_health())
	player.health = health if health > 0 else player.max_health()
	player.hunger = clampf(float(saved.get("hunger", player.hunger)), 0.0, player.hunger)
	if health <= 0:
		player.hunger = maxf(player.hunger, Content.tuning.respawn_hunger)
	players[id] = player
	return player


## Leaving the game inside a run counts as dying there, without the wait.
func remove_player(id: int) -> void:
	var player: SimPlayer = players.get(id)
	if player == null:
		return
	if player.run:
		player.position = Content.tuning.dungeon_entrance
		_leave_run(player, true)
	_save_player(player)
	players.erase(id)


func is_online(player_name: String) -> bool:
	return players.values().any(func(p: SimPlayer) -> bool: return p.name == player_name)


## Client-authoritative movement with a basic sanity check: a move further than the walk speed
## allows (plus slack, plus a dash's distance right after one) is a teleport and is dropped, as
## are moves of the dead and moves into a blocking piece. Returns whether it was accepted.
# ponytail: no correction sent back; a dropped move only holds the server copy until the next one.
func move_player(id: int, position: Vector2) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0:
		return false
	var t := Content.tuning
	var speed := t.walk_speed * (1.0 + player.buffs.stat("move_speed"))
	var allowed := speed * (time - player.moved_at + MOVE_SLACK)
	if time - player.dashed_at <= t.dash_time + MOVE_SLACK:
		allowed += t.dash_distance
	if player.position.distance_to(position) > allowed:
		return false
	if player.run and Dungeon.clamp_to(player.run.area, position) != position:
		return false
	if not Building.can_walk(pieces, player.position, position):
		return false
	player.position = position
	player.moved_at = time
	return true


## E at one of its own graves, the dungeon entrance, a run's exit or its end chest. At a grave it
## takes back what fits (_loot_grave). A living player at the entrance
## goes into a run, the one opened within dungeon_join_window or a new one, and its inventory is
## snapshotted; at its run's exit it goes back to the entrance with everything found inside; at
## the chest, once no enemy is near it, it opens it once for itself and the chest_drops spill
## out. Returns whether it did any of that.
func interact(id: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0:
		return false
	if player.run == null:
		var grave := own_grave(player.name, player.position, REACH + REACH_SLACK)
		if grave:
			return _loot_grave(player, grave)
	return _use_portal(player)


## interact at the dungeon entrance, a run's exit or its end chest.
func _use_portal(player: SimPlayer) -> bool:
	var id := player.id
	var t := Content.tuning
	var reach := t.portal_reach + REACH_SLACK
	var run := player.run
	if run and player.position.distance_to(run.chest) <= reach:
		if run.opened.has(id) or Dungeon.locked(run.chest, _enemy_positions()):
			return false
		run.opened[id] = true
		_drop_loot(t.chest_drops, run.chest)
		events.append(["chest", id])
		return true
	var portal := run.exit if run else t.dungeon_entrance
	if player.position.distance_to(portal) > reach:
		return false
	if run:
		player.position = t.dungeon_entrance
		_leave_run(player, false)
		return true
	for open: Dungeon in dungeons.values():
		if time - open.opened_at <= t.dungeon_join_window:
			run = open
	if run == null:
		run = _open_run()
	run.players[id] = true
	player.run = run
	player.snapshot = player.inventory.to_data()
	player.position = run.spawn + Vector2(0, (run.players.size() - 1) * SPAWN_SPACING)
	player.position = Dungeon.clamp_to(run.area, player.position)
	player.moved_at = time
	events.append(["dungeon", id, run.area, run.exit, run.chest, player.position])
	return true


## The closest enemy within radius of a position, null if none.
func nearest_enemy(at: Vector2, radius: float) -> SimEnemy:
	var best: SimEnemy = null
	for enemy: SimEnemy in enemies.values():
		var distance := enemy.position.distance_to(at)
		if distance <= radius and (best == null or distance < best.position.distance_to(at)):
			best = enemy
	return best


func _enemy_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for enemy: SimEnemy in enemies.values():
		out.append(enemy.position)
	return out


## The run whose slot holds a position, null in the overworld.
func _run_at(at: Vector2) -> Dungeon:
	if at.y < Dungeon.ORIGIN.y:
		return null
	for run: Dungeon in dungeons.values():
		if run.owns(at):
			return run
	return null


## A run in the lowest free slot, with a new layout.
func _open_run() -> Dungeon:
	var slot := 0
	while dungeons.has(slot):
		slot += 1
	var run := Dungeon.new(slot, time, rng)
	dungeons[slot] = run
	return run


## Spawns the enemies of each room a living player has walked into for the first time, in
## number and strength scaled by the players near it, in strength by its depth and the minutes
## the run has been open; the end room also wakes the boss at the chest. Once every enemy of
## the rooms woken so far is dead, the living inside heal room_clear_heal of their max health.
func _wake_rooms(run: Dungeon) -> void:
	if (
		run.cleared < run.reached
		and not enemies.values().any(func(enemy: SimEnemy) -> bool: return run.owns(enemy.position))
	):
		run.cleared = run.reached
		for id: int in run.players:
			if players[id].dead_until == 0:
				players[id].heal(players[id].max_health() * Content.tuning.room_clear_heal)
	var deepest := run.reached
	for id: int in run.players:
		if players[id].dead_until == 0:
			deepest = maxi(deepest, run.room_of(players[id].position))
	var kind := Content.tuning.dungeon_enemy
	while run.reached < deepest:
		run.reached += 1
		var room := run.rooms[run.reached]
		var scale := Combat.dungeon_scaled(
			run.reached, run.minutes(time), players_near(room.get_center())
		)
		# More players bring more enemies, from the same spawn points, each a step aside.
		var spawns := run.defs[run.reached].spawns
		for i in roundi(spawns.size() * scale.count):
			var aside := floorf(float(i) / spawns.size()) * 16.0
			var at := room.position + spawns[i % spawns.size()] + Vector2(aside, 0)
			add_enemy(
				Dungeon.clamp_to(run.area, at),
				kind.health * scale.health,
				kind.damage * scale.damage,
				kind
			)
		if run.reached == run.rooms.size() - 1:
			var boss := Content.tuning.dungeon_boss
			add_enemy(run.chest, boss.health * scale.health, boss.damage * scale.damage, boss)


## Out of its run, at the position already set, without its buffs; restore puts back the
## inventory from entering.
## The last one out closes the run and clears its enemies and drops.
func _leave_run(player: SimPlayer, restore: bool) -> void:
	var run := player.run
	if restore:
		player.inventory.load_data(player.snapshot)
	player.buffs.clear()
	player.health = minf(player.health, player.max_health())
	run.players.erase(player.id)
	player.run = null
	player.snapshot = {}
	player.moved_at = time
	events.append(
		["dungeon", player.id, [] as Array[Rect2], Vector2.ZERO, Vector2.ZERO, player.position]
	)
	if not run.players.is_empty():
		return
	dungeons.erase(run.slot)
	for id: int in enemies.keys():
		if run.owns(enemies[id].position):
			enemies.erase(id)
	for id: int in drops.keys():
		if run.owns(drops[id].position):
			drops.erase(id)


## Picks up a stick or pebble the player stands next to, at most one per gather_time; trees and
## rocks are swung at instead (attack). Returns whether it was picked up.
func remove_prop(id: int, coord: Vector2i, prop_id: int) -> bool:
	return Gathering.pick_up(self, id, coord, prop_id)


## Crafts a recipe with the station pieces near the player.
func craft(id: int, recipe: StringName) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null:
		return false
	return Crafting.craft(player, recipe, Building.stations_near(pieces, player.position))


## Builds a piece on a tile in a loaded chunk, paid from the player's inventory (see
## Building.can_build), or repairs the same piece there if it is damaged and no enemy is within
## repair_lock_radius. Nothing is built inside a run. Returns whether it did either.
func build(id: int, tile: Vector2i, piece_id: StringName) -> bool:
	var player: SimPlayer = players.get(id)
	var chunk: SimChunk = chunks.get(Building.chunk_of_tile(tile))
	var def := Content.piece(piece_id)
	if player == null or chunk == null or def == null or player.dead_until > 0 or player.run:
		return false
	var index := Building.index_in_chunk(tile)
	var prop: bool = chunk.props.has(index) and not chunk.removed.has(index)
	var bodies := _enemy_positions()
	for other: SimPlayer in players.values():
		if other.dead_until == 0:
			bodies.append(other.position)
	match Building.can_build(
		pieces, tile, piece_id, player.inventory, player.position, prop, bodies, REACH_SLACK
	):
		Building.Status.REPAIR:
			var radius := Content.tuning.repair_lock_radius
			if nearest_enemy(Building.tile_center(tile), radius) != null:
				return false
			pieces[tile].health = def.health
		Building.Status.OK:
			player.inventory.take(def.cost)
			var piece := Building.Piece.new(piece_id)
			chunk.pieces[tile] = piece
			pieces[tile] = piece
			pieces_version += 1
		_:
			return false
	chunk.dirty = true
	events.append(["piece", tile])
	return true


## Takes down a piece in reach and gives its cost back (what doesn't fit drops on the ground,
## as does a chest's contents). Returns whether it did.
# ponytail: the whole cost back even when damaged; scale it by health if that gets abused.
func unbuild(id: int, tile: Vector2i) -> bool:
	var player: SimPlayer = players.get(id)
	var piece: Building.Piece = pieces.get(tile)
	if player == null or piece == null or player.dead_until > 0:
		return false
	var reach := Content.tuning.build_reach + REACH_SLACK
	if player.position.distance_to(Building.tile_center(tile)) > reach:
		return false
	var cost := piece.def().cost
	for item: StringName in cost:
		var left := player.inventory.add(item, cost[item])
		if left > 0:
			add_drop(item, left, Building.tile_center(tile))
	_remove_piece(tile)
	return true


## E on a door opens or shuts it (not shut on someone standing in it), on a chest opens it for
## the player, on a bed makes it the player's respawn point. Returns whether it did.
func use_piece(id: int, tile: Vector2i) -> bool:
	var player: SimPlayer = players.get(id)
	var piece: Building.Piece = pieces.get(tile)
	if player == null or piece == null or player.dead_until > 0:
		return false
	if player.position.distance_to(Building.tile_center(tile)) > REACH + REACH_SLACK:
		return false
	if piece.def().door:
		if piece.open:
			var bodies := _enemy_positions()
			for other: SimPlayer in players.values():
				bodies.append(other.position)
			if bodies.any(func(at: Vector2) -> bool: return Building.overlaps(tile, at)):
				return false
		piece.open = not piece.open
		pieces_version += 1
		chunks[Building.chunk_of_tile(tile)].dirty = true
		events.append(["piece", tile])
		return true
	if piece.items:
		player.open_chest = tile
		events.append(["storage", id, piece.items.to_data()])
	elif piece.def().bed:
		player.bed = tile
		events.append(["bed", id])
	else:
		return false
	return true


## Moves a whole stack between the player's inventory and its open chest, from_chest says
## which way, as much of it as fits. Returns whether anything moved.
# ponytail: whole stacks by click; drag and drop between the two comes when it is missed.
func chest_move(id: int, from_chest: bool, index: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.open_chest == null or player.dead_until > 0:
		return false
	var tile: Vector2i = player.open_chest
	var chest: Inventory = pieces[tile].items
	var from := chest if from_chest else player.inventory
	var to := player.inventory if from_chest else chest
	if index < 0 or index >= from.slots.size() or from.slots[index].is_empty():
		return false
	var slot := from.slots[index]
	var moved: int = slot.count - to.add(slot.item, slot.count)
	if moved == 0:
		return false
	from.take_at(index, moved)
	chunks[Building.chunk_of_tile(tile)].dirty = true
	for other: SimPlayer in players.values():
		if other.open_chest == tile:
			events.append(["storage", other.id, chest.to_data()])
	return true


## An enemy hit on a piece; at 0 health it is gone and a chest's contents spill out.
func damage_piece(tile: Vector2i, amount: float) -> void:
	var piece: Building.Piece = pieces.get(tile)
	if piece == null:
		return
	piece.health -= amount
	if piece.health <= 0:
		_remove_piece(tile)
		return
	chunks[Building.chunk_of_tile(tile)].dirty = true
	events.append(["piece", tile])


## The tile of a piece blocking a body at at, null if none does.
func blocker(at: Vector2) -> Variant:
	return Building.blocker(pieces, at)


## Pathing.blocked_tiles of the loaded pieces, kept until pieces_version changes.
func blocked_tiles() -> Dictionary:
	if _blocked_version != pieces_version:
		_blocked = Pathing.blocked_tiles(pieces)
		_blocked_version = pieces_version
	return _blocked


func _remove_piece(tile: Vector2i) -> void:
	var piece: Building.Piece = pieces[tile]
	if piece.items:
		for slot in piece.items.slots:
			if not slot.is_empty():
				add_drop(slot.item, slot.count, Building.tile_center(tile))
		for player: SimPlayer in players.values():
			if player.open_chest == tile:
				_close_chest(player)
	var chunk: SimChunk = chunks[Building.chunk_of_tile(tile)]
	chunk.pieces.erase(tile)
	chunk.dirty = true
	pieces.erase(tile)
	pieces_version += 1
	events.append(["piece", tile])


func _chest_in_reach(player: SimPlayer, tile: Vector2i) -> bool:
	var reach := Content.tuning.build_reach + REACH_SLACK
	return pieces.has(tile) and player.position.distance_to(Building.tile_center(tile)) <= reach


func _close_chest(player: SimPlayer) -> void:
	player.open_chest = null
	events.append(["storage", player.id, {}])


## A light or heavy swing toward aim. The client reports the enemies it saw hit (PLAN §4.4); the
## server checks them against its own copy with some slack. The equipped weapon decides the
## swing, buffs make it stronger, faster, critical, bleeding or healing. Returns the enemies
## damaged, empty if the swing itself was refused (dead, cooling down, out of stamina).
func attack(id: int, heavy: bool, aim: Vector2, hits: PackedInt32Array) -> PackedInt32Array:
	var player: SimPlayer = players.get(id)
	var damaged := PackedInt32Array()
	if player == null:
		return damaged
	var move := Content.attack(player.inventory.weapon(), heavy)
	if time < player.cooldown_until or not _spend(player, move.cost):
		return damaged
	var b := player.buffs
	player.cooldown_until = time + Combat.cooldown(move, b)
	events.append(["swing", id, heavy, aim, player.position, player.inventory.weapon()])
	var t := Content.tuning
	var reach := move.reach + t.hit_slack
	var arc := move.arc + t.arc_slack
	var damage := Combat.swing_damage(move, heavy, b)
	var crit := b.stat("crit")
	for enemy_id in hits:
		var enemy: SimEnemy = enemies.get(enemy_id)
		if enemy == null or not Combat.in_arc(player.position, aim, enemy.position, reach, arc):
			continue
		# Rolled only with a crit buff, so runs without buffs draw the same numbers.
		var dealt := damage * (2.0 if crit > 0 and rng.randf() < crit else 1.0)
		enemy.provoke(id)
		if enemy.blocks(player.position) and move.poise_damage < enemy.def.block_break:
			events.append(["enemy", enemy.id, Net.EnemyEvent.BLOCK, enemy.position])
			damaged.append(enemy.id)
			_hurt_enemy(enemy, dealt * enemy.def.block_pass, player, false)
			continue
		enemy.push((enemy.position - player.position).normalized(), move.knock)
		damaged.append(enemy.id)
		_land_hit(enemy, dealt, player, move.poise_damage)
	if damaged.is_empty():
		Gathering.swing(self, player, aim, reach, arc, move.cost)
	return damaged


## Eats the food in an inventory slot (-1: the first food) for a player. Cooked food also
## starts a regeneration, which the client is told of. Returns whether it was eaten.
func eat(id: int, index: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or not player.eat(index):
		return false
	if player.regen_left > 0:
		events.append(["status", id, Net.Status.REGEN, player.regen_left])
	return true


## Drinks the first healing draught for a player, unless it is cooling down. Returns whether it
## did.
func use_draught(id: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0 or time < player.draught_ready_at:
		return false
	var index := player.inventory.first_draught()
	if index == -1:
		return false
	player.heal(Content.item(player.inventory.slots[index].item).heal)
	player.inventory.take_at(index, 1)
	player.draught_ready_at = time + Content.tuning.draught_cooldown
	events.append(["status", id, Net.Status.DRAUGHT, Content.tuning.draught_cooldown])
	return true


## The ability of the worn rune toward aim, unless it is cooling down or there is not the
## stamina for it. Returns whether it was used.
func use_ability(id: int, aim: Vector2) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0 or time < player.ability_ready_at:
		return false
	var def := player.inventory.ability()
	if def == null or not _spend(player, def.stamina_cost):
		return false
	player.ability_ready_at = time + def.cooldown
	events.append(["status", id, Net.Status.ABILITY, def.cooldown])
	var damage := def.damage * (1.0 + player.buffs.stat("damage"))
	match def.kind:
		AbilityDef.Kind.FROST_BOLT:
			var bolt := add_projectile(
				SimProjectile.Team.PLAYERS,
				id,
				player.position,
				aim if aim != Vector2.ZERO else Vector2.RIGHT,
				def.speed,
				damage,
				def.range
			)
			bolt.slow = def.slow
			bolt.slow_time = def.slow_time
			bolt.magic = true
		AbilityDef.Kind.WARD:
			var ward := SimWard.new()
			ward.id = _next_ward_id
			_next_ward_id += 1
			ward.position = player.position
			ward.radius = def.radius
			ward.heal_per_second = def.heal_per_second
			ward.until = time + def.duration
			wards[ward.id] = ward
			events.append(["effect", def.kind, ward.position, def.radius, def.duration])
		AbilityDef.Kind.SHOCKWAVE:
			for enemy: SimEnemy in enemies.values():
				var offset := enemy.position - player.position
				if offset.length() > def.radius:
					continue
				enemy.provoke(id)
				enemy.push(
					offset.normalized() if offset != Vector2.ZERO else Vector2.RIGHT, def.knock
				)
				_land_hit(enemy, damage, player, def.poise_damage)
			events.append(["effect", def.kind, player.position, def.radius, 0.4])
	return true


## Heals the players standing in a ward; a ward is gone when its time is up.
func _tick_wards(delta: float) -> void:
	for ward: SimWard in wards.values():
		if time >= ward.until:
			wards.erase(ward.id)
			continue
		for player: SimPlayer in players.values():
			if player.dead_until == 0 and player.position.distance_to(ward.position) <= ward.radius:
				player.heal(ward.heal_per_second * delta)


## A player's hit that got through, by a swing, an arrow or a rune: by's lifesteal heals them
## and their bleed starts on the enemy, it takes the damage (kill buffs in _hurt_enemy), then,
## if still alive, the poise damage (after, so a killing blow that would stagger an exploder
## out of its windup still sets it off).
func _land_hit(enemy: SimEnemy, dealt: float, by: SimPlayer, poise_damage: float) -> void:
	if by:
		by.heal(dealt * by.buffs.stat("lifesteal"))
		if by.buffs.stat("bleed") > 0:
			enemy.bleed_dps = by.buffs.stat("bleed")
			enemy.bleed_until = time + Content.tuning.bleed_time
			enemy.bleed_by = by.id
	if not _hurt_enemy(enemy, dealt, by):
		enemy.hit_poise(self, poise_damage)


## Takes health off an enemy, with a damage number if shown. One that dies drops its loot,
## inside a run maybe a buff orb (rarer the deeper the run has gone), and feeds by's kill
## buffs; an exploder killed in its windup blows up as it dies. Returns whether it died.
func _hurt_enemy(enemy: SimEnemy, amount: float, by: SimPlayer, shown := true) -> bool:
	enemy.health -= amount
	if shown:
		events.append(["hit", true, enemy.id, amount, enemy.position, enemy.pushed()])
	if enemy.health > 0 or not enemies.has(enemy.id):
		return false
	if enemy.def.behavior == EnemyDef.Behavior.EXPLODER and enemy.state == SimEnemy.State.WINDUP:
		explode(enemy)
	else:
		events.append(["enemy", enemy.id, Net.EnemyEvent.DIED, enemy.position])
		enemies.erase(enemy.id)
	_drop_loot(enemy.def.drops, enemy.position)
	var run := _run_at(enemy.position)
	if run and rng.randf() < Content.tuning.buff_chance:
		_add_orb(Buffs.roll(rng, run.reached * Content.tuning.buff_depth_bonus), enemy.position)
	if by:
		by.heal(by.buffs.stat("kill_heal"), by.buffs.stat("kill_stamina"))
	return true


func _add_orb(buff: StringName, at: Vector2) -> SimDrop:
	var drop := add_drop(&"", 0, at)
	drop.buff = buff
	return drop


## A shot from the bow in a player's hands, toward aim, drawn (0..1) of its draw_time. The
## client holds the button for the draw: the server only checks that the time since the last
## shot allows it (with draw_slack), and takes the arrow and stamina. Arrow damage, speed
## and range scale with the draw. Returns whether an arrow flew.
func shoot(id: int, aim: Vector2, drawn: float) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0 or aim == Vector2.ZERO:
		return false
	var bow := Content.item(player.inventory.weapon())
	if bow == null or bow.ammo == &"" or not player.inventory.has_all({bow.ammo: 1}):
		return false
	var share := clampf(drawn, 0.0, 1.0)
	var t := Content.tuning
	if share < bow.min_draw or time - player.shot_at < bow.draw_time * share * t.draw_slack:
		return false
	if not _spend(player, bow.draw_cost):
		return false
	player.inventory.take({bow.ammo: 1})
	player.shot_at = time
	var b := player.buffs
	var damage := bow.arrow_damage * share * (1.0 + b.stat("damage"))
	# Rolled only with a crit buff, so runs without buffs draw the same numbers.
	if b.stat("crit") > 0 and rng.randf() < b.stat("crit"):
		damage *= 2.0
	var arrow := add_projectile(
		SimProjectile.Team.PLAYERS,
		id,
		player.position,
		aim,
		bow.arrow_speed * share,
		damage,
		bow.arrow_range * share
	)
	arrow.knock = bow.arrow_knock * share
	arrow.poise_damage = bow.arrow_poise * share
	return true


## Sends a projectile flying from from toward direction, for a player (team PLAYERS) or an
## enemy (ENEMIES) with that id.
func add_projectile(
	team: SimProjectile.Team,
	owner_id: int,
	from: Vector2,
	direction: Vector2,
	speed: float,
	damage: float,
	max_range: float
) -> SimProjectile:
	var p := SimProjectile.new(
		_next_projectile_id, team, owner_id, from, direction, speed, damage, max_range
	)
	_next_projectile_id += 1
	projectiles[p.id] = p
	return p


## Flies every projectile on, in steps no longer than its hit radius so nothing slips through.
## One ends at the first blocking piece (damaging it if an enemy shot it), at the first body of
## the other team it hurts (a dashing or dead player is passed through), when it leaves a
## dungeon's rooms or when its range is spent.
func _tick_projectiles(delta: float) -> void:
	var radius := Content.tuning.projectile_radius
	for p: SimProjectile in projectiles.values():
		var distance := minf(p.velocity.length() * delta, p.range_left)
		var steps := maxi(ceili(distance / radius), 1)
		var step := p.velocity.normalized() * distance / steps
		var done := distance < 0.001
		for i in steps:
			p.position += step
			if _projectile_hits(p, radius):
				done = true
				break
			var run := _run_at(p.position)
			if run and Dungeon.clamp_to(run.area, p.position) != p.position:
				done = true
				break
		p.range_left -= distance
		if done or p.range_left <= 0.0:
			projectiles.erase(p.id)


## Whether p, at its position, hit something and is spent.
func _projectile_hits(p: SimProjectile, radius: float) -> bool:
	var wall: Variant = blocker(p.position)
	if wall != null:
		if p.team == SimProjectile.Team.ENEMIES:
			damage_piece(wall, p.damage)
		return true
	if p.team == SimProjectile.Team.ENEMIES:
		for player: SimPlayer in players.values():
			if player.position.distance_to(p.position) <= radius:
				if damage_player(player.id, p.damage):
					return true
		return false
	for enemy: SimEnemy in enemies.values():
		if enemy.position.distance_to(p.position) <= radius:
			var shooter: SimPlayer = players.get(p.owner_id)
			enemy.provoke(p.owner_id)
			if not p.magic and enemy.blocks(p.position - p.velocity):
				events.append(["enemy", enemy.id, Net.EnemyEvent.BLOCK, enemy.position])
				_hurt_enemy(enemy, p.damage * enemy.def.block_pass, shooter, false)
				return true
			if p.slow < 1.0:
				enemy.slow = p.slow
				enemy.slow_until = time + p.slow_time
			enemy.push(p.velocity.normalized(), p.knock)
			_land_hit(enemy, p.damage, shooter, p.poise_damage)
			return true
	return false


## Starts a dash: i-frames now, and the next moves may cover its distance. With dash_damage,
## enemies around the player take it.
func dash(id: int) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or time - player.dashed_at < Content.tuning.dash_cooldown:
		return false
	if not _spend(player, Content.tuning.dash_cost):
		return false
	player.dashed_at = time
	var burst := player.buffs.stat("dash_damage")
	if burst > 0:
		for enemy: SimEnemy in enemies.values():
			if enemy.position.distance_to(player.position) <= Content.tuning.dash_burst_radius:
				enemy.provoke(id)
				_hurt_enemy(enemy, burst, player)
	return true


## Spends stamina if the player is alive and has enough.
func _spend(player: SimPlayer, cost: float) -> bool:
	if player.dead_until > 0 or player.stamina < cost:
		return false
	player.stamina -= cost
	player.stamina_used_at = time
	return true


## An enemy hit lands (Combat.hit_player), unless the player is dead or dashing. With thorns,
## the enemy that hit (from) takes them back. Returns whether it landed.
func damage_player(id: int, amount: float, from: SimEnemy = null) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null or player.dead_until > 0 or not Combat.hit_player(self, player, amount, from):
		return false
	var thorns := player.buffs.stat("thorns")
	if from and thorns > 0 and enemies.has(from.id):
		_hurt_enemy(from, thorns, player)
	if player.health == 0:
		_die(player)
	return true


## The pieces of a loaded chunk as sent to clients: [index in chunk, Building.to_net...] each.
func chunk_pieces(coord: Vector2i) -> Array:
	var out := []
	for tile: Vector2i in chunks[coord].pieces:
		out.append([Building.index_in_chunk(tile)] + Building.to_net(pieces[tile]))
	return out


## The graves in a loaded chunk as sent to clients: [id, x, y, owner name] each.
func chunk_graves(coord: Vector2i) -> Array:
	var out := []
	for grave: SimGrave in chunks[coord].graves.values():
		out.append([grave.id, grave.position.x, grave.position.y, grave.owner])
	return out


## Ids of the props removed from a loaded chunk, as sent to clients and saved.
func removed_props(coord: Vector2i) -> PackedInt32Array:
	return PackedInt32Array(chunks[coord].removed.keys())


## The chunks a player sees, none inside a run.
func interest(id: int) -> Array[Vector2i]:
	if players[id].run:
		return []
	return WorldGen.around(WorldGen.chunk_of(players[id].position), VIEW_CHUNKS)


## Whether a position is within a player's view.
func sees(id: int, at: Vector2) -> bool:
	return WorldGen.near(
		WorldGen.chunk_of(at), WorldGen.chunk_of(players[id].position), VIEW_CHUNKS
	)


## What one player's client is sent: {players: {id: Vector3(x, y, health 0..1)}, enemies: the
## same with Net.enemy_z for z, drops: {id: Vector3(x, y, Content.item_index, or -1 - the
## index in Content.buff_ids for a buff orb)}, projectiles: {id: Vector3(x, y, flight angle in
## radians)}, facings: {id: angle in radians} of the enemies with a shield, me: Vector4(health,
## stamina, max health, hunger), time: the world's time for the day/night clock}, with only
## the players (itself included), enemies, drops and projectiles near it.
func snapshot_for(id: int) -> Dictionary:
	var near := {}
	for other: SimPlayer in players.values():
		if sees(id, other.position):
			near[other.id] = Vector3(
				other.position.x, other.position.y, other.health / other.max_health()
			)
	var near_enemies := {}
	var facings := {}
	for enemy: SimEnemy in enemies.values():
		if sees(id, enemy.position):
			if enemy.def.block_arc > 0.0:
				facings[enemy.id] = enemy.facing.angle()
			var health := enemy.health / enemy.max_health
			near_enemies[enemy.id] = Vector3(
				enemy.position.x,
				enemy.position.y,
				Net.enemy_z(Content.enemy_index(enemy.def), health, enemy.slowed(self))
			)
	var near_drops := {}
	for drop: SimDrop in drops.values():
		if sees(id, drop.position):
			var kind := Content.item_index(drop.item)
			if drop.buff != &"":
				kind = -1 - Content.buff_ids.find(drop.buff)
			near_drops[drop.id] = Vector3(drop.position.x, drop.position.y, kind)
	var near_projectiles := {}
	for p: SimProjectile in projectiles.values():
		if sees(id, p.position):
			near_projectiles[p.id] = Vector3(p.position.x, p.position.y, p.velocity.angle())
	var me: SimPlayer = players[id]
	return {
		players = near,
		enemies = near_enemies,
		drops = near_drops,
		projectiles = near_projectiles,
		facings = facings,
		me = Vector4(me.health, me.stamina, me.max_health(), me.hunger),
		time = time,
	}
