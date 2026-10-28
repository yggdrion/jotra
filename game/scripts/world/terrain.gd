class_name Terrain
## Height levels of the overworld (PLAN §5.1, M23), from the seed on both sides like the biomes:
## sunken ground, plain ground and raised plateaus. Heights are sampled on a lattice every
## LATTICE tiles, a lattice point keeps its level only inside a 3×3 block of its level (others
## take their neighbours' level), and tiles read the lattice bilinearly, so every level is broad
## and no tiny patch or pit is left. A tile with a lower tile among its eight neighbours is a cliff:
## it blocks bodies and projectiles, unless the edge crosses one of the ramp windows scattered
## over the grid, where it is walkable.

enum Level { SUNKEN, GROUND, RAISED }

## Bits of a tile's terrain byte: which of its four neighbours lie lower (N, E, S, W), whether it
## is a cliff (any of its eight neighbours lower) and whether that cliff is a ramp.
const LOWER_N := 1
const LOWER_E := 2
const LOWER_S := 4
const LOWER_W := 8
const CLIFF := 16
const RAMP := 32
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
## Within this many tiles of the spawn everything is ground: the workbench, the barrow and the
## first fights stand on open, even ground.
const FLAT_RADIUS := 48
## One ramp window of RAMP_SIZE² tiles per RAMP_CELL² cell, at a spot hashed from the seed; the
## cliff tiles inside it are a ramp if there are at least RAMP_MIN of them (not a clipped corner).
const RAMP_CELL := 12
const RAMP_SIZE := 4
const RAMP_MIN := 3


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
	var _ramps := {}  # ramp cell -> whether its window holds a ramp

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
				var cell := Rect2i(base * LATTICE, Vector2i.ONE * LATTICE).intersection(area)
				for y in range(cell.position.y, cell.end.y):
					var fy := float(y - base.y * LATTICE) / LATTICE
					var row := (y - area.position.y) * area.size.x - area.position.x
					for x in range(cell.position.x, cell.end.x):
						var fx := float(x - base.x * LATTICE) / LATTICE
						var height := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
						_grid[row + x] = Terrain.level_of(height)

	func level_at(tile: Vector2i) -> Level:
		if _covered.has_point(tile):
			var at := tile - _covered.position
			return _grid[at.y * _covered.size.x + at.x] as Level
		if _levels.has(tile):
			return _levels[tile]
		var at := Vector2(tile) / LATTICE
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
	## covered area must reach RAMP_SIZE + 1 tiles past them.
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
					):
						bits |= CLIFF
						if _ramp_at(origin + Vector2i(x, y)):
							bits |= RAMP
				out[y * side + x] = bits
				i += 1
		return out

	func is_cliff(tile: Vector2i) -> bool:
		var level := level_at(tile)
		for dir in AROUND:
			if level_at(tile + dir) < level:
				return true
		return false

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
		var cell := Vector2i((Vector2(tile) / RAMP_CELL).floor())
		var window := _window(cell)
		if not window.has_point(tile):
			return false
		if not _ramps.has(cell):
			var count := 0
			for y in range(window.position.y, window.end.y):
				for x in range(window.position.x, window.end.x):
					if is_cliff(Vector2i(x, y)):
						count += 1
			_ramps[cell] = count >= RAMP_MIN
		return _ramps[cell]

	func _window(cell: Vector2i) -> Rect2i:
		var roll := absi(hash([_seed, cell.x, cell.y, "ramp"]))
		var spread := RAMP_CELL - RAMP_SIZE + 1
		var offset := Vector2i(roll % spread, (roll / spread) % spread)
		return Rect2i(cell * RAMP_CELL + offset, Vector2i.ONE * RAMP_SIZE)


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
