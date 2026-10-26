class_name SimEnemy
extends RefCounted
## An enemy on the server. AI v1 (PLAN §5.2): idle until a player comes near, chase, wind up
## an attack that lands at the end if the target is still in range and not dashing (closing
## in at windup_speed meanwhile; a slam hits everyone near instead), and walk
## home to heal when led too far away. It walks straight at its target; a blocking piece in the
## way gets the attack instead, until it breaks.
# ponytail: no pathing around walls; enemies break through. Add it if bases feel too fragile.

enum State { IDLE, CHASE, WINDUP, LEASH }

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
## Sim time the windup lands (WINDUP) or the next attack may start (CHASE).
var _until := 0.0


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


func tick(world: SimWorld, delta: float) -> void:
	match state:
		State.IDLE:
			target = world.nearest_player(position, def.notice_radius)
			if target != 0:
				state = State.CHASE
		State.CHASE:
			var player: SimWorld.SimPlayer = world.players.get(target)
			if player == null or player.dead_until > 0 or position.distance_to(home) > def.leash:
				state = State.LEASH
				target = 0
				return
			var far := position.distance_to(player.position) > def.attack_range
			siege = _step(world, player.position, speed * delta) if far else null
			if (far and siege == null) or world.time < _until:
				return
			state = State.WINDUP
			_until = world.time + def.windup
			world.events.append(["windup", id, position, def.windup, def.slam_radius])
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
			_until = world.time + def.cooldown
			state = State.CHASE
		State.LEASH:
			# Walled off from home: this is home now.
			if _step(world, home, speed * delta) != null:
				home = position
			if position == home:
				health = max_health
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
