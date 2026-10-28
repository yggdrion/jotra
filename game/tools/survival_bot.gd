class_name SurvivalBot
extends RefCounted
## Plays one player of a SimWorld the way a person roughly would, for the balance sim: eats
## when hungry, forages trees when low on food, gathers what the next piece of gear needs,
## crafts it (walking to a workbench, or building one first) and wears it, fights what comes
## near, uses its rune and healing draughts, walks back to its grave after a death to take its
## things back (by day, healed, with the group) and otherwise wanders.
## Skill decides how often it dashes out of a telegraphed hit, how often inside the perfect
## window, and whether it backs off when low on health. It drives the sim through the same
## calls the server makes for a client, so it gets no more than a player could do. It records
## what happened to it.

## Gear it works toward, in order; it skips what isn't better than what it wears.
const GEAR: Array[StringName] = [
	&"club", &"cloth_tunic", &"stone_axe", &"hide_armor", &"bone_armor", &"bone_sword"
]
const BONE_GEAR: Array[StringName] = [&"bone_armor", &"bone_sword"]
## Hand-made tools it makes first, by what they break: sticks and pebbles come off the ground.
const TOOLS := {ItemDef.Tool.AXE: &"pebble_axe", ItemDef.Tool.PICKAXE: &"pebble_pickaxe"}
## Enemies this close are fought.
const ENGAGE := 150.0
## Seconds from a windup's start to the dash at the earliest, when it dodges.
const REACT := 0.2
## The way of a dash timed into the perfect window: it stays where it is, so the hit still
## reaches it and the i-frames take it (a dash out of reach dodges nothing perfectly).
const THROUGH := Vector2.INF
## Eats below this share of max hunger; forages while carrying less food than FOOD_STOCK.
const EAT_BELOW := 0.5
const FOOD_STOCK := 40.0
## Berries beyond this are made into trail rations. From STEW_BERRIES on it stews them at a
## fire within STEW_RANGE, or one it builds where it stands if it has what that takes; it
## walks no further for a stew. (Stewing never made the bots forage more: the first M17 bot
## also made draughts without a bone limit, and those ate the berries.)
const SPARE_BERRIES := 12
const STEW_BERRIES := 3
const STEW_RANGE := 300.0
## The draughts it keeps in stock, and the bones it leaves for gear.
const DRAUGHT_STOCK := 2
const SPARE_BONES := 14
## Drinks a draught below this share of max health.
const DRINK_BELOW := 0.5
## Runes it makes once only the bone gear is left to make: the ward in a group, else the
## shockwave.
const GROUP_RUNE := &"ward_rune"
const SOLO_RUNE := &"shock_rune"
## Lays a ward below this share of max health (its own or a teammate's in it); fires a
## shockwave with this many enemies in its radius.
const WARD_BELOW := 0.6
const SURROUNDED := 2
## Goes back to its grave only with GRAVE_DAYLIGHT seconds of day left, not starving (above
## GRAVE_HUNGER of max hunger or with food), and in a group only with a teammate within ESCORT
## (it walks to one first; idle teammates walk with it). It waits while GRAVE_CROWD enemies
## stand around the grave.
## A death on the way makes it wait GRAVE_RETRY seconds before it tries that grave again,
## and after GRAVE_TRIES deaths it leaves the grave be.
const GRAVE_DAYLIGHT := 90.0
const GRAVE_HUNGER := 0.2
const ESCORT := 120.0
const GRAVE_CROWD := 2
const GRAVE_RETRY := 120.0
const GRAVE_TRIES := 2
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
## Seconds before it searches its route again for a target that moved to another tile.
const REPATH := 0.5

var world: SimWorld
var id: int
## Chance to dash out of a telegraphed hit aimed at it, 0..1, and the share of those dashes
## it times inside the perfect window (Tuning.perfect_window) instead of early.
var dodge := 0.5
var perfect := 0.0
## The bots playing together, itself included.
var group: Array = []
## Walking back to its grave now: teammates with nothing to do walk with it.
var grave_run := false
## Backs off to heal when low.
var retreats := false

