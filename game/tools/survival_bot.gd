class_name SurvivalBot
extends RefCounted
## Plays one player of a SimWorld the way a person roughly would, for the balance sim: eats
## when hungry, forages trees when low on food, gathers what the next piece of gear needs,
## crafts it (walking to a workbench, or building one first) and wears it, fights what comes
## near and otherwise wanders. Skill decides how often it dashes out of a telegraphed hit and
## whether it backs off when low on health. It drives the sim through the same calls the server
## makes for a client, so it gets no more than a player could do. It records what happened to it.

## Gear it works toward, in order; it skips what isn't better than what it wears.
const GEAR: Array[StringName] = [
	&"club", &"cloth_tunic", &"stone_axe", &"hide_armor", &"bone_armor", &"bone_sword"
]
## Hand-made tools it makes first, by what they break: sticks and pebbles come off the ground.
const TOOLS := {ItemDef.Tool.AXE: &"pebble_axe", ItemDef.Tool.PICKAXE: &"pebble_pickaxe"}
## Enemies this close are fought.
const ENGAGE := 150.0
## Seconds from a windup's start to the dash at the earliest, when it dodges.
const REACT := 0.2
## Eats below this share of max hunger; forages while carrying less food than FOOD_STOCK.
const EAT_BELOW := 0.5
const FOOD_STOCK := 40.0
## Berries beyond this are made into trail rations.
const SPARE_BERRIES := 12
## Retreats below RETREAT_BELOW of max health, until back over RETREAT_UNTIL: backs off from
## enemies closer than SAFE, gets on with other things further away and only fights what
## comes within CORNERED.
const RETREAT_BELOW := 0.35
const RETREAT_UNTIL := 0.6
const SAFE := 250.0
const CORNERED := 40.0
## Seconds it keeps one wandering direction.
const WANDER_TIME := 20.0
## Wanders back toward the spawn when further than this.
const WANDER_RANGE := 1500.0

var world: SimWorld
var id: int
## Chance to dash out of a telegraphed hit aimed at it, 0..1.
var dodge := 0.5
## Backs off to heal when low.
var retreats := false

## Seconds spent per activity: fight, forage, gather, craft, retreat, wander, dead.
var time_in := {}
var deaths_by_enemy := 0
var deaths_by_hunger := 0
var deaths_at_night := 0
var damage_day := 0.0
var damage_night := 0.0
var hits_taken := 0
var dodged := 0
var kills := 0
var starving := 0.0
var food_eaten := 0.0
var lowest_health := 1.0
## Sum over time of the enemies within ENGAGE, for the average crowd it faces.
var crowd := 0.0
var alive := 0.0
## item id -> sim time it was crafted first.
var crafted_at := {}

var _rng := RandomNumberGenerator.new()
## Sim times to dash at, for the windups it decided to dodge, and the way each dash goes
## (zero: away from the nearest enemy).
var _dash_at: Array[float] = []
var _dash_way: Array[Vector2] = []
var _retreating := false
var _wander := Vector2.RIGHT
var _wander_until := 0.0
var _was_dead := false
var _hit_this_tick := false


func _init(sim: SimWorld, player_id: int, seed_value: int) -> void:
	world = sim
	id = player_id
	_rng.seed = seed_value


func player() -> SimWorld.SimPlayer:
	return world.players[id]


