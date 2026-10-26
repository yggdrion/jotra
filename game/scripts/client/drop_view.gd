class_name DropView
extends Node2D
## Placeholder for an item on the ground: a small square in the item's color, outlined in its
## rarity's, bobbing a little over a shadow. Glides toward target as the server moves it.

const SIZE := 8.0
const BOB_PX := 1.5
## Faster than the server's magnet, so it keeps up.
const GLIDE_SPEED := 300.0

var item: ItemDef
var target: Vector2


func _process(delta: float) -> void:
	position = position.move_toward(target, GLIDE_SPEED * delta)
	queue_redraw()


func _draw() -> void:
	var bob := sin(Time.get_ticks_msec() / 250.0 + position.x) * BOB_PX
	draw_circle(Vector2.ZERO, SIZE / 2, Color(0, 0, 0, 0.3))
	var rect := Rect2(-SIZE / 2, -SIZE - 3 + bob, SIZE, SIZE)
	draw_rect(rect, item.color)
	draw_rect(rect, ItemDef.RARITY_COLORS[item.rarity], false, 1)
