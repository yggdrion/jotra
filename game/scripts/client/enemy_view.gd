class_name EnemyView
extends PlayerView
## An enemy in its def's walk sheet at its def's size. While it winds up an attack the ground
## shows the area it will hit (a disc, a sweep cone, an arrow line or a lunge lane) filling as the
## hit lands, and it crouches back; then it lunges forward. A hit recoils it away from the blow, a
## stagger shakes it, a give-up dims it, a death topples and fades it before it is gone. A
## shield shows its blocking arc along the server's facing, which also turns the sprite.

const AREA := Color(0.9, 0.15, 0.1)
const GAVE_UP := Color(0.65, 0.7, 0.9)
const SHIELD := Color(0.75, 0.82, 0.95)
const BLOCK_MS := 150
const STRIKE_MS := 140
const STAGGER_MS := 500
const GAVE_UP_MS := 2500
const DEATH_MS := 450
## Recoil: a hit pushes the body back by this share of the push, fading in this many ms.
const RECOIL := 0.6
const RECOIL_MS := 200

var def: EnemyDef:
	set(value):
		def = value
		scale = Vector2.ONE * def.size
## The server's facing (SimEnemy.facing) for one with a shield, zero for the rest, which face
## the way they walk.
var facing := Vector2.ZERO:
	set(value):
		facing = value
		_face(value)
		queue_redraw()
## Died: it is topped up and shown falling instead of being driven by snapshots.
var dying := false

var _windup_start := 0
var _windup_end := 0
var _area := 0.0
## The unit vector of an arrow line or sweep telegraph, zero for a disc.
var _line := Vector2.ZERO
## Degrees of the sweep cone around _line, 0 for an arrow line.
var _arc := 0.0
var _block_at := -1000
var _strike_at := -1000
var _stagger_at := -1000
var _gave_up_at := -100000
var _recoil_at := -1000
var _recoil := Vector2.ZERO
var _died_at := 0


## An attack that lands in seconds on everything within radius of the enemy, or, with a line
## (a unit vector), on the strip that far along it, or with an arc too, on the cone of arc
## degrees around the line.
func windup(seconds: float, radius: float, line := Vector2.ZERO, arc := 0.0) -> void:
	_line = line
	_arc = arc
	_windup_start = Time.get_ticks_msec()
	_windup_end = _windup_start + int(seconds * 1000)
	_area = radius
	queue_redraw()


## Its shield took a hit.
func block() -> void:
	_block_at = Time.get_ticks_msec()
	queue_redraw()


## Its windup is off and it reels.
func stagger() -> void:
	_windup_end = 0
	_stagger_at = Time.get_ticks_msec()


## The windup landed, hit or not: it lunges.
func strike() -> void:
	_windup_end = 0
	_strike_at = Time.get_ticks_msec()


func give_up() -> void:
	_gave_up_at = Time.get_ticks_msec()


func die() -> void:
	dying = true
	_windup_end = 0
	_died_at = Time.get_ticks_msec()


## Shoved by a hit along push (px).
func recoil(push: Vector2) -> void:
	_recoil = push * RECOIL
	_recoil_at = Time.get_ticks_msec()


func sheet() -> Texture2D:
	return def.sheet


func tint() -> Color:
	var base := super()
	if base != Color.WHITE:
		return base
	if def.tint != Color.WHITE:
		return def.tint
	if Time.get_ticks_msec() - _gave_up_at < GAVE_UP_MS:
		return GAVE_UP
	return Color.WHITE


func _face(direction: Vector2) -> void:
	super(facing if facing != Vector2.ZERO else direction)


func _ahead() -> Vector2:
	return facing.normalized() if facing != Vector2.ZERO else _facing_vector()


func _pose(now: int) -> void:
	super(now)
	var ahead := _ahead()
	if now < _windup_end:
		var p := float(now - _windup_start) / maxf(_windup_end - _windup_start, 1.0)
		pose_offset = -ahead * 3.0 * ease(p, 0.5)
		pose_scale = Vector2(1.0 + 0.12 * p, 1.0 - 0.18 * p)
	var since := now - _strike_at
	if since < STRIKE_MS:
		var k := sin(PI * since / STRIKE_MS)
		pose_offset = ahead * 6.0 * k
		pose_scale = Vector2(1.0 - 0.1 * k, 1.0 + 0.15 * k)
	since = now - _recoil_at
	if since < RECOIL_MS:
		pose_offset += _recoil * (1.0 - float(since) / RECOIL_MS)
	since = now - _stagger_at
	if since < STAGGER_MS:
		pose_offset.x += sin(since / 18.0) * 1.2 * (1.0 - float(since) / STAGGER_MS)
		pose_rot = sin(since / 30.0) * 0.12
	if dying:
		var k := clampf(float(now - _died_at) / DEATH_MS, 0.0, 1.0)
		pose_rot = ease(k, 0.3) * (PI / 2) * signf(_recoil.x if _recoil.x != 0.0 else 1.0)
		pose_scale = Vector2(1.0, 1.0 - 0.3 * k)
		pose_alpha = 1.0 - k
		if k >= 1.0:
			queue_free()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	if now < _windup_end and not dying:
		var r := _area / scale.x
		var p := float(now - _windup_start) / maxf(_windup_end - _windup_start, 1.0)
		if _arc > 0.0:
			_draw_cone(r, p)
		elif _line != Vector2.ZERO and def.lunge_distance > 0:
			_draw_lane(r, def.lunge_reach / scale.x, p)
		elif _line != Vector2.ZERO:
			var width := 2.0 * Content.tuning.projectile_radius / scale.x
			draw_line(Vector2.ZERO, _line * r, Color(AREA, 0.3), width)
			draw_line(Vector2.ZERO, _line * r * p, Color(AREA, 0.85), width)
		else:
			draw_circle(Vector2.ZERO, r * p, Color(AREA, 0.35))
			draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(AREA, 0.85), 1.0)
	if def.block_arc > 0 and not dying:
		var edge := deg_to_rad(def.block_arc) / 2
		var heading := _ahead().angle()
		var lit := clampf(1.0 - float(now - _block_at) / BLOCK_MS, 0.0, 1.0)
		var color := SHIELD.lerp(Color.WHITE, lit)
		draw_arc(Vector2(0, -6), 12, heading - edge, heading + edge, 12, color, 2.0)
	super()


## The lunge telegraph: the lane it dashes along, half_width to each side, filling out from
## the enemy as the windup runs.
func _draw_lane(length: float, half_width: float, p: float) -> void:
	var side := _line.orthogonal() * half_width
	var lane := PackedVector2Array([side, _line * length + side, _line * length - side, -side])
	if p > 0.05:
		var fill := _line * length * p
		draw_colored_polygon(
			PackedVector2Array([side, fill + side, fill - side, -side]), Color(AREA, 0.35)
		)
	lane.append(side)
	draw_polyline(lane, Color(AREA, 0.85), 1.0)


## The sweep telegraph: the cone filling out from the enemy as the windup runs, its edge drawn.
func _draw_cone(r: float, p: float) -> void:
	var half := deg_to_rad(_arc) / 2
	var heading := _line.angle()
	var fill := PackedVector2Array([Vector2.ZERO])
	var edge := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		var dir := Vector2.from_angle(heading - half + 2 * half * i / 12.0)
		fill.append(dir * r * p)
		edge.append(dir * r)
	edge.append(Vector2.ZERO)
	if p > 0.05:
		draw_colored_polygon(fill, Color(AREA, 0.35))
	draw_polyline(edge, Color(AREA, 0.85), 1.0)
