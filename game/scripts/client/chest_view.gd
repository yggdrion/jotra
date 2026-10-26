class_name ChestView
extends Node2D
## A dungeon's end chest standing on its position, its lid up once opened.

const SHEET := preload("res://assets/ninja_adventure/items/treasure_chest.png")

var opened := false


func _draw() -> void:
	var frame := Rect2(16 if opened else 0, 0, 16, 16)
	draw_texture_rect_region(SHEET, Rect2(-8, -15, 16, 16), frame)
