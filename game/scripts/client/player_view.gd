class_name PlayerView
extends Node2D
## A player standing on its position (feet at the origin): a walk sheet facing the way it last
## moved or swung, a health bar once hurt, a white flash on hits and the own player's swing arc.

## Sheet columns per facing.
enum Facing { DOWN, UP, LEFT, RIGHT }

const OWN_SHEET := preload("res://assets/ninja_adventure/characters/hunter_walk.png")
const OTHER_SHEET := preload("res://assets/ninja_adventure/characters/caveman_walk.png")
const FRAME := 16
const FRAME_MS := 150
## Keeps walking this long after the last move, so frames without one don't flicker to idle.
const WALK_GRACE_MS := 100
const FLASH_MS := 100
const FLASH := Color(4, 4, 4)
const SWING_MS := 120
const BAR_WIDTH := 16.0
const RADIUS := 6.0

var own := false
## 0..1 of a bow drawn, shown as a ring that fills; 0: not drawing.
var draw_share := 0.0
## 0..1, from the snapshots.
var health := 1.0:
	set(value):
		if value != health:
			health = value
			queue_redraw()

var _flash_until := 0
var _swing_until := 0
var _swing_aim := Vector2.RIGHT
var _swing: AttackDef
var _facing := Facing.DOWN
var _walk_until := 0
var _last_position := Vector2.INF


func flash() -> void:
	_flash_until = Time.get_ticks_msec() + FLASH_MS
	queue_redraw()


## Shows a swing toward aim.
func swing(aim: Vector2, move: AttackDef) -> void:
	_swing_aim = aim
	_swing = move
	_swing_until = Time.get_ticks_msec() + SWING_MS
	_face(aim)
	queue_redraw()


func sheet() -> Texture2D:
	return OWN_SHEET if own else OTHER_SHEET


func tint() -> Color:
	return FLASH if Time.get_ticks_msec() < _flash_until else Color.WHITE


func _face(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		_facing = Facing.RIGHT if direction.x > 0 else Facing.LEFT
	else:
		_facing = Facing.DOWN if direction.y > 0 else Facing.UP


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var moved := position - _last_position if _last_position.is_finite() else Vector2.ZERO
	_last_position = position
	if moved.length() > 0.01:
		_walk_until = now + WALK_GRACE_MS
		if now >= _swing_until:
			_face(moved)
	queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	var row := (now / FRAME_MS) % 4 if now < _walk_until else 0
	var region := Rect2(_facing * FRAME, row * FRAME, FRAME, FRAME)
	draw_texture_rect_region(sheet(), Rect2(-FRAME / 2.0, -FRAME, FRAME, FRAME), region, tint())
	if health < 1.0:
		var bar := Rect2(-BAR_WIDTH / 2, -FRAME - 5, BAR_WIDTH, 2)
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color("e43b44"))
	if draw_share > 0.0:
		var ring := Color.WHITE if draw_share >= 1.0 else Color(1, 1, 1, 0.6)
		draw_arc(Vector2(0, -RADIUS), 10.0, -PI / 2, -PI / 2 + TAU * draw_share, 24, ring, 2)
	if now < _swing_until:
		var half := deg_to_rad(_swing.arc) / 2
		var angle := _swing_aim.angle()
		var center := Vector2(0, -RADIUS)
		draw_arc(center, _swing.reach, angle - half, angle + half, 12, Color(1, 1, 1, 0.7), 2)
