class_name SimEnemy
extends RefCounted
## An enemy on the server. AI v1 (PLAN §5.2): idle until a player comes near, chase, wind up
## an attack that lands at the end if the target is still in range and not dashing (closing
## in at windup_speed meanwhile; a slam hits everyone near instead), then stand open for
## def.recovery. Hits push it (it slides) and wear down its poise: broken, or hit by a heavy
## during a windup, it staggers. It gives up when its target is led further than def.leash
## from home and walks home, healing on the way. It walks around blocking pieces to its target
## (Pathing, searched again when pieces change or its target moves to another tile); when no
## way is open it attacks the piece in its way at the end of the best route until it breaks.
## def.behavior changes the parts that differ (approach, what the windup ends in): an archer
## keeps its distance and shoots along the line it locked, a wolf circles and lunges and its
## pack comes along, a shield blocks hits from the front, an exploder blows up.
# ponytail: leashing walks straight home; it only takes the spot it is walled off at as home.

enum State { IDLE, CHASE, WINDUP, LEASH, RECOVER, STAGGER }

## Seconds at least between path searches for a moving target (spread a little by id).
const REPATH := 0.5
## Tiles one path search may expand.
const PATH_NODES := 300
## Behaviors whose melee hit can be a sweep (EnemyDef.sweep_arc).
const SWEEPERS := [EnemyDef.Behavior.MELEE, EnemyDef.Behavior.SHIELD]
## Players closer than this to it are in its sweep whatever the angle.
const SWEEP_CORE := 6.0

var id: int
var def: EnemyDef
var position: Vector2
var home: Vector2
var health: float
var max_health: float
var damage: float
## def.speed, faster for those spawned at night.
var speed: float
var state := State.IDLE
var target := 0
## The tile of the piece the current windup is aimed at, null when it is aimed at the player.
var siege: Variant = null
## A bleed from a player's buff: damage a second until the sim time bleed_until, by whom.
var bleed_dps := 0.0
var bleed_until := 0.0
var bleed_by := 0
var poise: float
## Speed multiplier from a frost bolt, until the sim time slow_until.
var slow := 1.0
var slow_until := 0.0
## The knockback it is still sliding along, px a second.
var knock_vel := Vector2.ZERO
## The way it faces, turning toward its target at def.turn_speed.
var facing := Vector2.DOWN
## Enemies spawned together share a pack id (0: none) and wake together.
var pack := 0
## Sim time the windup lands (WINDUP) or the recovery or stagger ends.
var _until := 0.0
## Sim time the next attack may start.
var _ready_at := 0.0
## The direction the current windup locked onto, for a shot or a lunge.
var _aim := Vector2.ZERO
var _alerted := false
## Seconds a perfect dodge of its hit leaves it open, taken off by SimWorld.damage_player.
var _punished := 0.0
## The waypoints left on its route (empty: straight at the target), whether the route reaches
## the target, the earliest time to search again, and the target's tile and
## SimWorld.pieces_version at the last search.
var _path: Array[Vector2] = []
var _open := true
var _repath_at := 0.0
var _path_goal := Vector2i.MAX
var _path_version := -1
## Ran into a piece on a route that looked open: searches again at once, sieges if that
## happens again before it moves freely.
var _stuck := false


## Health and damage come scaled; the rest is from def.
func _init(
	enemy_id: int, kind: EnemyDef, at: Vector2, enemy_health: float, enemy_damage: float
) -> void:
	id = enemy_id
	def = kind
	position = at
	home = at
	health = enemy_health
	max_health = enemy_health
	damage = enemy_damage
	speed = kind.speed
	poise = kind.poise


