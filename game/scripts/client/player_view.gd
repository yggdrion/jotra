class_name PlayerView
extends Node2D
## A player standing on its position (feet at the origin): a walk sheet facing the way it last
## moved or swung, a health bar once hurt, a white or red flash on hits, an afterimage while
## dashing, and the weapon in hand: held for the own player, shown for others while they swing.
## A swing sweeps the weapon through its arc with the timing of its AttackDef (a light one from
## the side the last one ended on, a heavy one pulling back first), steps the body toward the
## aim and leaves a smear behind the blade.

## Sheet columns per facing; rows are walk frames, square, as many as fit.
enum Facing { DOWN, UP, LEFT, RIGHT }

const SHEETS: Array[Texture2D] = [
	preload("res://assets/dark_knight/knight_walk.png"),
	preload("res://assets/dark_knight/knight_blue_walk.png"),
]
## Multiplied into the sheet, the second half of a look (Net.player_z).
const TINTS: Array[Color] = [
	Color.WHITE,
	Color(1.0, 0.75, 0.7),
	Color(0.75, 0.9, 1.0),
	Color(0.8, 1.0, 0.75),
	Color(1.0, 0.95, 0.65),
	Color(0.85, 0.75, 1.0),
]
const FRAME_MS := 110
## How far below a frame's bottom edge the feet stand, px.
const FEET := 3
## Weapon icons, px square.
const ICON := 16
## The body's height above the feet, where the health bar goes.
const BODY := 28
## Keeps walking this long after the last move, so frames without one don't flicker to idle.
const WALK_GRACE_MS := 100
const FLASH_MS := 100
const FLASH := Color(4, 4, 4)
const HURT := Color(2.2, 0.5, 0.5)
const BAR_WIDTH := 16.0
const RADIUS := 6.0
## Faster than this (px a second) is a dash, leaving an afterimage.
const DASH_SPEED := 250.0
const GHOST_EVERY_MS := 25
const GHOST_MS := 220
const GHOST := Color(0.6, 0.85, 1.0, 0.5)
## How far the weapon sits from the body's center, and how far back a heavy pulls it (radians).
const HAND := 9.0
const PULL_BACK_ANGLE := 0.6
## The share of a swing the smear trails behind the blade.
const SMEAR := 0.4

var own := false
## Its character's look (Net.player_z): which sheet, in which tint.
var look := 0
## 0..1 of a bow drawn, shown as a ring that fills; 0: not drawing.
var draw_share := 0.0
## Held and drawn all the time for the own player; others show it only while swinging.
var holding := false
var weapon := &""
## 0..1, from the snapshots.
var health := 1.0:
	set(value):
		if value != health:
			health = value
			queue_redraw()
## What the pose does to the body sprite, set by subclasses and swings each frame: an offset
## from the feet, a rotation about them, a scale and an opacity.
var pose_offset := Vector2.ZERO
var pose_rot := 0.0
var pose_scale := Vector2.ONE
var pose_alpha := 1.0
## Where this one looks between swings (the own player: toward the mouse); zero looks along
## the walking direction.
var aim := Vector2.ZERO

var _flash_until := 0
var _hurt_until := 0
var _swing_start := 0
var _swing_end := 0
var _swing_aim := Vector2.RIGHT
var _swing: AttackDef
var _swing_flip := 1.0
var _facing := Facing.DOWN
var _walk_until := 0
var _last_position := Vector2.INF
var _ghosts := []  # [ms, global position, sheet row, facing]
var _ghost_at := 0


func flash() -> void:
	_flash_until = Time.get_ticks_msec() + FLASH_MS
	queue_redraw()


## Red for a hit that hurt this one.
func hurt() -> void:
	_hurt_until = Time.get_ticks_msec() + FLASH_MS * 2
	queue_redraw()


## Shows a swing toward aim; weapon (not needed for the own player) is what it swings.
func swing(aim: Vector2, move: AttackDef, weapon_id := &"") -> void:
	var now := Time.get_ticks_msec()
	if weapon_id != &"":
		weapon = weapon_id
	if move.pull_back == 0.0:
		_swing_flip = -_swing_flip
	else:
		_swing_flip = 1.0
	_swing_aim = aim.normalized()
	_swing = move
	_swing_start = now
	_swing_end = now + int(move.swing_time * 1000)
	_face(aim)
	queue_redraw()


func sheet() -> Texture2D:
	return SHEETS[sheet_of(look)]


func tint() -> Color:
	var now := Time.get_ticks_msec()
	if now < _flash_until:
		return FLASH
	return HURT if now < _hurt_until else TINTS[tint_of(look)]


## A sheet's frame size: four facings side by side.
static func frame_of(of_sheet: Texture2D) -> int:
	return of_sheet.get_width() / Facing.size()


## The sheet index of a look (Net.player_z), the first half of it.
static func sheet_of(of_look: int) -> int:
	return clampi(of_look / TINTS.size(), 0, SHEETS.size() - 1)


static func tint_of(of_look: int) -> int:
	return posmod(of_look, TINTS.size())


## 0..1 through the swing being shown, -1 when none.
func swing_progress() -> float:
	var now := Time.get_ticks_msec()
	if _swing == null or now >= _swing_end:
		return -1.0
	return float(now - _swing_start) / maxf(_swing_end - _swing_start, 1.0)