## Reads what the last world tick did to it. Call after every world.tick, before the events
## are cleared.
func observe(delta: float) -> void:
	var me := player()
	_hit_this_tick = false
	for event in world.events:
		if event[0] == "hit" and not event[1] and event[2] == id:
			_hit_this_tick = true
			hits_taken += 1
			if Survival.is_night(world.time):
				damage_night += event[3]
			else:
				damage_day += event[3]
		elif event[0] == "windup" and _targets_me(event[1]):
			if _rng.randf() < dodge:
				_plan_dash(event)
	var dead := me.dead_until > 0
	if dead and not _was_dead:
		if me.hunger <= 0 and not _hit_this_tick:
			deaths_by_hunger += 1
		else:
			deaths_by_enemy += 1
		if Survival.is_night(world.time):
			deaths_at_night += 1
		_dash_at.clear()
		_dash_way.clear()
		_retreating = false
	_was_dead = dead
	if not dead:
		alive += delta
		for enemy: SimEnemy in world.enemies.values():
			if enemy.position.distance_to(me.position) <= ENGAGE:
				crowd += delta
		lowest_health = minf(lowest_health, me.health / me.max_health())
		if me.hunger <= 0:
			starving += delta


## Decides and does one step of play.
func act(delta: float) -> void:
	var me := player()
	if me.dead_until > 0:
		_spend("dead", delta)
		return
	if _dodge():
		_spend("fight", delta)
		return
	_eat()
	var health := me.health / me.max_health()
	if retreats and health < RETREAT_BELOW:
		_retreating = true
	elif health > RETREAT_UNTIL:
		_retreating = false
	var enemy := _nearest_enemy()
	var distance := enemy.position.distance_to(me.position) if enemy else INF
	if _retreating and distance < SAFE:
		_spend("retreat", delta)
		_walk_to(me.position + (me.position - enemy.position).normalized() * 100, delta)
		return
	if distance <= (CORNERED if _retreating else ENGAGE):
		_spend("fight", delta)
		_fight(enemy, delta)
		return
	if _craft(delta):
		_spend("craft", delta)
		return
	var has_axe := player().inventory.best_tool(ItemDef.Tool.AXE) != null
	if has_axe and _food_carried() < FOOD_STOCK and _gather(WorldGen.Prop.TREE, delta):
		_spend("forage", delta)
	else:
		_provide(delta)


## Forages, gathers for gear or, with nothing to do, wanders.
func _provide(delta: float) -> void:
	var need := _needed_prop()
	if need != -1:
		_spend("gather", delta)
		if _gather(need, delta):
			return
	_spend("wander", delta)
	_wander_step(delta)


func _spend(activity: String, delta: float) -> void:
	time_in[activity] = time_in.get(activity, 0.0) + delta


## Its windup is aimed at this bot, or is a slam that reaches it.
func _targets_me(enemy_id: int) -> bool:
	var enemy: SimEnemy = world.enemies.get(enemy_id)
	if enemy == null:
		return false
	if enemy.def.slam_radius > 0:
		return enemy.position.distance_to(player().position) <= enemy.def.slam_radius
	return enemy.target == id


## Plans the dash for a windup event. A hit lands as the telegraph ends, so the i-frames are
## timed to cover it even on a long windup; an arrow line is sidestepped, and the dash is timed
## to the arrow's arrival.
func _plan_dash(event: Array) -> void:
	var at: float = world.time + maxf(REACT, event[3] - Content.tuning.iframes)
	var way := Vector2.ZERO
	var line: Vector2 = event[5]
	if line != Vector2.ZERO:
		var enemy: SimEnemy = world.enemies[event[1]]
		var flight := enemy.position.distance_to(player().position) / enemy.def.arrow_speed
		at = world.time + event[3] + flight - Content.tuning.iframes / 2
		way = line.orthogonal()
	_dash_at.append(at)
	_dash_way.append(way)


## Dashes away from the nearest enemy (or the way planned) when a planned dodge is due.
func _dodge() -> bool:
	var next := -1
	for i in _dash_at.size():
		if world.time >= _dash_at[i] and (next == -1 or _dash_at[i] < _dash_at[next]):
			next = i
	if next == -1:
		return false
	var way := _dash_way[next]
	_dash_at.remove_at(next)
	_dash_way.remove_at(next)
	var me := player()
	if not world.dash(id):
		return false
	dodged += 1
	if way == Vector2.ZERO:
		var enemy := _nearest_enemy()
		way = (me.position - enemy.position).normalized() if enemy else Vector2.RIGHT
	world.move_player(id, me.position + way * Content.tuning.dash_distance)
	return true


