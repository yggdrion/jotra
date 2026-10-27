class_name ChunkView
extends Node2D
## One chunk on the client, generated from the seed: biome tiles drawn below everything, props
## and built pieces as children y-sorted with the players.
# ponytail: tiles drawn one by one in _draw until the art needs a TileMapLayer (autotiled edges).

const GROUND := preload("res://assets/craftpix/tiles/ground.png")
## Per biome, the top-left of a row of five ground tiles: plain, then four with tufts.
const GROUND_ROWS: Array[Vector2] = [Vector2(0, 0), Vector2(0, 16), Vector2(0, 32), Vector2(0, 48)]
## One tile in this many gets tufts.
const TUFT_EVERY := 5


## Tree or rock, standing on its tile's center at its own size, maybe mirrored; brighter while
## E acts on it.
class PropView:
	extends Node2D

	## Trees per biome (meadow, forest, marsh, bone hills), one picked per tile by variant.
	const TREES := [
		["tree_meadow", "tree_meadow", "tree_big", "tree_drip"],
		["tree_forest", "tree_forest", "tree_forest", "tree_drip_small"],
		["tree_marsh", "tree_marsh", "tree_forest", "tree_drip_small"],
		["tree_bone", "tree_bone", "tree_pale"],
	]
	const ROCK := preload("res://assets/craftpix/props/rock.png")
	## How far below the sprite's bottom edge its base stands (the shadow reaches past it), px.
	const BASE := 4
	## Sticks and pebbles are the items' own icons.
	const STICK := preload("res://assets/craftpix/icons/stick.png")
	const PEBBLE := preload("res://assets/craftpix/icons/pebble.png")
	const HIGHLIGHT := Color(1.6, 1.6, 1.6)

	var kind: WorldGen.Prop
	var biome: WorldGen.Biome
	## Any hash of the tile: picks the tree and whether it is mirrored.
	var variant := 0
	var highlighted := false:
		set(value):
			if value != highlighted:
				highlighted = value
				queue_redraw()

	func _draw() -> void:
		var tint := HIGHLIGHT if highlighted else Color.WHITE
		if WorldGen.is_node(kind):
			var texture: Texture2D = ROCK
			if kind == WorldGen.Prop.TREE:
				var trees: Array = TREES[biome]
				texture = Decor.sprite(trees[variant % trees.size()])
			var size := texture.get_size()
			if variant & 8:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
			draw_texture(texture, Vector2(-size.x / 2, -size.y + BASE), tint)
			draw_set_transform(Vector2.ZERO)
		else:
			var icon := STICK if kind == WorldGen.Prop.STICK else PEBBLE
			draw_texture_rect(icon, Rect2(-8, -12, 16, 16), false, tint)


var coord: Vector2i
var _tiles: PackedByteArray
var _props := {}  # id -> PropView
var _pieces := {}  # index in chunk -> PieceView
var _decor := {}  # index in chunk -> Decor.View


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
		prop.variant = _roll(world_seed, id)
		prop.position = WorldGen.prop_offset(id)
		prop.z_index = 1
		add_child(prop)
		_props[id] = prop
	_scatter(world_seed, data.props)


## Shows a piece on a tile of this chunk, or none there for null.
func set_piece(index: int, piece: Building.Piece) -> void:
	var view: PieceView = _pieces.get(index)
	if _decor.has(index):
		_decor[index].visible = piece == null
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


## Scenery on the tiles without a prop (felled ones included), from the seed.
func _scatter(world_seed: int, props: Dictionary) -> void:
	for id in WorldGen.CHUNK * WorldGen.CHUNK:
		if props.has(id):
			continue
		var roll := _roll(world_seed, id)
		var piece := Decor.pick(_tiles[id], roll)
		if piece == "":
			continue
		var view := Decor.View.new()
		view.texture = Decor.sprite("decor/" + piece)
		view.flip = roll & 16 != 0
		# Off the tile's center by up to 4 px, so the scatter doesn't line up.
		var jitter := Vector2((roll >> 5) % 9 - 4, (roll >> 9) % 9 - 4)
		view.position = WorldGen.prop_offset(id) + jitter
		view.z_index = 0 if piece in Decor.FLAT else 1
		add_child(view)
		_decor[id] = view


## A hash of a tile of this chunk, stable per world.
func _roll(world_seed: int, id: int) -> int:
	var tile := coord * WorldGen.CHUNK + Vector2i(id % WorldGen.CHUNK, id / WorldGen.CHUNK)
	return absi(hash([world_seed, tile.x, tile.y]))


func set_join_mask(index: int, mask: int) -> void:
	if _pieces.has(index):
		_pieces[index].mask = mask


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