func tick(world: SimWorld, delta: float) -> void:
	_slide(world, delta)
	if state != State.STAGGER:
		poise = minf(def.poise, poise + def.poise * delta / Content.tuning.poise_regen_time)
	match state:
		State.IDLE:
			target = world.nearest_player(position, def.notice_radius)
			if target != 0:
				state = State.CHASE
		State.CHASE:
			var player: SimWorld.SimPlayer = world.players.get(target)
			if (
				player == null
				or player.dead_until > 0
				or player.position.distance_to(home) > def.leash
			):
				state = State.LEASH
				target = 0
				world.events.append(["enemy", id, Net.EnemyEvent.GAVE_UP, position])
				return
			_alert_pack(world)
			_turn(player.position, delta)
			siege = null
			if not _approach(world, player, delta) or world.time < _ready_at:
				return
			state = State.WINDUP
			_until = world.time + def.windup
			_aim = (player.position - position).normalized()
			var area := (
				def.slam_radius if def.slam_radius > 0 else def.attack_range + def.attack_slack
			)
			var line := Vector2.ZERO
			var arc := 0.0
			if def.behavior == EnemyDef.Behavior.ARCHER:
				area = def.arrow_range
				line = _aim
			elif _sweeps():
				line = _aim
				arc = def.sweep_arc
			world.events.append(["windup", id, position, def.windup, area, line, arc])
		State.WINDUP:
			var player: SimWorld.SimPlayer = world.players.get(target)
			if player != null:
				_turn(player.position, delta)
			if player != null and siege == null:
				var close := maxf(position.distance_to(player.position) - def.attack_range, 0.0)
				# A sweep presses on along its locked aim, so a step to the side gets out of it.
				var to := position + _aim * 100.0 if _sweeps() else player.position
				_step(world, to, minf(_speed(world) * def.windup_speed * delta, close))
			if world.time < _until:
				return
			if siege != null:
				world.damage_piece(siege, damage)
				siege = null
			else:
				match def.behavior:
					EnemyDef.Behavior.ARCHER:
						world.add_projectile(
							SimProjectile.Team.ENEMIES,
							id,
							position,
							_aim,
							def.arrow_speed,
							damage,
							def.arrow_range
						)
					EnemyDef.Behavior.PACK:
						_lunge(world, player)
					EnemyDef.Behavior.EXPLODER:
						world.explode(self)
						return
					_:
						_strike(world, player)
			world.events.append(["enemy", id, Net.EnemyEvent.STRIKE, position])
			_ready_at = world.time + def.cooldown
			_until = world.time + maxf(def.recovery, _punished)
			if _punished > 0:
				world.events.append(["enemy", id, Net.EnemyEvent.STAGGER, position])
			_punished = 0.0
			state = State.RECOVER
		State.RECOVER, State.STAGGER:
			if world.time >= _until:
				state = State.CHASE
		State.LEASH:
			health = minf(health + max_health * def.leash_heal * delta, max_health)
			# Walled off from home: this is home now.
			if _step(world, home, _speed(world) * delta) != null:
				home = position
			if position == home and health >= max_health:
				state = State.IDLE


## Closes in on or keeps away from the player as the behavior wants. Returns whether it is
## in place to attack (a blocking piece in the way, in siege, counts).
func _approach(world: SimWorld, player: SimWorld.SimPlayer, delta: float) -> bool:
	var distance := position.distance_to(player.position)
	var away := (position - player.position).normalized()
	if def.behavior == EnemyDef.Behavior.ARCHER:
		if distance < def.preferred_distance:
			_step(world, position + away * 100.0, _speed(world) * delta)
			return true
	elif def.behavior == EnemyDef.Behavior.PACK:
		if distance <= def.attack_range and world.time < _ready_at:
			# Circles at circle_distance, to the side picked by id.
			var side := 1.0 if id % 2 == 0 else -1.0
			var around := away.rotated(side * PI / 2)
			var nudge := away * clampf(def.circle_distance - distance, -1.0, 1.0)
			_step(world, position + (around + nudge) * 100.0, _speed(world) * 0.7 * delta)
			return false
	if distance <= def.attack_range:
		return true
	var wall: Variant = _step(world, _waypoint(world, player.position), _speed(world) * delta)
	if wall == null:
		_stuck = false
	elif _open and not _stuck:
		# The target moved behind a piece or a push took it off its route: look again first.
		_stuck = true
		return false
	siege = wall
	return siege != null


## Where to walk next on the way to goal: the next waypoint of its route, searched again
## when pieces changed or the goal moved to another tile (at most every REPATH), as the
## tick's path budget allows; at once when stuck.
func _waypoint(world: SimWorld, goal: Vector2) -> Vector2:
	var tile := Building.tile_of(goal)
	var moved := tile != _path_goal and world.time >= _repath_at
	var due := _stuck or moved or _path_version != world.pieces_version
	if due and (_stuck or world.path_budget >= PATH_NODES):
		var route := Pathing.find(world.blocked_tiles(), position, goal, PATH_NODES)
		world.path_budget -= route.used
		_path = route.points
		_open = route.open
		_path_goal = tile
		_path_version = world.pieces_version
		_repath_at = world.time + REPATH + (id % 5) * 0.05
	while not _path.is_empty() and position.distance_to(_path[0]) <= 0.5:
		_path.pop_front()
	return goal if _path.is_empty() else _path[0]


## Moves distance toward to unless a piece blocks the way (or it is already inside one).
## Returns the blocking piece's tile, null if it moved.
func _step(world: SimWorld, to: Vector2, distance: float) -> Variant:
	var next := position.move_toward(to, distance)
	var wall: Variant = world.blocker(next)
	if wall != null and world.blocker(position) == null:
		return wall
	position = next
	return null


## Whether its melee hit is a sweep (EnemyDef.sweep_arc) rather than a slam or a hit anywhere
## in reach.
func _sweeps() -> bool:
	return def.sweep_arc > 0 and def.slam_radius <= 0 and def.behavior in SWEEPERS