func _eat() -> void:
	var me := player()
	if me.hunger >= Content.tuning.max_hunger * EAT_BELOW:
		return
	var index := me.inventory.first_food()
	if index == -1:
		return
	var food := Content.item(me.inventory.slots[index].item).food
	if me.eat(index):
		food_eaten += food


## Closes in and swings: heavy when there is stamina for it and a dash after, else light.
func _fight(enemy: SimEnemy, delta: float) -> void:
	var me := player()
	var t := Content.tuning
	var reserve := t.dash_cost if dodge > 0.0 else 0.0
	var heavy := Content.attack(me.inventory.weapon(), true)
	var move := (
		heavy
		if me.stamina >= heavy.cost + reserve
		else Content.attack(me.inventory.weapon(), false)
	)
	# Behind a shield a light swing does nothing: go around it unless the swing breaks the guard.
	var guarded := enemy.blocks(me.position) and move.poise_damage < enemy.def.block_break
	if guarded:
		_walk_to(enemy.position + enemy.facing.rotated(PI * 0.75) * 24.0, delta)
		return
	if enemy.position.distance_to(me.position) > move.reach * 0.8:
		_walk_to(enemy.position, delta)
		return
	if me.stamina < move.cost + reserve or world.time < me.cooldown_until:
		return
	var aim := enemy.position - me.position
	var hits := PackedInt32Array()
	for other: SimEnemy in world.enemies.values():
		if Combat.in_arc(me.position, aim, other.position, move.reach, move.arc):
			hits.append(other.id)
	for hit in world.attack(id, move == heavy, aim, hits):
		if not world.enemies.has(hit):
			kills += 1


## Crafts the next gear upgrade (or a ration from spare berries) it has the items for,
## walking to the station first, or building one next to it if there is none in view. Returns
## whether that is what it is doing.
func _craft(delta: float) -> bool:
	var me := player()
	var wanted := _wanted_tools() + _wanted_gear()
	if player().inventory.count_of(&"berries") >= SPARE_BERRIES:
		wanted.append(&"trail_ration")
	for item in wanted:
		var recipe: RecipeDef = Content.recipes[item]
		match Crafting.status(
			me.inventory, recipe, Building.stations_near(world.pieces, me.position)
		):
			Crafting.Status.READY:
				world.craft(id, item)
				if not crafted_at.has(item):
					crafted_at[item] = world.time
				_wear(item)
				return true
			Crafting.Status.AWAY_FROM_STATION:
				if not me.inventory.has_all(recipe.inputs):
					continue
				var station := _nearest_piece(recipe.station)
				if not station.is_empty():
					_walk_to(Building.tile_center(station[0]), delta)
					return true
				if _build_near(recipe.station):
					return true
	return false


## [tile, distance] of the nearest loaded piece of a kind, [] if there is none.
func _nearest_piece(piece_id: StringName) -> Array:
	var best := []
	for tile: Vector2i in world.pieces:
		if world.pieces[tile].id != piece_id:
			continue
		var distance := Building.tile_center(tile).distance_to(player().position)
		if best.is_empty() or distance < best[1]:
			best = [tile, distance]
	return best


## Builds a piece on the first free tile a step away. Returns whether it did.
func _build_near(piece_id: StringName) -> bool:
	var center := Building.tile_of(player().position)
	for offset: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if world.build(id, center + offset, piece_id):
			return true
	return false


func _wear(item: StringName) -> void:
	var inventory := player().inventory
	for i in inventory.slots.size():
		if inventory.slots[i].get("item", &"") == item:
			player().equip(i)
			return


## The hand-made tools it still has none of.
func _wanted_tools() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: int in TOOLS:
		if player().inventory.best_tool(kind) == null:
			out.append(TOOLS[kind])
	return out


