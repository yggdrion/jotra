class_name DropView
extends Node2D
## An item on the ground: its icon (or a square in its color, outlined in its rarity's) bobbing a
## little over a shadow; a buff orb is a pulsing ball in its rarity's color.
## Glides toward target as the server moves it.

const SIZE := 8.0
const BOB_PX := 1.5
## Faster than the server's magnet, so it keeps up.
const GLIDE_SPEED := 300.0

## One of the two is set.
var item: ItemDef
var buff: BuffDef
var target: Vector2


func _process(delta: float) -> void:
	position = position.move_toward(target, GLIDE_SPEED * delta)
	queue_redraw()


func _draw() -> void:
	var bob := sin(Time.get_ticks_msec() / 250.0 + position.x) * BOB_PX
	draw_circle(Vector2.ZERO, SIZE / 2, Color(0, 0, 0, 0.3))
	if buff:
		var color := ItemDef.RARITY_COLORS[buff.rarity]
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		draw_circle(Vector2(0, -SIZE + bob), SIZE * 0.8, Color(color, 0.25 + 0.25 * pulse))
		draw_circle(Vector2(0, -SIZE + bob), SIZE / 2, color)
		return
	if item.icon:
		var size := item.icon.get_size()
		draw_texture(item.icon, Vector2(-size.x / 2, -size.y - 3 + bob).round())
		return
	var rect := Rect2(-SIZE / 2, -SIZE - 3 + bob, SIZE, SIZE)
	draw_rect(rect, item.color)
	draw_rect(rect, ItemDef.RARITY_COLORS[item.rarity], false, 1)
