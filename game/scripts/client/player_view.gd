class_name PlayerView
extends Node2D
## Placeholder capsule for a player, standing on its position (feet at the origin), with a
## health bar once hurt, a white flash on hits and the own player's swing arc.

const OWN_COLOR := Color("63c74d")
const OTHER_COLOR := Color("0099db")
const RADIUS := 6.0
const HEIGHT := 20.0
const FLASH_MS := 100
const SWING_MS := 120
const BAR_WIDTH := 16.0

var own := false
## 0..1, from the snapshots.
var health := 1.0:
	set(value):
		if value != health:
			health = value
			queue_redraw()

var _flash_until := 0
var _swing_until := 0
var _swing_aim := Vector2.RIGHT
var _swing: Dictionary


func flash() -> void:
	_flash_until = Time.get_ticks_msec() + FLASH_MS
	queue_redraw()


## Shows a Combat.LIGHT or HEAVY swing toward aim.
func swing(aim: Vector2, move: Dictionary) -> void:
	_swing_aim = aim
	_swing = move
	_swing_until = Time.get_ticks_msec() + SWING_MS
	queue_redraw()


func body_color() -> Color:
	return OWN_COLOR if own else OTHER_COLOR


func _process(_delta: float) -> void:
	# Redraw once more when a flash or swing runs out.
	var now := Time.get_ticks_msec()
	if now < _flash_until + 50 or now < _swing_until + 50:
		queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	var color := Color.WHITE if now < _flash_until else body_color()
	draw_circle(Vector2(0, -RADIUS), RADIUS, color)
	draw_rect(Rect2(-RADIUS, -HEIGHT + RADIUS, RADIUS * 2, HEIGHT - RADIUS * 2), color)
	draw_circle(Vector2(0, -HEIGHT + RADIUS), RADIUS, color)
	if health < 1.0:
		var bar := Rect2(-BAR_WIDTH / 2, -HEIGHT - 5, BAR_WIDTH, 2)
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color("e43b44"))
	if now < _swing_until:
		var half := deg_to_rad(_swing.arc) / 2
		var angle := _swing_aim.angle()
		var center := Vector2(0, -RADIUS)
		draw_arc(center, _swing.reach, angle - half, angle + half, 12, Color(1, 1, 1, 0.7), 2)
