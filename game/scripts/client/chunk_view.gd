class_name ChunkView
extends Node2D
## One chunk on the client, generated from the seed: biome tiles drawn below everything, props
## as children y-sorted with the players.
# ponytail: tiles as flat rects until there is tile art for a TileMapLayer.


## Placeholder tree or rock, standing on its tile's center.
class PropView:
	extends Node2D

	var kind: WorldGen.Prop

	func _draw() -> void:
		if kind == WorldGen.Prop.TREE:
			draw_rect(Rect2(-2, -10, 4, 10), Color("733e39"))
			draw_circle(Vector2(0, -16), 8, Color("193c3e"))
		else:
			draw_circle(Vector2(0, -4), 6, Color("5a6988"))


var coord: Vector2i
var _tiles: PackedByteArray
var _props := {}  # id -> PropView


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


func remove_prop(id: int) -> void:
	if _props.has(id):
		_props[id].queue_free()
		_props.erase(id)


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