## Seconds spent per activity: fight, forage, gather, craft, retreat, grave (its own or
## walking with a teammate to theirs), wander, dead.
var time_in := {}
var deaths_by_enemy := 0
var deaths_by_hunger := 0
var deaths_at_night := 0
var damage_day := 0.0
var damage_night := 0.0
var hits_taken := 0
var dodged := 0
var perfects := 0
var drunk := 0
var abilities := 0
var stewed := 0
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
## (zero: away from the nearest enemy, THROUGH: nowhere).
var _dash_at: Array[float] = []
var _dash_way: Array[Vector2] = []
var _retreating := false
var _wander := Vector2.RIGHT
var _wander_until := 0.0
var _was_dead := false
var _hit_this_tick := false
## The grave it last went for, its deaths on the way per grave, and when it tries again.
var _grave_target := Vector2.ZERO
var _grave_fails := {}
var _grave_retry_at := 0.0
## Its route around pieces and cliffs to the target tile it last searched for.
var _route: Array[Vector2] = []
var _route_tile := Vector2i.MAX
var _route_at := -1.0


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
		elif event[0] == "perfect" and event[1] == id:
			perfects += 1
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
		if grave_run:
			_grave_fails[_grave_target] = _grave_fails.get(_grave_target, 0) + 1
			_grave_retry_at = world.time + GRAVE_RETRY
		grave_run = false
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
	_drink()
	var health := me.health / me.max_health()
	if retreats and health < RETREAT_BELOW:
		_retreating = true
	elif health > RETREAT_UNTIL:
		_retreating = false
	var enemy := _nearest_enemy()
	var distance := enemy.position.distance_to(me.position) if enemy else INF
	_use_ability(enemy, distance)
	if _retreating and distance < SAFE:
		_spend("retreat", delta)
		# Stands in a ward while nothing is upon it.
		if distance <= CORNERED * 2 or not _in_ward():
			_walk_to(me.position + (me.position - enemy.position).normalized() * 100, delta)
		return
	if distance <= (CORNERED if _retreating else ENGAGE):
		_spend("fight", delta)
		_fight(enemy, delta)
		return
	if _to_grave(delta) or _escort(delta):
		_spend("grave", delta)
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
## to the arrow's arrival; a wolf's lunge lane is sidestepped too. Some of the dashes against a
## hit come late, inside the perfect window, and through the hit.
func _plan_dash(event: Array) -> void:
	var t := Content.tuning
	var late := _rng.randf() < perfect
	var at: float = (
		world.time + maxf(REACT, event[3] - (t.perfect_window * 0.5 if late else t.iframes))
	)
	var way := THROUGH if late else Vector2.ZERO
	var line: Vector2 = event[5]
	var enemy: SimEnemy = world.enemies[event[1]]
	if line != Vector2.ZERO and enemy.def.behavior == EnemyDef.Behavior.ARCHER:
		var flight := enemy.position.distance_to(player().position) / enemy.def.arrow_speed
		at = world.time + event[3] + flight - Content.tuning.iframes / 2
		way = line.orthogonal()
	elif line != Vector2.ZERO and event[6] == 0.0 and not late:
		way = line.orthogonal()
	_dash_at.append(at)
	_dash_way.append(way)


## Dashes away from the nearest enemy (or the way planned, or in place) when a planned dodge is
## due.
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
	if way == THROUGH:
		return true
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
	if world.eat(id, index):
		food_eaten += food


func _drink() -> void:
	var me := player()
	if me.health < me.max_health() * DRINK_BELOW and world.use_draught(id):
		drunk += 1


