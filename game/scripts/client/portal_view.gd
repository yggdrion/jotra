class_name PortalView
extends Node2D
## A way into or out of a dungeon: a barrow mound with a dark doorway, standing on its position,
## with its name above it.

const FONT_SIZE := 8
const SHEET := preload("res://assets/ninja_adventure/tilesets/TilesetHouse.png")
const MOUND := Rect2(0, 112, 48, 48)

var label := ""


func _draw() -> void:
	draw_texture_rect_region(SHEET, Rect2(-24, -44, 48, 48), MOUND)
	var font := ThemeDB.fallback_font
	var at := Vector2(-40, -48)
	var center := HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, at, label, center, 80, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, at, label, center, 80, FONT_SIZE, Color("feae34"))
