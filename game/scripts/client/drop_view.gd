class_name DropView
extends Node2D
## Placeholder for an item on the ground: a small square in the item's color, outlined in its
## rarity's, bobbing a little.

const SIZE := 6.0
const BOB_PX := 1.5

var item: ItemDef


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bob := sin(Time.get_ticks_msec() / 250.0 + position.x) * BOB_PX
	var rect := Rect2(-SIZE / 2, -SIZE - 2 + bob, SIZE, SIZE)
	draw_rect(rect, item.color)
	draw_rect(rect, ItemDef.RARITY_COLORS[item.rarity], false, 1)
