class_name EnemyView
extends PlayerView
## Placeholder enemy (draugr): a red capsule that turns orange while it winds up an attack.

const COLOR := Color("a22633")
const WINDUP_COLOR := Color("feae34")

var _windup_until := 0


func windup(seconds: float) -> void:
	_windup_until = Time.get_ticks_msec() + int(seconds * 1000)
	queue_redraw()


func body_color() -> Color:
	return WINDUP_COLOR if Time.get_ticks_msec() < _windup_until else COLOR


func _process(delta: float) -> void:
	super(delta)
	if Time.get_ticks_msec() < _windup_until + 50:
		queue_redraw()
