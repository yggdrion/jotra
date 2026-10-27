class_name PortalView
extends Node2D
## A way into or out of a dungeon: a skull with a gaping mouth for a doorway, standing on its
## position, with its name above it.

const FONT_SIZE := 8
const DOOR := preload("res://assets/craftpix/props/barrow.png")

var label := ""


func _draw() -> void:
	draw_texture(DOOR, Vector2(-DOOR.get_width() / 2.0, -DOOR.get_height() + 4))
	var font := ThemeDB.fallback_font
	var at := Vector2(-40, -48)
	var center := HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, at, label, center, 80, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, at, label, center, 80, FONT_SIZE, Color("feae34"))
