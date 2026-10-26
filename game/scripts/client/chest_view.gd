class_name ChestView
extends Node2D
## Placeholder for a dungeon's end chest: a banded box standing on its position, its lid up and
## glowing once opened.

var opened := false


func _draw() -> void:
	draw_rect(Rect2(-10, -12, 20, 12), Color("733e39"))
	draw_rect(Rect2(-10, -8, 20, 2), Color("feae34"))
	if opened:
		draw_rect(Rect2(-9, -11, 18, 4), Color("feae34", 0.6))
		draw_rect(Rect2(-10, -20, 20, 4), Color("3e2731"))
	else:
		draw_rect(Rect2(-10, -16, 20, 4), Color("3e2731"))
		draw_rect(Rect2(-2, -12, 4, 4), Color("feae34"))
