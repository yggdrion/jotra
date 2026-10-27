class_name PortalView
extends Node2D
## A way into or out of a dungeon: a shrine of skulls and green flame around a dark doorway,
## standing on its position, with its name above it.

const FONT_SIZE := 8

var label := ""


func _draw() -> void:
	var door := Decor.sprite("shrine")
	draw_texture(door, Vector2(-door.get_width() / 2.0, -door.get_height() + 4))
	var font := ThemeDB.fallback_font
	var at := Vector2(-40, -door.get_height())
	var center := HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, at, label, center, 80, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, at, label, center, 80, FONT_SIZE, Color("feae34"))