## The gear still worth making: better than what is worn and not carried already.
func _wanted_gear() -> Array[StringName]:
	var out: Array[StringName] = []
	var inventory := player().inventory
	for item in GEAR:
		var def := Content.item(item)
		var worn := Content.item(inventory.equipment[def.slot])
		if inventory.count_of(item) > 0:
			continue
		if worn == null or _power(def) > _power(worn):
			out.append(item)
	return out


static func _power(def: ItemDef) -> float:
	return def.heavy.damage if def.slot == ItemDef.Slot.WEAPON else def.armor + def.health / 10


## Hunger the food it carries would restore.
func _food_carried() -> float:
	var total := 0.0
	for slot in player().inventory.slots:
		if not slot.is_empty():
			total += Content.item(slot.item).food * slot.count
	return total


## The prop kind whose drops the next wanted gear is short of, -1 if none: those parts come
## from enemies.
func _needed_prop() -> int:
	var inventory := player().inventory
	for item in _wanted_tools() + _wanted_gear():
		var recipe: RecipeDef = Content.recipes[item]
		var inputs := recipe.inputs.duplicate()
		# With no station in view, also what building one takes.
		if recipe.station != &"" and _nearest_piece(recipe.station).is_empty():
			var cost := Content.piece(recipe.station).cost
			for input: StringName in cost:
				inputs[input] = inputs.get(input, 0) + cost[input]
		for input: StringName in inputs:
			if inventory.count_of(input) >= inputs[input]:
				continue
			if input == &"stick":
				return WorldGen.Prop.STICK
			if input == &"pebble":
				return WorldGen.Prop.PEBBLE
			if input == &"wood":
				return WorldGen.Prop.TREE
			if input == &"stone":
				return WorldGen.Prop.ROCK
	return -1


## Walks to the nearest prop of a kind in view and picks it up, or swings at it if it is a tree
## or rock. False if none is in view.
func _gather(kind: int, delta: float) -> bool:
	var me := player()
	var best := []
	var best_distance := INF
	for coord in WorldGen.around(WorldGen.chunk_of(me.position), 1):
		var chunk: SimWorld.SimChunk = world.chunks.get(coord)
		if chunk == null:
			continue
		for prop_id: int in chunk.props:
			if chunk.props[prop_id] != kind or chunk.removed.has(prop_id):
				continue
			var distance := WorldGen.prop_position(coord, prop_id).distance_to(me.position)
			if distance < best_distance:
				best = [coord, prop_id]
				best_distance = distance
	if best.is_empty():
		return false
	var at := WorldGen.prop_position(best[0], best[1])
	if best_distance > SimWorld.REACH * 0.8:
		_walk_to(at, delta)
	elif WorldGen.is_node(kind):
		world.attack(id, false, at - me.position, PackedInt32Array())
	else:
		world.remove_prop(id, best[0], best[1])
	return true


func _wander_step(delta: float) -> void:
	var me := player()
	if world.time >= _wander_until:
		_wander_until = world.time + WANDER_TIME
		_wander = Vector2.from_angle(_rng.randf() * TAU)
		if me.position.length() > WANDER_RANGE:
			_wander = -me.position.normalized()
	_walk_to(me.position + _wander * 100, delta)


func _nearest_enemy() -> SimEnemy:
	var best: SimEnemy = null
	var me := player()
	for enemy: SimEnemy in world.enemies.values():
		if (
			best == null
			or enemy.position.distance_to(me.position) < best.position.distance_to(me.position)
		):
			best = enemy
	return best


## Walks toward target, sliding along a piece in the way like a player would.
func _walk_to(target: Vector2, delta: float) -> void:
	var me := player()
	var step := me.position.move_toward(target, Content.tuning.walk_speed * delta) - me.position
	for to: Vector2 in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		if world.move_player(id, me.position + to):
			return
