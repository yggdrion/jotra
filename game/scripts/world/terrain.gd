class_name Terrain
## Height levels of the overworld (PLAN §5.1, M23), from the seed on both sides like the biomes:
## sunken ground, plain ground and raised plateaus. Heights are sampled on a lattice every
## LATTICE tiles, a lattice point keeps its level only inside a 3×3 block of its level (others
## take their neighbours' level), and BLOCK² squares of tiles read the lattice bilinearly, so
## every level is broad, no tiny patch or pit is left and edges run straight like the art's. A tile
## with a lower tile among its eight neighbours is a cliff, and so are the FACE_SOLID rows of rock
## face above lower ground to the south (seen from above, a south edge shows its face): cliffs
## block bodies and projectiles, unless they lie in one of the ramp windows scattered over the
## grid, where they are walkable.

enum Level { SUNKEN, GROUND, RAISED }

## Bits of a tile's terrain byte: which of its four neighbours lie lower (N, E, S, W), whether it
## is a cliff (any of its eight neighbours lower, or a solid face row) and whether that cliff is a
## ramp.
const LOWER_N := 1
const LOWER_E := 2
const LOWER_S := 4
const LOWER_W := 8
const CLIFF := 16
const RAMP := 32
## The cliff art (looks_of) is the tileset's 5×6 plateau: row 0 the spikes a top edge pokes
## into the ground north of it, row 1 the top edge, row 2 the sides, rows 3-5 the south face from
## its top down; column 0 and 4 the rock a left or right edge throws onto the lower ground beside
## it, 1 and 3 the edges themselves, 2 the middle. A look packs the tile's own piece and up to
## three such overhangs (row * 5 + column, plus one; 0 for none) in LOOK_BITS each, and STAIRS.
const LOOK_BITS := 6
const STAIRS := 1 << 24
## Rows of rock face a south edge shows, and how many of them (from the bottom) block.
const FACE_ROWS := 3
const FACE_SOLID := 2
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

## Height noise frequency per tile: plateaus and hollows span a hundred tiles or more.
const FREQUENCY := 0.006
## How much the biome noise lifts the height: marshes lie low, the bone hills high.
const BIOME_PULL := 0.6
## Heights below this are sunken, above RAISED_ABOVE raised.
const SUNKEN_BELOW := -0.4
const RAISED_ABOVE := 0.4
## Tiles between two lattice points.
const LATTICE := 8
## Side of the squares of tiles that share a level; LATTICE is a multiple of it.
const BLOCK := 4
## Within this many tiles of the spawn everything is ground: the workbench, the barrow and the
## first fights stand on open, even ground.
const FLAT_RADIUS := 48
## One ramp window of RAMP_SIZE² tiles per RAMP_CELL² cell, at a spot hashed from the seed; the
## cliff tiles inside it are a ramp if there are at least RAMP_MIN of them (not a clipped corner).
const RAMP_CELL := 10
const RAMP_SIZE := 3
const RAMP_MIN := 3
## Tiles past a chunk the covered area must reach: the ramp windows and face rows next to it.
const MARGIN := RAMP_SIZE + FACE_ROWS + 1