## Uses the worn rune's ability when it pays: a frost bolt at an enemy chasing it, a ward when
## it or a teammate beside it is hurt (alone only with no enemy upon it), a shockwave when
## SURROUNDED. Keeps the stamina for a dash.
func _use_ability(enemy: SimEnemy, distance: float) -> void:
	var me := player()
	var def := me.inventory.ability()
	if def == null or world.time < me.ability_ready_at or enemy == null:
		return
	if me.stamina < def.stamina_cost + (Content.tuning.dash_cost if dodge > 0.0 else 0.0):
		return
	var aim := Vector2.ZERO
	match def.kind:
		AbilityDef.Kind.FROST_BOLT:
			if enemy.target != id or distance < CORNERED or distance > def.range * 0.8:
				return
			aim = enemy.position - me.position
		AbilityDef.Kind.WARD:
			var hurt := false
			var near := 0
			for mate: SurvivalBot in group:
				var other := mate.player()
				if other.dead_until > 0 or other.position.distance_to(me.position) > def.radius:
					continue
				if mate != self:
					near += 1
				hurt = hurt or other.health < other.max_health() * WARD_BELOW
			if not hurt or (near == 0 and distance < CORNERED * 2):
				return
		AbilityDef.Kind.SHOCKWAVE:
			var around := 0
			for other: SimEnemy in world.enemies.values():
				if other.position.distance_to(me.position) <= def.radius * 0.9:
					around += 1
			if around < SURROUNDED:
				return
	if world.use_ability(id, aim):
		abilities += 1


func _in_ward() -> bool:
	for ward: SimWorld.SimWard in world.wards.values():
		if ward.position.distance_to(player().position) <= ward.radius * 0.8:
			return true
	return false


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


## Walks to its closest grave and loots it, once it is ready: day with time left, healed, not
## starving, no crowd at the grave, not just died on the way there, and in a group with a
## teammate beside it (it walks to the nearest living one first). Returns whether that is what
## it is doing; false also when nothing more of the grave fits.
func _to_grave(delta: float) -> bool:
	var me := player()
	grave_run = false
	var closest := Vector2.INF
	for at in me.graves:
		if _grave_fails.get(at, 0) >= GRAVE_TRIES:
			continue
		if at.distance_to(me.position) < closest.distance_to(me.position):
			closest = at
	if closest == Vector2.INF:
		return false
	if closest.distance_to(me.position) <= SimWorld.REACH * 0.8:
		return world.interact(id)
	if world.time < _grave_retry_at or not _ready_for_grave(closest):
		return false
	grave_run = true
	_grave_target = closest
	var mate := _nearest_mate()
	if mate and mate.player().position.distance_to(me.position) > ESCORT:
		_walk_to(mate.player().position, delta)
		return true
	_walk_to(closest, delta)
	return true


func _ready_for_grave(grave: Vector2) -> bool:
	var me := player()
	var t := Content.tuning
	if Survival.time_of_day(world.time) > t.day_length - GRAVE_DAYLIGHT:
		return false
	if me.health < me.max_health() * RETREAT_UNTIL:
		return false
	# The grave holds its food and tools: it forages first only when close to starving.
	if me.hunger < t.max_hunger * GRAVE_HUNGER and me.inventory.first_food() == -1:
		return false
	var crowd := 0
	for enemy: SimEnemy in world.enemies.values():
		if enemy.position.distance_to(grave) <= ENGAGE:
			crowd += 1
	return crowd < GRAVE_CROWD


## Walks with the nearest teammate on its way back to a grave, unless busy with its own.
func _escort(delta: float) -> bool:
	if not player().graves.is_empty():
		return false
	var me := player()
	for mate: SurvivalBot in group:
		if mate == self or not mate.grave_run:
			continue
		if mate.player().position.distance_to(me.position) > ESCORT * 0.5:
			_walk_to(mate.player().position, delta)
		return true
	return false


## The nearest living teammate, null if none.
func _nearest_mate() -> SurvivalBot:
	var best: SurvivalBot = null
	var me := player()
	for mate: SurvivalBot in group:
		if mate == self or mate.player().dead_until > 0:
			continue
		var distance := mate.player().position.distance_to(me.position)
		if best == null or distance < best.player().position.distance_to(me.position):
			best = mate
	return best


