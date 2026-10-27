class_name SlowMotion
extends RefCounted
## Hitstop and the perfect dodge's slow motion: the time scale until a wall-clock end. Read every
## frame (scale_at) instead of reset by a timer, which can fire a frame before the end and leave
## the game slowed for good.

var _scale := 1.0
var _until_ms := 0


## Slows to scale for seconds from now_ms, unless a slowdown that ends later is running.
func start(scale: float, seconds: float, now_ms: int) -> void:
	var until := now_ms + int(seconds * 1000)
	if until <= _until_ms:
		return
	_until_ms = until
	_scale = scale


func scale_at(now_ms: int) -> float:
	return _scale if now_ms < _until_ms else 1.0
