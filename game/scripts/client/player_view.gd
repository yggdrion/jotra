class_name PlayerView
extends Node2D
## Placeholder capsule for a player, standing on its position (feet at the origin).

const OWN_COLOR := Color("63c74d")
const OTHER_COLOR := Color("0099db")
const RADIUS := 6.0
const HEIGHT := 20.0

var own := false


func _draw() -> void:
	var color := OWN_COLOR if own else OTHER_COLOR
	draw_circle(Vector2(0, -RADIUS), RADIUS, color)
	draw_rect(Rect2(-RADIUS, -HEIGHT + RADIUS, RADIUS * 2, HEIGHT - RADIUS * 2), color)
	draw_circle(Vector2(0, -HEIGHT + RADIUS), RADIUS, color)
