class_name EnemyView
extends PlayerView
## An enemy (draugr) in its def's walk sheet, tinted orange while it winds up an attack.

const WINDUP := Color(1.6, 0.9, 0.3)

var _windup_until := 0


func windup(seconds: float) -> void:
	_windup_until = Time.get_ticks_msec() + int(seconds * 1000)
	queue_redraw()


func sheet() -> Texture2D:
	return Content.tuning.enemy.sheet


func tint() -> Color:
	return WINDUP if Time.get_ticks_msec() < _windup_until else super()
