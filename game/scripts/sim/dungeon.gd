class_name Dungeon
extends RefCounted
## One run through a dungeon instance (PLAN §4.8): its rooms, laid out in a slot of its own far
## from the overworld so no run sees another or the world, and the players inside. Each player's
## inventory is snapshotted on entry (SimWorld keeps it); dying restores it, the exit keeps what
## was found. Rooms are rects in world px; the walkable area is their union, and the client and
## server keep players inside it with the same clamp_to.
# ponytail: one fixed test room until the layout is generated from room chunks.

## The first slot's top-left corner and the distance between slots, in px: far beyond any view
## (SimWorld.VIEW_CHUNKS), yet close enough to 0 that float positions stay precise.
const ORIGIN := Vector2(0, 200_000)
const SLOT_SPACING := 20_000.0
const TEST_ROOM := Vector2(480, 320)

var slot: int
## Sim time the run opened; others may join it for Tuning.dungeon_join_window.
var opened_at: float
var rooms: Array[Rect2] = []
var spawn: Vector2
var exit: Vector2
## {player id: true} of those inside.
var players := {}


func _init(run_slot: int, now: float) -> void:
	slot = run_slot
	opened_at = now
	var origin := ORIGIN + Vector2(slot * SLOT_SPACING, 0)
	rooms.append(Rect2(origin, TEST_ROOM))
	spawn = origin + Vector2(32, TEST_ROOM.y / 2)
	exit = origin + Vector2(TEST_ROOM.x - 32, TEST_ROOM.y / 2)


## Whether a position lies in this run's slot, rooms or not: what belongs to the run.
func owns(at: Vector2) -> bool:
	var origin := ORIGIN + Vector2(slot * SLOT_SPACING, 0)
	return Rect2(origin, Vector2(SLOT_SPACING, SLOT_SPACING)).has_point(at)


## The closest point to at inside the rooms; at itself if it is inside one.
static func clamp_to(walkable: Array[Rect2], at: Vector2) -> Vector2:
	var best := at
	var best_distance := INF
	for room in walkable:
		var inside := at.clamp(room.position, room.end)
		var distance := inside.distance_squared_to(at)
		if distance < best_distance:
			best = inside
			best_distance = distance
	return best