func _face(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		_facing = Facing.RIGHT if direction.x > 0 else Facing.LEFT
	else:
		_facing = Facing.DOWN if direction.y > 0 else Facing.UP


func _facing_vector() -> Vector2:
	return [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT][_facing]


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var moved := position - _last_position if _last_position.is_finite() else Vector2.ZERO
	_last_position = position
	if moved.length() > 0.01:
		_walk_until = now + WALK_GRACE_MS
	if swing_progress() < 0.0:
		if aim != Vector2.ZERO:
			_face(aim)
		elif moved.length() > 0.01:
			_face(moved)
	if moved.length() > DASH_SPEED * delta and delta > 0.0 and now - _ghost_at >= GHOST_EVERY_MS:
		_ghost_at = now
		_ghosts.append([now, global_position, _row(now), _facing])
	while not _ghosts.is_empty() and now - _ghosts[0][0] > GHOST_MS:
		_ghosts.pop_front()
	_pose(now)
	queue_redraw()


## Sets the pose_* of this frame. A swing steps the body toward the aim: a light one in one
## beat, a heavy one back first, then forward.
func _pose(_now: int) -> void:
	pose_offset = Vector2.ZERO
	pose_rot = 0.0
	pose_scale = Vector2.ONE
	pose_alpha = 1.0
	var p := swing_progress()
	if p < 0.0:
		return
	var back := _swing.pull_back
	if back > 0.0 and p < back:
		pose_offset = -_swing_aim * 2.0 * ease(p / back, 0.4)
	elif back > 0.0:
		pose_offset = _swing_aim * _swing.lunge * sin(PI * (p - back) / (1.0 - back) * 0.5)
	else:
		pose_offset = _swing_aim * _swing.lunge * sin(PI * p)


func _row(now: int) -> int:
	var frames := sheet().get_height() / frame_of(sheet())
	return (now / FRAME_MS) % frames if now < _walk_until else 0


func _draw() -> void:
	var now := Time.get_ticks_msec()
	var frame := frame_of(sheet())
	var body := Rect2(-frame / 2.0, -frame + FEET, frame, frame)
	for ghost: Array in _ghosts:
		var fade := 1.0 - float(now - ghost[0]) / GHOST_MS
		var at: Vector2 = to_local(ghost[1])
		draw_texture_rect_region(
			sheet(),
			Rect2(at + body.position, body.size),
			Rect2(ghost[3] * frame, ghost[2] * frame, frame, frame),
			Color(GHOST, GHOST.a * fade)
		)
	var region := Rect2(_facing * frame, _row(now) * frame, frame, frame)
	draw_set_transform(pose_offset, pose_rot, pose_scale)
	var color := tint()
	color.a *= pose_alpha
	draw_texture_rect_region(sheet(), body, region, color)
	draw_set_transform(Vector2.ZERO)
	if health < 1.0:
		var bar := Rect2(-BAR_WIDTH / 2, -BODY - 5, BAR_WIDTH, 2)
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), Color("e43b44"))
	if draw_share > 0.0:
		var ring := Color.WHITE if draw_share >= 1.0 else Color(1, 1, 1, 0.6)
		draw_arc(Vector2(0, -RADIUS), 10.0, -PI / 2, -PI / 2 + TAU * draw_share, 24, ring, 2)
	_draw_weapon()


## The weapon in hand, and while swinging the smear behind it.
func _draw_weapon() -> void:
	var def := Content.item(weapon)
	var p := swing_progress()
	if def == null or def.icon == null or (p < 0.0 and not holding):
		return
	var center := Vector2(0, -RADIUS) + pose_offset
	var idle := aim if aim != Vector2.ZERO else _facing_vector()
	var angle := _swing_aim.angle() if p >= 0.0 else idle.angle() + 0.9
	if p >= 0.0:
		angle += _sweep(p)
		_draw_smear(center, p)
	var dir := Vector2.from_angle(angle)
	# The icon's blade points up and right: turn it to point along dir.
	draw_set_transform(center + dir * HAND, angle + PI / 4, Vector2.ONE)
	draw_texture_rect(def.icon, Rect2(-ICON / 2.0, -ICON / 2.0, ICON, ICON), false)
	draw_set_transform(Vector2.ZERO)


## The blade's angle from the aim at progress p of the swing: the swing's arc swept with an
## ease-out (fast through the middle, slowing at the end), after a heavy's pull-back.
func _sweep(p: float) -> float:
	var half := deg_to_rad(_swing.arc) / 2 * _swing_flip
	var start := -half
	var back := _swing.pull_back
	if back > 0.0:
		start -= PULL_BACK_ANGLE * _swing_flip
		if p < back:
			return lerpf(-half, start, ease(p / back, 0.4))
		p = (p - back) / (1.0 - back)
	return lerpf(start, half, 1.0 - pow(1.0 - p, 3.0))


func _draw_smear(center: Vector2, p: float) -> void:
	var back := _swing.pull_back
	if p < back:
		return
	var steps := 6
	var from := maxf(p - SMEAR, back)
	for i in steps:
		var a := _swing_aim.angle() + _sweep(lerpf(from, p, float(i) / steps))
		var b := _swing_aim.angle() + _sweep(lerpf(from, p, float(i + 1) / steps))
		draw_arc(
			center, _swing.reach * 0.85, a, b, 3, Color(1, 1, 1, 0.6 * float(i + 1) / steps), 3
		)
