class_name Pathing
## Enemy routes around blocking pieces (PLAN §5.2): A* on the tile grid over tiles without a
## blocking piece, eight ways without cutting corners, bounded by a node budget. Tile centers
## are safe to walk between for a body of Building.BODY, so a route never runs into a piece.
## When the target can't be reached within the budget, the route leads to the tile closest to
## it; the enemy walks there and sieges what is in its way.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]
## Px between the body positions clear() checks; the body is grown by half of it so nothing
## between two checks can touch a piece.
const SAMPLE := 4.0
## How many tiles ahead a route's first waypoint may be pulled straight.
const PULL := 8
## The side in tiles of the square around the start a search stays in.
const WINDOW := 64


class Route:
	## Waypoints in px, the first to walk to first; empty when the goal is straight ahead.
	var points: Array[Vector2] = []
	## Whether it reaches the goal's tile; false: it ends as close as the search got.
	var open := true
	## Tiles the search expanded.
	var used := 0


## {tile: true} of the tiles whose piece blocks, what clear() and find() take.
static func blocked_tiles(pieces: Dictionary) -> Dictionary:
	var out := {}
	for tile: Vector2i in pieces:
		if pieces[tile].blocks():
			out[tile] = true
	return out


## Whether a body can walk the straight line from one position to another without touching a
## blocked tile (conservative: a near miss counts as touching).
static func clear(blocked: Dictionary, from: Vector2, to: Vector2) -> bool:
	if blocked.is_empty():
		return true
	var body := Building.BODY + SAMPLE / 2
	var steps := maxi(ceili(from.distance_to(to) / SAMPLE), 1)
	if blocked.size() < steps:
		# Few pieces: none near the line is the common case and quick to rule out.
		var box := Rect2(from, Vector2.ZERO).expand(to).grow(body)
		var near := false
		for tile: Vector2i in blocked:
			if box.intersects(Rect2(Vector2(tile * WorldGen.TILE), Vector2.ONE * WorldGen.TILE)):
				near = true
				break
		if not near:
			return true
	for i in range(1, steps + 1):
		var at := from.lerp(to, float(i) / steps)
		var low := Building.tile_of(at - Vector2(body, body))
		var high := Building.tile_of(at + Vector2(body, body))
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				if blocked.has(Vector2i(x, y)):
					return false
	return true


## The route from one position to another around blocked tiles, expanding at most budget
## tiles of the WINDOW around from.
static func find(blocked: Dictionary, from: Vector2, to: Vector2, budget: int) -> Route:
	var route := Route.new()
	if clear(blocked, from, to):
		return route
	var start := Building.tile_of(from)
	var goal := Building.tile_of(to)
	var origin := start - Vector2i(WINDOW, WINDOW) / 2
	var cost := PackedFloat32Array()
	cost.resize(WINDOW * WINDOW)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(WINDOW * WINDOW)
	var closed := PackedByteArray()
	closed.resize(WINDOW * WINDOW)
	var start_index := _index(start, origin)
	cost[start_index] = 0.0
	came[start_index] = start_index
	var heap := _Heap.new()
	heap.push(_guess(start, goal), start_index)
	var best := start_index
	var best_guess := _guess(start, goal)
	var reached := false
	var side := [false, false, false, false]
	while not heap.is_empty() and route.used < budget:
		var index := heap.pop()
		if closed[index]:
			continue
		closed[index] = 1
		var tile := origin + Vector2i(index % WINDOW, index / WINDOW)
		if tile == goal:
			best = index
			reached = true
			break
		route.used += 1
		var guess := _guess(tile, goal)
		if guess < best_guess:
			best = index
			best_guess = guess
		var g0 := cost[index]
		# E, W, S, N first; a diagonal needs both sides it passes open.
		for i in 8:
			var dir := DIRS[i]
			var next := tile + dir
			var shut := blocked.has(next)
			if i < 4:
				side[i] = shut
				if shut:
					continue
			elif shut or side[0 if dir.x > 0 else 1] or side[2 if dir.y > 0 else 3]:
				continue
			var local := next - origin
			if local.x < 0 or local.y < 0 or local.x >= WINDOW or local.y >= WINDOW:
				continue
			var next_index := local.y * WINDOW + local.x
			var g := g0 + (1.0 if i < 4 else 1.4142)
			if g < cost[next_index]:
				cost[next_index] = g
				came[next_index] = index
				heap.push(g + _guess(next, goal), next_index)
	route.open = reached
	var tiles: Array[Vector2i] = []
	var at := best
	while at != start_index:
		tiles.push_front(origin + Vector2i(at % WINDOW, at / WINDOW))
		at = came[at]
	tiles.push_front(start)
	# Walk straight to the furthest of the next few tiles in a clear line.
	var first := 0
	for i in range(mini(PULL, tiles.size() - 1), 0, -1):
		if clear(blocked, from, Building.tile_center(tiles[i])):
			first = i
			break
	# Standing in a blocked tile (a dungeon wall tile whose center is outside the room, the body
	# inside it): its center can't be reached, so the route leaves from where it stands.
	if first == 0 and blocked.has(start) and tiles.size() > 1:
		first = 1
	for i in range(first, tiles.size()):
		route.points.append(Building.tile_center(tiles[i]))
	return route


static func _index(tile: Vector2i, origin: Vector2i) -> int:
	return (tile.y - origin.y) * WINDOW + tile.x - origin.x


## Octile distance in tiles.
static func _guess(from: Vector2i, to: Vector2i) -> float:
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	return maxi(dx, dy) + 0.4142 * mini(dx, dy)


## A binary min-heap of ints by priority.
class _Heap:
	var _keys := PackedFloat32Array()
	var _values := PackedInt32Array()

	func is_empty() -> bool:
		return _values.is_empty()

	func push(key: float, value: int) -> void:
		var i := _values.size()
		_keys.append(key)
		_values.append(value)
		while i > 0:
			var up := (i - 1) >> 1
			if _keys[up] <= key:
				break
			_keys[i] = _keys[up]
			_values[i] = _values[up]
			i = up
		_keys[i] = key
		_values[i] = value

	func pop() -> int:
		var top := _values[0]
		var last := _values.size() - 1
		var key := _keys[last]
		var value := _values[last]
		_keys.resize(last)
		_values.resize(last)
		if last == 0:
			return top
		var i := 0
		while true:
			var child := 2 * i + 1
			if child >= last:
				break
			if child + 1 < last and _keys[child + 1] < _keys[child]:
				child += 1
			if _keys[child] >= key:
				break
			_keys[i] = _keys[child]
			_values[i] = _values[child]
			i = child
		_keys[i] = key
		_values[i] = value
		return top
