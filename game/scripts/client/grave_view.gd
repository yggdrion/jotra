class_name GraveView
extends Node2D
## A grave on its position: a headstone, with a faint glow on the player's own while it holds
## something, brighter while E acts on it.

const STONE := preload("res://assets/craftpix/props/grave.png")
const HIGHLIGHT := Color(1.6, 1.6, 1.6)

## The chunk it lies in.
var coord: Vector2i
var own := false
var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()


func _process(_delta: float) -> void:
	if own:
		queue_redraw()


func _draw() -> void:
	if own:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
		draw_circle(Vector2(0, -6), 10.0, Color(0.996, 0.682, 0.204, 0.15 + 0.15 * pulse))
	var tint := HIGHLIGHT if highlighted else Color.WHITE
	draw_texture(STONE, Vector2(-STONE.get_width() / 2.0, -STONE.get_height() + 2), tint)
