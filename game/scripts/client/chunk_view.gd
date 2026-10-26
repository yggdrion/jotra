class_name ChunkView
extends Node2D
## One chunk on the client, generated from the seed: biome tiles drawn below everything, props
## and built pieces as children y-sorted with the players.
# ponytail: tiles as flat rects until there is tile art for a TileMapLayer.


## Placeholder tree or rock, standing on its tile's center.
class PropView:
	extends Node2D

	const OUTLINE := Color(1, 1, 1, 0.8)

	var kind: WorldGen.Prop
	## Outlined: the prop E acts on.
	var highlighted := false:
		set(value):
			if value != highlighted:
				highlighted = value
				queue_redraw()

	func _draw() -> void:
		if kind == WorldGen.Prop.TREE:
			if highlighted:
				draw_rect(Rect2(-3, -11, 6, 12), OUTLINE)
				draw_circle(Vector2(0, -16), 9, OUTLINE)
			draw_rect(Rect2(-2, -10, 4, 10), Color("733e39"))
			draw_circle(Vector2(0, -16), 8, Color("193c3e"))
		else:
			if highlighted:
				draw_circle(Vector2(0, -4), 7, OUTLINE)
			draw_circle(Vector2(0, -4), 6, Color("5a6988"))


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


## [prop id, distance] of the prop closest to a world position, or [] if none is within reach.
func nearest_prop(world_position: Vector2, reach: float) -> Array:
	var best := []
	for id: int in _props:
		var distance := world_position.distance_to(position + _props[id].position)
		if distance <= reach and (best.is_empty() or distance < best[1]):
			best = [id, distance]
	return best


func _draw() -> void:
	var size := Vector2(WorldGen.TILE, WorldGen.TILE)
	for y in WorldGen.CHUNK:
		for x in WorldGen.CHUNK:
			var biome := _tiles[y * WorldGen.CHUNK + x]
			draw_rect(Rect2(Vector2(x, y) * size, size), WorldGen.BIOME_COLORS[biome])
