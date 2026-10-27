class_name ChunkView
extends Node2D
## One chunk on the client, generated from the seed: biome tiles drawn below everything, props
## and built pieces as children y-sorted with the players.
# ponytail: tiles drawn one by one in _draw until the art needs a TileMapLayer (autotiled edges).

const GROUND := preload("res://assets/ninja_adventure/tilesets/TilesetFloor.png")
## Per biome, the top-left of a row of five ground tiles: plain, then four with tufts.
const GROUND_ROWS: Array[Vector2] = [
	Vector2(0, 192), Vector2(176, 192), Vector2(176, 304), Vector2(0, 304)
]
## One tile in this many gets tufts.
const TUFT_EVERY := 5


## Tree or rock, standing on its tile's center; brighter while E acts on it.
class PropView:
	extends Node2D

	const NATURE := preload("res://assets/ninja_adventure/tilesets/TilesetNature.png")
	## Tree per biome (meadow, forest, marsh, bone hills), 32×32.
	const TREES: Array[Rect2] = [
		Rect2(0, 0, 32, 32), Rect2(32, 0, 32, 32), Rect2(64, 0, 32, 32), Rect2(64, 0, 32, 32)
	]
	const ROCK := Rect2(288, 144, 16, 16)
	## Sticks and pebbles are the items' own icons.
	const STICK := preload("res://assets/ninja_adventure/items/stick.png")
	const PEBBLE := preload("res://assets/ninja_adventure/items/pebble.png")
	const HIGHLIGHT := Color(1.6, 1.6, 1.6)

	var kind: WorldGen.Prop
	var biome: WorldGen.Biome
	var highlighted := false:
		set(value):
			if value != highlighted:
				highlighted = value
				queue_redraw()

	func _draw() -> void:
		var tint := HIGHLIGHT if highlighted else Color.WHITE
		if kind == WorldGen.Prop.TREE:
			draw_texture_rect_region(NATURE, Rect2(-16, -29, 32, 32), TREES[biome], tint)
		elif kind == WorldGen.Prop.ROCK:
			draw_texture_rect_region(NATURE, Rect2(-8, -13, 16, 16), ROCK, tint)
		else:
			var icon := STICK if kind == WorldGen.Prop.STICK else PEBBLE
			draw_texture_rect(icon, Rect2(-8, -12, 16, 16), false, tint)


var coord: Vector2i
var _tiles: PackedByteArray
var _props := {}  # id -> PropView
var _pieces := {}  # index in chunk -> PieceView


func _init(world_seed: int, chunk_coord: Vector2i, removed: PackedInt32Array) -> void:
	coord = chunk_coord
	position = Vector2(coord * WorldGen.CHUNK_PX)
	y_sort_enabled = true
	# Tiles below everything; the props' +1 brings them back level with the players.
	z_index = -1
	var data := WorldGen.chunk(world_seed, coord)
	_tiles = data.tiles
	for id: int in data.props:
		if id in removed:
			continue
		var prop := PropView.new()
		prop.kind = data.props[id]
		prop.biome = _tiles[id] as WorldGen.Biome
		prop.position = WorldGen.prop_offset(id)
		prop.z_index = 1
		add_child(prop)
		_props[id] = prop


## Shows a piece on a tile of this chunk, or none there for null.
func set_piece(index: int, piece: Building.Piece) -> void:
	var view: PieceView = _pieces.get(index)
	if piece == null:
		if view:
			view.queue_free()
			_pieces.erase(index)
		return
	if view == null:
		view = PieceView.new()
		view.position = WorldGen.prop_offset(index)
		add_child(view)
		_pieces[index] = view
	# Floors lie with the ground, the rest stands level with the players.
	view.z_index = 0 if piece.def().flat else 1
	view.piece = piece


func highlight_piece(index: int, on: bool) -> void:
	if _pieces.has(index):
		_pieces[index].highlighted = on


func has_prop(id: int) -> bool:
	return _props.has(id)


func remove_prop(id: int) -> void:
	if _props.has(id):
		_props[id].queue_free()
		_props.erase(id)


func kind_of(id: int) -> WorldGen.Prop:
	return _props[id].kind


func highlight(id: int, on: bool) -> void:
	if _props.has(id):
		_props[id].highlighted = on


## [prop id, distance] of the pickup (stick or pebble) closest to a world position, or [] if
## none is within reach; trees and rocks are swung at, not used.
func nearest_prop(world_position: Vector2, reach: float) -> Array:
	var best := []
	for id: int in _props:
		if WorldGen.is_node(_props[id].kind):
			continue
		var distance := world_position.distance_to(position + _props[id].position)
		if distance <= reach and (best.is_empty() or distance < best[1]):
			best = [id, distance]
	return best


func _draw() -> void:
	var size := Vector2(WorldGen.TILE, WorldGen.TILE)
	for y in WorldGen.CHUNK:
		for x in WorldGen.CHUNK:
			var biome := _tiles[y * WorldGen.CHUNK + x]
			# Stable per world tile, so chunk edges don't show.
			var tuft := hash(coord * WorldGen.CHUNK + Vector2i(x, y)) % (4 * TUFT_EVERY)
			var column := tuft + 1 if tuft < 4 else 0
			var region := Rect2(GROUND_ROWS[biome] + Vector2(column * WorldGen.TILE, 0), size)
			draw_texture_rect_region(GROUND, Rect2(Vector2(x, y) * size, size), region)