## The heights of one world, cached while it is asked: one per chunk generated (or per tool).
class Field:
	var _seed: int
	var _height := FastNoiseLite.new()
	var _biome: FastNoiseLite
	var _raw := {}  # lattice point -> Level
	var _value := {}  # lattice point -> height after the cleanup
	var _levels := {}  # tile -> Level, outside the covered area
	var _covered := Rect2i()
	var _grid := PackedByteArray()  # Level of each tile of _covered, row by row
	var _rows := PackedByteArray()  # face row (_face_row) of each tile of _covered
	var _ramps := {}  # ramp cell -> its window if it holds a ramp, else an empty rect

	func _init(world_seed: int) -> void:
		_seed = world_seed
		_height.seed = hash([world_seed, "height"])
		_height.frequency = FREQUENCY
		_height.fractal_type = FastNoiseLite.FRACTAL_NONE
		_biome = WorldGen.biome_noise(world_seed)

	## Works out the levels of every tile in area at once, a lattice cell at a time, which is
	## much quicker than tile by tile; level_at reads them from there.
	func cover(area: Rect2i) -> void:
		_covered = area
		_grid.resize(area.size.x * area.size.y)
		var low := Vector2i((Vector2(area.position) / LATTICE).floor())
		var high := Vector2i((Vector2(area.end - Vector2i.ONE) / LATTICE).floor())
		for py in range(low.y, high.y + 1):
			for px in range(low.x, high.x + 1):
				var base := Vector2i(px, py)
				var a := _cleaned(base)
				var b := _cleaned(base + Vector2i(1, 0))
				var c := _cleaned(base + Vector2i(0, 1))
				var d := _cleaned(base + Vector2i(1, 1))
				# One level per BLOCK, read at its middle.
				for by in range(0, LATTICE, BLOCK):
					var fy := (by + BLOCK / 2.0) / LATTICE
					for bx in range(0, LATTICE, BLOCK):
						var fx := (bx + BLOCK / 2.0) / LATTICE
						var level := Terrain.level_of(lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy))
						var block := Rect2i(base * LATTICE + Vector2i(bx, by), Vector2i.ONE * BLOCK)
						block = block.intersection(area)
						for y in range(block.position.y, block.end.y):
							var row := (y - area.position.y) * area.size.x - area.position.x
							for x in range(block.position.x, block.end.x):
								_grid[row + x] = level
		# Face rows from the bottom up, each from the one below it (the last row has none).
		var w := area.size.x
		_rows.resize(_grid.size())
		_rows.fill(0)
		for i in range(_grid.size() - w - 1, -1, -1):
			var level := _grid[i]
			var below := _grid[i + w]
			if below < level:
				_rows[i] = 1
			elif below == level and _rows[i + w] > 0 and _rows[i + w] < FACE_ROWS:
				_rows[i] = _rows[i + w] + 1

	func level_at(tile: Vector2i) -> Level:
		if _covered.has_point(tile):
			var at := tile - _covered.position
			return _grid[at.y * _covered.size.x + at.x] as Level
		if _levels.has(tile):
			return _levels[tile]
		var at := Vector2(Terrain.block_center(tile.x), Terrain.block_center(tile.y)) / LATTICE
		var base := Vector2i(at.floor())
		var f := at - Vector2(base)
		var top := lerpf(_cleaned(base), _cleaned(base + Vector2i(1, 0)), f.x)
		var bottom := lerpf(_cleaned(base + Vector2i(0, 1)), _cleaned(base + Vector2i(1, 1)), f.x)
		var level := Terrain.level_of(lerpf(top, bottom, f.y))
		_levels[tile] = level
		return level

	## The levels of the side² tiles from origin, row by row, out of the covered area.
	func levels_of(origin: Vector2i, side: int) -> PackedByteArray:
		var out := PackedByteArray()
		var w := _covered.size.x
		for y in side:
			var i := (origin.y + y - _covered.position.y) * w + origin.x - _covered.position.x
			out.append_array(_grid.slice(i, i + side))
		return out

	## The terrain bytes (LOWER_*, CLIFF, RAMP) of the side² tiles from origin, row by row; the
	## covered area must reach MARGIN tiles past them.
	func bits_of(origin: Vector2i, side: int) -> PackedByteArray:
		var out := PackedByteArray()
		out.resize(side * side)
		var w := _covered.size.x
		for y in side:
			var i := (origin.y + y - _covered.position.y) * w + origin.x - _covered.position.x
			for x in side:
				var level := _grid[i]
				var bits := 0
				# Nothing lies below sunken ground.
				if level > Level.SUNKEN:
					bits |= LOWER_N if _grid[i - w] < level else 0
					bits |= LOWER_E if _grid[i + 1] < level else 0
					bits |= LOWER_S if _grid[i + w] < level else 0
					bits |= LOWER_W if _grid[i - 1] < level else 0
					if (
						bits
						or _grid[i - w - 1] < level
						or _grid[i - w + 1] < level
						or _grid[i + w - 1] < level
						or _grid[i + w + 1] < level
						or _rows[i] > 0 and _rows[i] <= FACE_SOLID
					):
						bits |= CLIFF
						var tile := origin + Vector2i(x, y)
						var row := _face_row(i)
						# A face is a ramp all the way up where its foot is.
						var foot := tile + Vector2i(0, row - 1) if row > 0 else tile
						if _ramp_at(foot):
							bits |= RAMP
				out[y * side + x] = bits
				i += 1
		return out

	## The face rows (0 off a face) of the side² tiles from origin; no prop stands on one.
	func faces_of(origin: Vector2i, side: int) -> PackedByteArray:
		var out := PackedByteArray()
		var w := _covered.size.x
		for y in side:
			var i := (origin.y + y - _covered.position.y) * w + origin.x - _covered.position.x
			out.append_array(_rows.slice(i, i + side))
		return out

	## The looks (see LOOK_BITS) of the side² tiles from origin, row by row, for drawing.
	func looks_of(origin: Vector2i, side: int) -> PackedInt32Array:
		# Own pieces a tile further out too, as overhangs come from the neighbours.
		var outer := side + 2
		var own := PackedInt32Array()
		own.resize(outer * outer)
		for y in outer:
			for x in outer:
				own[y * outer + x] = _own_piece(origin + Vector2i(x - 1, y - 1))
		var out := PackedInt32Array()
		out.resize(side * side)
		for y in side:
			for x in side:
				var k := (y + 1) * outer + x + 1
				var look := own[k] + 1
				if own[k] < 0:
					var shift := LOOK_BITS
					for piece in _overhangs(own, k, outer):
						look |= (piece + 1) << shift
						shift += LOOK_BITS
				var tile := origin + Vector2i(x, y)
				if _rows[_index(tile)] == 1 and _ramp_at(tile):
					look |= STAIRS
				out[y * side + x] = look
		return out

	## The piece of the plateau art a tile shows of itself, -1 for none (no edge, or a ramp).
	func _own_piece(tile: Vector2i) -> int:
		var i := _index(tile)
		var w := _covered.size.x
		var level := _grid[i]
		var west := _grid[i - 1] < level
		var east := _grid[i + 1] < level
		var row := _rows[i]
		if row > 0:
			if _ramp_at(tile + Vector2i(0, row - 1)):
				return -1
			var column := 2
			if west or not _same_face(i - 1, row, tile + Vector2i(-1, 0)):
				column = 1
			elif east or not _same_face(i + 1, row, tile + Vector2i(1, 0)):
				column = 3
			return (6 - row) * 5 + column
		var north := _grid[i - w] < level
		if not (north or west or east) or _ramp_at(tile):
			return -1
		var column := 1 if west else (3 if east else 2)
		return (5 if north else 10) + column

	## The rock the neighbours' edges throw onto a tile without a piece of its own.
	func _overhangs(own: PackedInt32Array, k: int, outer: int) -> Array[int]:
		var out: Array[int] = []
		var east := own[k + 1]
		if east >= 0 and east % 5 == 1:
			out.append(east - 1)
		var west := own[k - 1]
		if west >= 0 and west % 5 == 3:
			out.append(west + 1)
		var south := own[k + outer]
		if south >= 5 and south < 10:
			out.append(south - 5)
		elif own[k + outer + 1] == 6 and east < 0:
			out.append(0)
		elif own[k + outer - 1] == 8 and west < 0:
			out.append(4)
		return out

	func _index(tile: Vector2i) -> int:
		var at := tile - _covered.position
		return at.y * _covered.size.x + at.x

	func is_cliff(tile: Vector2i) -> bool:
		var level := level_at(tile)
		for dir in AROUND:
			if level_at(tile + dir) < level:
				return true
		for k in range(1, FACE_SOLID + 1):
			var below := level_at(tile + Vector2i(0, k))
			if below != level:
				return below < level
		return false

	## Which row of a south face the tile at grid index i is, 0 if none: lower ground lies that
	## many tiles south of it, with only its own level between.
	func _face_row(i: int) -> int:
		return _rows[i]

	## Whether the tile at grid index i (tile) carries on a face row: the same row, no ramp.
	func _same_face(i: int, row: int, tile: Vector2i) -> bool:
		return _face_row(i) == row and not _ramp_at(tile + Vector2i(0, row - 1))

	func _raw_height(point: Vector2i) -> float:
		var tile := point * LATTICE
		if Vector2(tile).length() <= FLAT_RADIUS:
			return 0.0
		var pull := BIOME_PULL * _biome.get_noise_2d(tile.x, tile.y)
		return _height.get_noise_2d(tile.x, tile.y) + pull

	func _raw_level(point: Vector2i) -> Level:
		if not _raw.has(point):
			_raw[point] = Terrain.level_of(_raw_height(point))
		return _raw[point]

	## The lattice point's height, or the middle of its neighbours' commonest level when it lies
	## in no 3×3 block of its own level.
	func _cleaned(point: Vector2i) -> float:
		if _value.has(point):
			return _value[point]
		var level := _raw_level(point)
		var value := _raw_height(point) if _in_block(point, level) else _middle(_common(point))
		_value[point] = value
		return value

	func _in_block(point: Vector2i, level: Level) -> bool:
		for cy in range(-1, 2):
			for cx in range(-1, 2):
				var center := point + Vector2i(cx, cy)
				var pure := true
				for dir in AROUND + [Vector2i.ZERO]:
					if _raw_level(center + dir) != level:
						pure = false
						break
				if pure:
					return true
		return false

	## The level most of a lattice point's eight neighbours have; ground on a tie.
	func _common(point: Vector2i) -> Level:
		var counts := [0, 0, 0]
		for dir in AROUND:
			counts[_raw_level(point + dir)] += 1
		var best := Level.GROUND
		for level: Level in [Level.SUNKEN, Level.RAISED]:
			if counts[level] > counts[best]:
				best = level
		return best

	func _middle(level: Level) -> float:
		match level:
			Level.SUNKEN:
				return SUNKEN_BELOW - 0.2
			Level.RAISED:
				return RAISED_ABOVE + 0.2
		return 0.0

	func _ramp_at(tile: Vector2i) -> bool:
		var cell := Vector2i(floori(float(tile.x) / RAMP_CELL), floori(float(tile.y) / RAMP_CELL))
		if not _ramps.has(cell):
			var window := _window(cell)
			var count := 0
			for y in range(window.position.y, window.end.y):
				for x in range(window.position.x, window.end.x):
					if is_cliff(Vector2i(x, y)):
						count += 1
			_ramps[cell] = window if count >= RAMP_MIN else Rect2i()
		return (_ramps[cell] as Rect2i).has_point(tile)

	func _window(cell: Vector2i) -> Rect2i:
		var roll := absi(hash([_seed, cell.x, cell.y, "ramp"]))
		var spread := RAMP_CELL - RAMP_SIZE + 1
		var offset := Vector2i(roll % spread, (roll / spread) % spread)
		return Rect2i(cell * RAMP_CELL + offset, Vector2i.ONE * RAMP_SIZE)


