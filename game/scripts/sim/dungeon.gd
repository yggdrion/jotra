class_name Dungeon
extends RefCounted
## One run through a dungeon instance (PLAN §4.8): its layout, laid out in a slot of its own far
## from the overworld so no run sees another or the world, and the players inside. Each player's
## inventory is snapshotted on entry (SimWorld keeps it); dying restores it, the exit keeps what
## was found.
##
## The layout chains handmade rooms (RoomDef) eastward: a start room, dungeon_rooms_min to
## dungeon_rooms_max middle rooms and an end room with the exit and the end chest, each joined
## to the next by a corridor at a random height both rooms share. The walkable area is the
## union of the rooms and corridors; the client and server keep players inside it with the same
## clamp_to.

## The first slot's top-left corner and the distance between slots, in px: far beyond any view
## (SimWorld.VIEW_CHUNKS), yet close enough to 0 that float positions stay precise.
const ORIGIN := Vector2(0, 200_000)
const SLOT_SPACING := 20_000.0
## How far from the start room's west wall players arrive, and from the end room's east wall
## the exit stands.
const DOOR_INSET := 32.0

var slot: int
## Sim time the run opened; others may join it for Tuning.dungeon_join_window, and its enemies
## grow stronger with the minutes since.
var opened_at: float
## The rooms in order from the start, as rects in world px, and what each was made from.
var rooms: Array[Rect2] = []
var defs: Array[RoomDef] = []
## Rooms and corridors: where players and enemies may be.
var area: Array[Rect2] = []
var spawn: Vector2
var exit: Vector2
## The end chest, in the middle of the end room, and {player id: true} of those who opened it.
var chest: Vector2
var opened := {}
## Index of the deepest room whose enemies have spawned; the start room's never do.
var reached := 0
## Index of the deepest room cleared of every enemy since, which healed those inside.
var cleared := 0
## {player id: true} of those inside.
var players := {}


func _init(run_slot: int, now: float, rng: RandomNumberGenerator) -> void:
	slot = run_slot
	opened_at = now
	var t := Content.tuning
	defs.append(_pick(RoomDef.Kind.START, null, rng))
	for i in rng.randi_range(t.dungeon_rooms_min, t.dungeon_rooms_max):
		defs.append(_pick(RoomDef.Kind.MIDDLE, defs.back(), rng))
	defs.append(_pick(RoomDef.Kind.END, null, rng))
	var start := _origin() + Vector2(0, SLOT_SPACING / 2)
	for def in defs:
		if rooms.is_empty():
			rooms.append(Rect2(start - Vector2(0, def.size.y / 2), def.size))
			continue
		var last := rooms.back() as Rect2
		# Keep at least a corridor's width of height in common with the last room.
		var drift := (last.size.y + def.size.y) / 2 - t.corridor_width
		var center_y := last.get_center().y + rng.randf_range(-drift, drift)
		var room := Rect2(
			Vector2(last.end.x + t.corridor_length, center_y - def.size.y / 2), def.size
		)
		var top := maxf(last.position.y, room.position.y)
		var bottom := minf(last.end.y, room.end.y)
		var y := rng.randf_range(top, bottom - t.corridor_width)
		area.append(Rect2(Vector2(last.end.x, y), Vector2(t.corridor_length, t.corridor_width)))
		rooms.append(room)
	area.append_array(rooms)
	spawn = Vector2(rooms[0].position.x + DOOR_INSET, rooms[0].get_center().y)
	var end := rooms.back() as Rect2
	exit = Vector2(end.end.x - DOOR_INSET, end.get_center().y)
	chest = end.get_center()


## Whether an enemy stands within Tuning.chest_lock_radius of the chest, keeping it shut. The
## client asks the same of the enemies it sees.
static func locked(at: Vector2, enemy_positions: Array[Vector2]) -> bool:
	var radius := Content.tuning.chest_lock_radius
	return enemy_positions.any(func(enemy: Vector2) -> bool: return enemy.distance_to(at) <= radius)


## A random room of kind, not the same as after when there is another.
static func _pick(kind: RoomDef.Kind, after: RoomDef, rng: RandomNumberGenerator) -> RoomDef:
	var choices: Array[RoomDef] = []
	for def: RoomDef in Content.rooms.values():
		if def.kind == kind and def != after:
			choices.append(def)
	if choices.is_empty():
		return after
	return choices[rng.randi() % choices.size()]


func _origin() -> Vector2:
	return ORIGIN + Vector2(slot * SLOT_SPACING, 0)


## Whether a position lies in this run's slot, inside the layout or not: what belongs to the run.
func owns(at: Vector2) -> bool:
	return Rect2(_origin(), Vector2(SLOT_SPACING, SLOT_SPACING)).has_point(at)


## Index of the room a position is in, -1 in a corridor or outside.
func room_of(at: Vector2) -> int:
	for i in rooms.size():
		var room := rooms[i]
		if at.clamp(room.position, room.end) == at:
			return i
	return -1


## Minutes since the run opened, for the scaling.
func minutes(now: float) -> float:
	return (now - opened_at) / 60.0


## The closest point to at inside the area; at itself if it is inside.
static func clamp_to(walkable: Array[Rect2], at: Vector2) -> Vector2:
	var best := at
	var best_distance := INF
	for rect in walkable:
		var inside := at.clamp(rect.position, rect.end)
		var distance := inside.distance_squared_to(at)
		if distance < best_distance:
			best = inside
			best_distance = distance
	return best
