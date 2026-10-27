class_name SimProjectile
extends RefCounted
## A projectile in flight on the server, shot by a player or an enemy: it flies straight until
## its range runs out and hits the first opposing body or blocking piece on its way
## (SimWorld._tick_projectiles). Bodies of its own team are passed through.

enum Team { PLAYERS, ENEMIES }

var id: int
var team: Team
## The shooting player's or enemy's id; that one may be gone by the time it hits.
var owner_id: int
var position: Vector2
var velocity: Vector2
var damage: float
## Distance it can still fly.
var range_left: float
## An enemy it hits is slowed to this speed multiplier for slow_time seconds (1: no effect).
var slow := 1.0
var slow_time := 0.0


func _init(
	projectile_id: int,
	shooter_team: Team,
	shooter_id: int,
	from: Vector2,
	direction: Vector2,
	speed: float,
	hit_damage: float,
	max_range: float
) -> void:
	id = projectile_id
	team = shooter_team
	owner_id = shooter_id
	position = from
	velocity = direction.normalized() * speed
	damage = hit_damage
	range_left = max_range
