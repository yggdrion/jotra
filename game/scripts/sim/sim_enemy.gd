class_name SimEnemy
extends RefCounted
## An enemy on the server. AI v1 (PLAN §5.2): idle until a player comes near, chase, wind up
## an attack that lands at the end if the target is still in range and not dashing, and walk
## home to heal when led too far away.

enum State { IDLE, CHASE, WINDUP, LEASH }

var id: int
var def: EnemyDef
var position: Vector2
var home: Vector2
var health: float
var max_health: float
var damage: float
var state := State.IDLE
var target := 0
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
			if position.distance_to(player.position) > def.attack_range:
				position = position.move_toward(player.position, def.speed * delta)
			elif world.time >= _until:
				state = State.WINDUP
				_until = world.time + def.windup
				world.events.append(["windup", id, position, def.windup])
		State.WINDUP:
			if world.time < _until:
				return
			var player: SimWorld.SimPlayer = world.players.get(target)
			var reach := def.attack_range + def.attack_slack
			if player != null and position.distance_to(player.position) <= reach:
				world.damage_player(target, damage)
			_until = world.time + def.cooldown
			state = State.CHASE
		State.LEASH:
			position = position.move_toward(home, def.speed * delta)
			if position == home:
				health = max_health
				state = State.IDLE


## Hit by a player: wake up and go for them.
func provoke(by: int) -> void:
	if state == State.IDLE:
		state = State.CHASE
		target = by