## The middle tile of the BLOCK a tile coordinate lies in, where its level is read.
static func block_center(at: int) -> int:
	return floori(float(at) / BLOCK) * BLOCK + BLOCK / 2


static func level_of(height: float) -> Level:
	if height < SUNKEN_BELOW:
		return Level.SUNKEN
	if height > RAISED_ABOVE:
		return Level.RAISED
	return Level.GROUND


## Whether a terrain byte blocks: a cliff that is no ramp.
static func blocks(bits: int) -> bool:
	return bits & CLIFF != 0 and bits & RAMP == 0


## The blocking tiles of a chunk, by its terrain bytes.
static func solid_tiles(coord: Vector2i, terrain: PackedByteArray) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in terrain.size():
		if blocks(terrain[id]):
			out.append(Building.tile_at(coord, id))
	return out


## Whether the straight line between two positions crosses none of tiles ({tile: true}), so a
## hit lands across it: no swing or bite reaches over a cliff.
static func line_clear(tiles: Dictionary, from: Vector2, to: Vector2) -> bool:
	if tiles.is_empty():
		return true
	var steps := maxi(ceili(from.distance_to(to) / 4.0), 1)
	for i in range(1, steps):
		if tiles.has(Building.tile_of(from.lerp(to, float(i) / steps))):
			return false
	return true
