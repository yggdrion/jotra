class_name EnemyView
extends PlayerView
## An enemy in its def's walk sheet at its def's size, tinted orange while it winds up an
## attack, with the ring a slam will hit drawn around it.

const WINDUP := Color(1.6, 0.9, 0.3)
const RING := Color(1, 0.55, 0.2, 0.8)

var def: EnemyDef:
	set(value):
		def = value
		scale = Vector2.ONE * def.size

var _windup_until := 0
var _slam_radius := 0.0


func windup(seconds: float, slam_radius: float) -> void:
	_windup_until = Time.get_ticks_msec() + int(seconds * 1000)
	_slam_radius = slam_radius
	queue_redraw()


func sheet() -> Texture2D:
	return def.sheet


func tint() -> Color:
	return WINDUP if Time.get_ticks_msec() < _windup_until else super()


func _draw() -> void:
	super()
	if _slam_radius > 0 and Time.get_ticks_msec() < _windup_until:
		draw_arc(Vector2.ZERO, _slam_radius / scale.x, 0, TAU, 32, RING, 1)
