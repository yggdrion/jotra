class_name ProjectileView
extends Node2D
## A projectile in flight: the arrow sprite pointing the way it flies. The snapshots give its
## position and direction; between them it keeps flying at the speed the last two implied.

const ICON := preload("res://assets/ninja_adventure/items/arrow.png")
## Height above the ground it flies at, px.
const HEIGHT := 6.0

var velocity := Vector2.ZERO
var _at := Vector2.INF
var _angle := 0.0


## The server's latest position and flight angle.
func update(at: Vector2, angle: float) -> void:
	if _at.is_finite():
		velocity = (at - _at) * GameServer.SNAPSHOT_RATE
	_at = at
	position = at
	_angle = angle
	queue_redraw()


func _process(delta: float) -> void:
	position += velocity * delta


func _draw() -> void:
	draw_set_transform(Vector2(0, -HEIGHT), _angle)
	draw_texture(ICON, -ICON.get_size() / 2)