## Crafts the next gear upgrade (or a ration from spare berries) it has the items for,
## walking to the station first, or building one next to it if there is none in view. Returns
## whether that is what it is doing.
func _craft(delta: float) -> bool:
	var me := player()
	var wanted := _wanted_tools() + _wanted_rune() + _wanted_gear()
	if player().inventory.count_of(&"berries") >= SPARE_BERRIES:
		wanted.append(&"trail_ration")
	# The first from any bone, more only from bones the next gear can do without.
	var draughts := player().inventory.count_of(&"healing_draught")
	var bones := player().inventory.count_of(&"bone")
	if draughts < 1 or (draughts < DRAUGHT_STOCK and bones > SPARE_BONES):
		wanted.append(&"healing_draught")
	if player().inventory.count_of(&"meat") > 0:
		wanted.append(&"cooked_meat")
	if player().inventory.count_of(&"berries") >= STEW_BERRIES:
		wanted.append(&"stewed_berries")
	for item in wanted:
		var recipe: RecipeDef = Content.recipes[item]
		match Crafting.status(
			me.inventory, recipe, Building.stations_near(world.pieces, me.position)
		):
			Crafting.Status.READY:
				world.craft(id, item)
				if item == &"stewed_berries":
					stewed += 1
				if not crafted_at.has(item):
					crafted_at[item] = world.time
				_wear(item)
				return true
			Crafting.Status.AWAY_FROM_STATION:
				if not me.inventory.has_all(recipe.inputs):
					continue
				var station := _nearest_piece(recipe.station)
				# Stews at a fire near it, or one it builds here if it has what that takes.
				if item == &"stewed_berries" and (station.is_empty() or station[1] > STEW_RANGE):
					if _build_near(recipe.station):
						return true
					continue
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


## The rune it makes next, before the bone gear: none while it wears one or still wants gear
## that comes before the bone gear. In a group the group rune when it has the drops that take
## (they come only from enemies), else the solo one.
func _wanted_rune() -> Array[StringName]:
	var inventory := player().inventory
	if inventory.equipment[ItemDef.Slot.RUNE] != &"":
		return []
	for item in _wanted_gear():
		if not item in BONE_GEAR:
			return []
	if group.size() > 1:
		var drops: Dictionary = Content.recipes[GROUP_RUNE].inputs.duplicate()
		drops.erase(&"bone")
		if inventory.has_all(drops):
			return [GROUP_RUNE]
	return [SOLO_RUNE]


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
	for item in _wanted_tools() + _wanted_rune() + _wanted_gear():
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
	if not _walk_to(me.position + _wander * 100, delta):
		# Up against a cliff: another way next tick.
		_wander_until = 0.0


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


## Walks toward target around pieces and cliffs, sliding along what is in the way like a player
## would. Returns whether it moved.
func _walk_to(target: Vector2, delta: float) -> bool:
	var me := player()
	var aim := _waypoint(target)
	var step := me.position.move_toward(aim, Content.tuning.walk_speed * delta) - me.position
	for to: Vector2 in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		if world.move_player(id, me.position + to):
			return true
	# Stuck: search again next tick.
	_route_tile = Vector2i.MAX
	_route_at = 0.0
	return false


## The next point on the way to target: the first waypoint of its route, searched again once
## the target is on another tile and REPATH has passed.
func _waypoint(target: Vector2) -> Vector2:
	var me := player()
	var tile := Building.tile_of(target)
	if tile != _route_tile and world.time >= _route_at:
		var blocked := world.blocked_at(me.position)
		_route = Pathing.find(blocked, me.position, target, SimEnemy.PATH_NODES).points
		_route_tile = tile
		_route_at = world.time + REPATH
	while not _route.is_empty() and me.position.distance_to(_route[0]) <= 2.0:
		_route.pop_front()
	return target if _route.is_empty() else _route[0]