## The melee hit: a sweep over everyone in the cone of its aim, a slam on everyone near, or a
## hit on the target anywhere in reach.
func _strike(world: SimWorld, player: SimWorld.SimPlayer) -> void:
	if _sweeps():
		var reach := def.attack_range + def.attack_slack
		var half := deg_to_rad(def.sweep_arc) / 2
		for other: SimWorld.SimPlayer in world.players.values():
			var to := other.position - position
			var inside := to.length() <= SWEEP_CORE or absf(_aim.angle_to(to)) <= half
			if to.length() <= reach and inside:
				world.damage_player(other.id, damage, self)
	elif def.slam_radius > 0:
		for other: SimWorld.SimPlayer in world.players.values():
			if position.distance_to(other.position) <= def.slam_radius:
				world.damage_player(other.id, damage, self)
	elif player != null:
		if position.distance_to(player.position) <= def.attack_range + def.attack_slack:
			world.damage_player(target, damage, self)


## A wolf's dash along the locked aim, stopping against a piece or at the target; it hits if
## it ends within lunge_reach.
func _lunge(world: SimWorld, player: SimWorld.SimPlayer) -> void:
	var left := def.lunge_distance
	while left > 0.0:
		var stride := minf(left, 8.0)
		var next := position + _aim * stride
		if world.blocker(next) != null:
			break
		position = next
		left -= stride
		if player != null and position.distance_to(player.position) <= def.lunge_reach * 0.6:
			break
	if player != null and position.distance_to(player.position) <= def.lunge_reach:
		world.damage_player(target, damage, self)


## Turns the facing toward at, at most def.turn_speed radians a second.
func _turn(at: Vector2, delta: float) -> void:
	var want := (at - position).normalized()
	if want == Vector2.ZERO:
		return
	if def.turn_speed <= 0.0:
		facing = want
		return
	var most := def.turn_speed * delta
	facing = facing.rotated(clampf(facing.angle_to(want), -most, most))


## Whether a hit coming from from lands on its shield instead (front arc, not while staggered).
func blocks(from: Vector2) -> bool:
	if def.block_arc <= 0.0 or state == State.STAGGER or state == State.LEASH:
		return false
	return absf(facing.angle_to(from - position)) <= deg_to_rad(def.block_arc) / 2


## The first time it chases, its pack wakes with it.
func _alert_pack(world: SimWorld) -> void:
	if _alerted or pack == 0:
		return
	_alerted = true
	for other: SimEnemy in world.enemies.values():
		if other.pack == pack and other.state == State.IDLE:
			other._alerted = true
			other.state = State.CHASE
			other.target = target


## Hit by a player: wake up and go for them.
func provoke(by: int) -> void:
	if state == State.IDLE:
		state = State.CHASE
		target = by


## A hit slides it dist px away along dir (a unit vector).
func push(dir: Vector2, dist: float) -> void:
	knock_vel += dir * dist * def.knock_scale * Content.tuning.knock_decay


## The way and px its knockback will carry it, for the hit event.
func pushed() -> Vector2:
	return knock_vel / Content.tuning.knock_decay


## A hit of this poise_damage: wears poise down, which staggers it when gone. A windup is
## not worn down but broken outright by a heavy hit (def.windup_armor).
func hit_poise(world: SimWorld, amount: float) -> void:
	if state == State.LEASH or state == State.STAGGER:
		return
	if state == State.WINDUP:
		if amount >= def.windup_armor:
			stagger(world, def.stagger_time)
		return
	poise -= amount
	if poise <= 0:
		stagger(world, def.stagger_time)


## Cancels what it is doing and stands open for seconds.
func stagger(world: SimWorld, seconds: float) -> void:
	state = State.STAGGER
	siege = null
	poise = def.poise
	_until = world.time + seconds
	_ready_at = maxf(_ready_at, _until)
	world.events.append(["enemy", id, Net.EnemyEvent.STAGGER, position])


## A perfect dodge of its hit: it is left open for seconds after the hit.
func punish(seconds: float) -> void:
	_punished = seconds


## Moves along its knockback, slowing down, unless a piece is in the way.
func _slide(world: SimWorld, delta: float) -> void:
	if knock_vel == Vector2.ZERO:
		return
	var decay := Content.tuning.knock_decay
	var fall := exp(-decay * delta)
	var next := position + knock_vel * (1.0 - fall) / decay
	if world.blocker(next) == null or world.blocker(position) != null:
		position = next
	else:
		knock_vel = Vector2.ZERO
	knock_vel *= fall
	if knock_vel.length() < 4.0:
		knock_vel = Vector2.ZERO


## Its speed now, slowed while a frost bolt holds it.
func _speed(world: SimWorld) -> float:
	return speed * (slow if world.time < slow_until else 1.0)


## Whether a frost bolt slows it now.
func slowed(world: SimWorld) -> bool:
	return world.time < slow_until
