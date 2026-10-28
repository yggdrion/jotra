class_name ProjectileView
extends Node2D
## A projectile in flight: the arrow sprite pointing the way it flies, or for a frost bolt an
## icy shard in a pale glow with a fading trail. The snapshots give its position and direction;
## between them it keeps flying at the speed the last two implied.

const ICON := preload("res://assets/ninja_adventure/items/arrow.png")
## Height above the ground it flies at, px.
const HEIGHT := 6.0
const FROST_CORE := Color(0.92, 0.98, 1.0)
const FROST_EDGE := Color(0.45, 0.75, 1.0)
const FROST_GLOW := Color(0.5, 0.8, 1.0, 0.25)

var velocity := Vector2.ZERO
## Drawn as a frost bolt instead of an arrow (Net.projectile_frost).
var frost := false
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
	if not frost:
		draw_texture(ICON, -ICON.get_size() / 2)
		return
	# Pointing along +x: a trail of shrinking motes behind, a glow, the shard over it.
	for i in 3:
		var color := FROST_EDGE
		color.a = 0.45 - i * 0.12
		draw_circle(Vector2(-7 - i * 5, 0), 2.5 - i * 0.6, color)
	draw_circle(Vector2.ZERO, 7, FROST_GLOW)
	draw_colored_polygon(
		PackedVector2Array([Vector2(7, 0), Vector2(0, -3), Vector2(-6, 0), Vector2(0, 3)]),
		FROST_EDGE
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(5, 0), Vector2(0, -1.5), Vector2(-3, 0), Vector2(0, 1.5)]),
		FROST_CORE
	)
