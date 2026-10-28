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
## {tile: true} of the tiles around the area whose center lies outside it, the walls enemies
## path around (Pathing.find).
var walls := {}
## The obstacles' tiles in world tiles and each one's RoomObstacle.Kind, in the order of the
## rooms; the client draws them and, with gates, rebuilds solid from them.
var obstacles: Array[Rect2i] = []
var obstacle_kinds := PackedByteArray()
## Gate k fills the last tile column of corridor k, the way from room k to room k + 1, and is
## shut until room k is cleared (cleared >= k). The way back never shuts.
var gates: Array[Rect2i] = []
## {tile: true} of the obstacle tiles and the tiles of the gates still shut.
var solid := {}
## walls and solid: what no body walks into and enemies path around.
var blocked := {}
var spawn: Vector2
var exit: Vector2
## The end chest, in the middle of the end room, and {player id: true} of those who opened it.
var chest: Vector2
var opened := {}
## Index of the deepest room whose enemies have spawned; the start room's never do.
var reached := 0
## Index of the deepest room cleared of every enemy since, which healed those inside. Only
## set_cleared changes it, which keeps solid in step.
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
			rooms.append(Rect2(_snap(start - Vector2(0, def.size.y / 2)), def.size))
			continue
		var last := rooms.back() as Rect2
		# Keep at least a corridor's width of height in common with the last room, less the
		# up to half a tile that snapping to the grid moves it.
		var drift := (last.size.y + def.size.y) / 2 - t.corridor_width - WorldGen.TILE / 2.0
		var center_y := last.get_center().y + rng.randf_range(-drift, drift)
		var room := Rect2(
			_snap(Vector2(last.end.x + t.corridor_length, center_y - def.size.y / 2)), def.size
		)
		var top := maxf(last.position.y, room.position.y)
		var bottom := minf(last.end.y, room.end.y)
		var rows := Vector2i(
			roundi(top / WorldGen.TILE), roundi((bottom - t.corridor_width) / WorldGen.TILE)
		)
		var y := rng.randi_range(rows.x, maxi(rows.x, rows.y)) * float(WorldGen.TILE)
		area.append(Rect2(Vector2(last.end.x, y), Vector2(t.corridor_length, t.corridor_width)))
		rooms.append(room)
	area.append_array(rooms)
	spawn = Vector2(rooms[0].position.x + DOOR_INSET, rooms[0].get_center().y)
	var end := rooms.back() as Rect2
	exit = Vector2(end.end.x - DOOR_INSET, end.get_center().y)
	chest = end.get_center()
	var bounds := rooms[0]
	for rect in area:
		bounds = bounds.merge(rect)
	var low := Building.tile_of(bounds.position) - Vector2i.ONE
	var high := Building.tile_of(bounds.end) + Vector2i.ONE
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var center := Building.tile_center(Vector2i(x, y))
			if clamp_to(area, center) != center:
				walls[Vector2i(x, y)] = true
	for i in rooms.size():
		var origin := Building.tile_of(rooms[i].position)
		for obstacle in defs[i].obstacles:
			obstacles.append(Rect2i(origin + obstacle.tiles.position, obstacle.tiles.size))
			obstacle_kinds.append(obstacle.kind)
	var tile_width := roundi(t.corridor_length / WorldGen.TILE)
	for i in rooms.size() - 1:
		var corridor := Rect2i(Building.tile_of(area[i].position), Vector2i.ONE)
		corridor.position.x += tile_width - 1
		corridor.size.y = roundi(area[i].size.y / WorldGen.TILE)
		gates.append(corridor)
	set_cleared(0)


## Sets cleared and rebuilds solid and blocked: the gates up to it are open from now on.
func set_cleared(count: int) -> void:
	cleared = count
	solid = solid_tiles(obstacles, gates, count)
	blocked = walls.duplicate()
	blocked.merge(solid)


## {tile: true} of the obstacles and of every gate k > cleared. The client builds its own the
## same way from what Net.dungeon sends.
static func solid_tiles(
	obstacle_tiles: Array[Rect2i], gate_tiles: Array[Rect2i], cleared_count: int
) -> Dictionary:
	var out := {}
	var shut: Array[Rect2i] = obstacle_tiles.duplicate()
	for k in gate_tiles.size():
		if k > cleared_count:
			shut.append(gate_tiles[k])
	for rect in shut:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				out[Vector2i(x, y)] = true
	return out


## The center of the nearest tile inside the area that is not blocked, found in rings of tiles
## around at; at itself if its tile is free.
func open_spot(at: Vector2) -> Vector2:
	var origin := Building.tile_of(at)
	for ring in range(0, 40):
		var best := Vector2.INF
		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var tile := origin + Vector2i(x, y)
				var center := Building.tile_center(tile)
				if blocked.has(tile) or clamp_to(area, center) != center:
					continue
				if best == Vector2.INF or center.distance_to(at) < best.distance_to(at):
					best = center
		if best != Vector2.INF:
			return at if ring == 0 else best
	return at


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


## A position moved to the nearest tile corner, so rooms and corridors cover whole tiles.
static func _snap(at: Vector2) -> Vector2:
	return at.snappedf(WorldGen.TILE)


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
