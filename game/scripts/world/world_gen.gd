class_name WorldGen
## Seeded world generation, shared by server and client: the same seed and chunk always give
## the same tiles and props, so only deltas against it are stored and sent. Also the chunk
## grid math both sides use.

enum Biome { MEADOW, FOREST, MARSH, BONE_HILLS }
enum Prop { TREE, ROCK }

const TILE := 16
## Tiles per chunk side.
const CHUNK := 32
const CHUNK_PX := TILE * CHUNK

# ponytail: placeholder biomes picked from one noise value; real biomes come with art and lore.
const BIOME_COLORS: Array[Color] = [
	Color("3e8948"), Color("265c42"), Color("3a4466"), Color("8b9bb4")
]
## Upper noise bound of MARSH, MEADOW, FOREST; above the last is BONE_HILLS.
const BIOME_BOUNDS: Array[float] = [-0.3, 0.05, 0.35]
## Chance per tile of [tree, rock], by biome.
const PROP_CHANCE: Array[Array] = [[0.02, 0.005], [0.12, 0.01], [0.03, 0.0], [0.0, 0.06]]
## Noise frequency per tile: biomes span a few hundred tiles.
const BIOME_FREQUENCY := 0.004


## {tiles: PackedByteArray of Biome, row by row; props: {id: Prop}}. A prop's id is its tile
## index in the chunk, so it is stable and unique per chunk.
static func chunk(world_seed: int, coord: Vector2i) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = BIOME_FREQUENCY
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, coord])
	var tiles := PackedByteArray()
	tiles.resize(CHUNK * CHUNK)
	var props := {}
	for y in CHUNK:
		for x in CHUNK:
			var id := y * CHUNK + x
			var tile := coord * CHUNK + Vector2i(x, y)
			var biome := _biome(noise.get_noise_2d(tile.x, tile.y))
			tiles[id] = biome
			var chance: Array = PROP_CHANCE[biome]
			var roll := rng.randf()
			if roll < chance[0]:
				props[id] = Prop.TREE
			elif roll < chance[0] + chance[1]:
				props[id] = Prop.ROCK
	return {tiles = tiles, props = props}


static func _biome(value: float) -> Biome:
	if value < BIOME_BOUNDS[0]:
		return Biome.MARSH
	if value < BIOME_BOUNDS[1]:
		return Biome.MEADOW
	if value < BIOME_BOUNDS[2]:
		return Biome.FOREST
	return Biome.BONE_HILLS


## A prop's position inside its chunk: the center of its tile.
@warning_ignore("integer_division")
static func prop_offset(id: int) -> Vector2:
	return Vector2(id % CHUNK, id / CHUNK) * TILE + Vector2(TILE, TILE) / 2


static func prop_position(coord: Vector2i, id: int) -> Vector2:
	return Vector2(coord * CHUNK_PX) + prop_offset(id)


static func chunk_of(position: Vector2) -> Vector2i:
	return Vector2i((position / CHUNK_PX).floor())


## Whether chunk a lies within radius chunks of b on both axes.
static func near(a: Vector2i, b: Vector2i, radius: int) -> bool:
	return absi(a.x - b.x) <= radius and absi(a.y - b.y) <= radius


## The (2·radius+1)² chunks around center.
static func around(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			out.append(center + Vector2i(x, y))
	return out
