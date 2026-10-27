class_name SimEnemy
extends RefCounted
## An enemy on the server. AI v1 (PLAN §5.2): idle until a player comes near, chase, wind up
## an attack that lands at the end if the target is still in range and not dashing (closing
## in at windup_speed meanwhile; a slam hits everyone near instead), then stand open for
## def.recovery. Hits push it (it slides) and wear down its poise: broken, or hit by a heavy
## during a windup, it staggers. It gives up when its target is led further than def.leash
## from home and walks home, healing on the way. It walks straight at its target; a blocking
## piece in the way gets the attack instead, until it breaks.
# ponytail: no pathing around walls; enemies break through. Add it if bases feel too fragile.

enum State { IDLE, CHASE, WINDUP, LEASH, RECOVER, STAGGER }

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
## The knockback it is still sliding along, px a second.
var knock_vel := Vector2.ZERO
## Sim time the windup lands (WINDUP) or the recovery or stagger ends.
var _until := 0.0
## Sim time the next attack may start.
var _ready_at := 0.0
## Seconds a perfect dodge of its hit leaves it open, taken off by SimWorld.damage_player.
var _punished := 0.0


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
			var far := position.distance_to(player.position) > def.attack_range
			siege = _step(world, player.position, speed * delta) if far else null
			if (far and siege == null) or world.time < _ready_at:
				return
			state = State.WINDUP
			_until = world.time + def.windup
			var area := (
				def.slam_radius if def.slam_radius > 0 else def.attack_range + def.attack_slack
			)
			world.events.append(["windup", id, position, def.windup, area])
		State.WINDUP:
			var player: SimWorld.SimPlayer = world.players.get(target)
			if player != null and siege == null:
				var close := maxf(position.distance_to(player.position) - def.attack_range, 0.0)
				_step(world, player.position, minf(speed * def.windup_speed * delta, close))
			if world.time < _until:
				return
			var reach := def.attack_range + def.attack_slack
			if siege != null:
				world.damage_piece(siege, damage)
				siege = null
			elif def.slam_radius > 0:
				for other: SimWorld.SimPlayer in world.players.values():
					if position.distance_to(other.position) <= def.slam_radius:
						world.damage_player(other.id, damage, self)
			elif player != null and position.distance_to(player.position) <= reach:
				world.damage_player(target, damage, self)
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
			if _step(world, home, speed * delta) != null:
				home = position
			if position == home and health >= max_health:
				state = State.IDLE


## Moves distance toward to unless a piece blocks the way (or it is already inside one).
## Returns the blocking piece's tile, null if it moved.
func _step(world: SimWorld, to: Vector2, distance: float) -> Variant:
	var next := position.move_toward(to, distance)
	var wall: Variant = world.blocker(next)
	if wall != null and world.blocker(position) == null:
		return wall
	position = next
	return null


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
