class_name Building
## Pieces players build on the tile grid (PLAN §5.5): walls, floors, doors, workbenches, chests
## and fires. Shared by server and client: both keep {global tile: Building.Piece} of the chunks
## they have and ask the same questions of it, so the client predicts what the server decides.

## Why a piece can or can't be built on a tile; the client colors its ghost by it.
enum Status { OK, REPAIR, FAR, PROP, TAKEN, IN_THE_WAY, MISSING_ITEMS }

## Half the side of the square players and enemies take up when walking into pieces.
const BODY := 6.0


class Piece:
	var id: StringName
	var health: float
	var open := false
	## A chest's contents; on the server only.
	var items: Inventory

	func _init(piece_id: StringName) -> void:
		id = piece_id
		health = def().health
		if def().storage > 0:
			items = Inventory.new(def().storage)

	func def() -> PieceDef:
		return Content.piece(id)

	func blocks() -> bool:
		return def().blocks and not open


static func tile_of(at: Vector2) -> Vector2i:
	return Vector2i((at / WorldGen.TILE).floor())


static func tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile * WorldGen.TILE) + Vector2.ONE * WorldGen.TILE / 2.0


static func chunk_of_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(tile.x / float(WorldGen.CHUNK)), floori(tile.y / float(WorldGen.CHUNK)))


## A tile's index inside its chunk, the same numbering as prop ids.
static func index_in_chunk(tile: Vector2i) -> int:
	return posmod(tile.y, WorldGen.CHUNK) * WorldGen.CHUNK + posmod(tile.x, WorldGen.CHUNK)


@warning_ignore("integer_division")
static func tile_at(coord: Vector2i, index: int) -> Vector2i:
	return coord * WorldGen.CHUNK + Vector2i(index % WorldGen.CHUNK, index / WorldGen.CHUNK)


## The first tile whose piece blocks a body standing at at, null if none does.
static func blocker(pieces: Dictionary, at: Vector2) -> Variant:
	var low := tile_of(at - Vector2.ONE * BODY)
	var high := tile_of(at + Vector2.ONE * BODY)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var piece: Piece = pieces.get(Vector2i(x, y))
			if piece and piece.blocks():
				return Vector2i(x, y)
	return null


## Whether moving from one position to another is fine: not into a blocking piece, unless
## already inside one (so nobody gets stuck where a wall went up around them).
static func can_walk(pieces: Dictionary, from: Vector2, to: Vector2) -> bool:
	return blocker(pieces, to) == null or blocker(pieces, from) != null


## Whether a body at at overlaps a tile.
static func overlaps(tile: Vector2i, at: Vector2) -> bool:
	return Rect2(Vector2(tile * WorldGen.TILE), Vector2.ONE * WorldGen.TILE).grow(BODY).has_point(
		at
	)


## Checked in this order: reach from at (plus slack on the server), a prop on the tile (prop),
## a piece there (REPAIR if it is the same one damaged), a body in the way of a blocking piece,
## the cost.
static func can_build(
	pieces: Dictionary,
	tile: Vector2i,
	piece_id: StringName,
	inventory: Inventory,
	at: Vector2,
	prop: bool,
	bodies: Array[Vector2],
	slack := 0.0
) -> Status:
	var def := Content.piece(piece_id)
	if at.distance_to(tile_center(tile)) > Content.tuning.build_reach + slack:
		return Status.FAR
	if prop:
		return Status.PROP
	var there: Piece = pieces.get(tile)
	if there:
		if there.id == piece_id and there.health < def.health:
			return Status.REPAIR
		return Status.TAKEN
	if def.blocks and bodies.any(func(body: Vector2) -> bool: return overlaps(tile, body)):
		return Status.IN_THE_WAY
	if not inventory.has_all(def.cost):
		return Status.MISSING_ITEMS
	return Status.OK


## {piece id: true} of the station pieces within station_reach of a position.
static func stations_near(pieces: Dictionary, at: Vector2) -> Dictionary:
	var out := {}
	var reach := Content.tuning.station_reach
	var center := tile_of(at)
	var tiles := ceili(reach / WorldGen.TILE)
	for y in range(-tiles, tiles + 1):
		for x in range(-tiles, tiles + 1):
			var tile := center + Vector2i(x, y)
			var piece: Piece = pieces.get(tile)
			if piece and piece.def().station and at.distance_to(tile_center(tile)) <= reach:
				out[piece.id] = true
	return out


## The closest door or chest within reach of at: [tile, distance], [] if none.
static func nearest_usable(pieces: Dictionary, at: Vector2, reach: float) -> Array:
	var best := []
	var center := tile_of(at)
	var tiles := ceili(reach / WorldGen.TILE)
	for y in range(-tiles, tiles + 1):
		for x in range(-tiles, tiles + 1):
			var tile := center + Vector2i(x, y)
			var piece: Piece = pieces.get(tile)
			if piece == null or not (piece.def().door or piece.def().storage > 0):
				continue
			var distance := at.distance_to(tile_center(tile))
			if distance <= reach and (best.is_empty() or distance < best[1]):
				best = [tile, distance]
	return best


## What the client is sent of a piece: [Content.piece_ids index, health 0..1, open].
static func to_net(piece: Piece) -> Array:
	return [Content.piece_ids.find(piece.id), piece.health / piece.def().health, piece.open]


## The reverse of to_net, for the client's copy (health as a share of the max).
static func from_net(data: Array) -> Piece:
	var piece := Piece.new(Content.piece_ids[data[0]])
	piece.health = data[1] * piece.def().health
	piece.open = data[2]
	return piece
