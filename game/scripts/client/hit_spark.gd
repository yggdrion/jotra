class_name HitSpark
extends Node2D
## A burst of short lines flying off where a blow landed, biased along its push, fading and
## freeing itself after LIFE_MS. Heavier blows throw more and longer ones.

const LIFE_MS := 160

var _born := Time.get_ticks_msec()
var _lines := []  # [direction, length]


## At a position, thrown along push (px) with this many lines.
static func burst(at: Vector2, push: Vector2, count: int) -> HitSpark:
	var spark := HitSpark.new()
	spark.position = at
	var base := push.angle() if push != Vector2.ZERO else randf() * TAU
	var spread := PI / 2 if push != Vector2.ZERO else PI
	for i in count:
		spark._lines.append(
			[Vector2.from_angle(base + randf_range(-spread, spread)), randf_range(4.0, 8.0)]
		)
	spark.z_index = 5
	return spark


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _born >= LIFE_MS:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := float(Time.get_ticks_msec() - _born) / LIFE_MS
	for line: Array in _lines:
		var from: Vector2 = line[0] * (2.0 + 10.0 * k)
		draw_line(from, from + line[0] * line[1] * (1.0 - k), Color(1, 0.95, 0.7, 1.0 - k), 1.0)
