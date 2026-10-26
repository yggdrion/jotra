class_name StationView
extends Node2D
## Placeholder for a crafting station (Tuning.stations): a workbench standing on its position,
## with its name above it.

const FONT_SIZE := 8

var station: StringName


func _draw() -> void:
	draw_rect(Rect2(-12, -12, 24, 8), Color("733e39"))
	draw_rect(Rect2(-11, -4, 3, 4), Color("3e2731"))
	draw_rect(Rect2(8, -4, 3, 4), Color("3e2731"))
	draw_rect(Rect2(-6, -16, 6, 4), Color("8b9bb4"))
	var font := ThemeDB.fallback_font
	var text := str(station).capitalize()
	var at := Vector2(-40, -20)
	var center := HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, at, text, center, 80, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, at, text, center, 80, FONT_SIZE, Color("feae34"))
