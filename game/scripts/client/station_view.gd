class_name StationView
extends Node2D
## Placeholder for a crafting station (Tuning.stations): a workbench, standing on its position.


func _draw() -> void:
	draw_rect(Rect2(-12, -12, 24, 8), Color("733e39"))
	draw_rect(Rect2(-11, -4, 3, 4), Color("3e2731"))
	draw_rect(Rect2(8, -4, 3, 4), Color("3e2731"))
	draw_rect(Rect2(-6, -16, 6, 4), Color("8b9bb4"))
