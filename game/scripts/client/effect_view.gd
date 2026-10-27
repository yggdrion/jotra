class_name EffectView
extends Node2D
## An ability's area on the ground: a healing ward's green circle standing for its duration and
## fading out at the end, or a shockwave's ring bursting out to its radius.

var kind := AbilityDef.Kind.WARD
var radius := 0.0
var seconds := 1.0

var _start := 0


func _ready() -> void:
	_start = Time.get_ticks_msec()
	z_index = -1


func _process(_delta: float) -> void:
	if age() >= seconds:
		queue_free()
	queue_redraw()


## Seconds since it appeared.
func age() -> float:
	return (Time.get_ticks_msec() - _start) / 1000.0


func _draw() -> void:
	var share := clampf(age() / seconds, 0.0, 1.0)
	if kind == AbilityDef.Kind.SHOCKWAVE:
		var color := Color(0.95, 0.85, 0.4, 1.0 - share)
		draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * share), 0, TAU, 32, color, 3.0)
		return
	var pulse := 0.5 + 0.5 * sin(age() * 5.0)
	var fade := minf((1.0 - share) * 4.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(0.4, 0.9, 0.5, (0.12 + 0.06 * pulse) * fade))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(0.5, 1.0, 0.6, 0.6 * fade), 1.5)
