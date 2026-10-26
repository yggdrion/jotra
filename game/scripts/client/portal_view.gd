class_name PortalView
extends Node2D
## Placeholder for a way into or out of a dungeon: a barrow mound with a dark doorway, standing
## on its position, with its name above it.

const FONT_SIZE := 8

var label := ""


func _draw() -> void:
	draw_circle(Vector2(0, -6), 16, Color("5a6988"))
	draw_rect(Rect2(-16, -6, 32, 8), Color("5a6988"))
	draw_rect(Rect2(-6, -14, 12, 16), Color("181425"))
	draw_circle(Vector2(0, -14), 6, Color("181425"))
	var font := ThemeDB.fallback_font
	var at := Vector2(-40, -26)
	var center := HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, at, label, center, 80, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, at, label, center, 80, FONT_SIZE, Color("feae34"))
