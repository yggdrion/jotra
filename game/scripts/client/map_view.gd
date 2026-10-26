class_name MapView
extends CanvasLayer
## The map of the chunks this player has been near: a minimap above the key hint in the
## bottom-right corner and, toggled with M, a big one over the whole screen. Terrain is painted
## from the world seed like the chunks themselves; dots mark us, the other players and the
## barrow. The explored chunks are kept per world seed in `dir`.

const MINI := Vector2(80, 80)
const MARGIN := 6
## World pixels per map pixel: 2 tiles on the minimap, 1 on the big map.
const MINI_SCALE := WorldGen.TILE * 2.0
const BIG_SCALE := WorldGen.TILE * 1.0
const FOG := Color(0, 0, 0, 0.75)
const ME_COLOR := Color.WHITE
const PLAYER_COLOR := Color("feae34")
const BARROW_COLOR := Color("e43b44")

# ponytail: client-side, per device; move to the saved player on the server if maps should
# follow players across machines.
var dir := "user://maps"
## Our position and the other players', set every frame by GameClient.
var me := Vector2.ZERO
var players: Array[Vector2] = []

var _seed := 0
var _explored := {}  # chunk coord -> ImageTexture
var _mini := Control.new()
var _big := Control.new()


func _ready() -> void:
	_mini.size = MINI
	_mini.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, MARGIN
	)
	_mini.offset_top -= 14
	_mini.offset_bottom -= 14
	_mini.clip_contents = true
	_big.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big.visible = false
	for control: Control in [_mini, _big]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(control)
	_mini.draw.connect(_draw_map.bind(_mini, MINI_SCALE))
	_big.draw.connect(_draw_map.bind(_big, BIG_SCALE))


func explored() -> Array:
	return _explored.keys()


## Starts the map of this world over, with the chunks explored in it before.
func load_world(world_seed: int) -> void:
	_seed = world_seed
	_explored.clear()
	if not FileAccess.file_exists(_path()):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	for xy: Variant in data if data is Array else []:
		_add(Vector2i(int(xy[0]), int(xy[1])))


## Marks a chunk explored and saves the map if it is new.
func explore(coord: Vector2i) -> void:
	if _explored.has(coord):
		return
	_add(coord)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file:
		var coords := _explored.keys().map(func(c: Vector2i) -> Array: return [c.x, c.y])
		file.store_string(JSON.stringify(coords))


func toggle_big() -> void:
	_big.visible = not _big.visible


func is_big() -> bool:
	return _big.visible


func refresh() -> void:
	_mini.queue_redraw()
	if _big.visible:
		_big.queue_redraw()


func _path() -> String:
	return "%s/%d.json" % [dir, _seed]


## One pixel per tile in the biome's color, darker where a tree or rock stands.
@warning_ignore("integer_division")
func _add(coord: Vector2i) -> void:
	var chunk := WorldGen.chunk(_seed, coord)
	var image := Image.create(WorldGen.CHUNK, WorldGen.CHUNK, false, Image.FORMAT_RGB8)
	for id in WorldGen.CHUNK * WorldGen.CHUNK:
		var color := WorldGen.BIOME_COLORS[chunk.tiles[id]]
		if chunk.props.has(id):
			color = color.darkened(0.35)
		image.set_pixel(id % WorldGen.CHUNK, id / WorldGen.CHUNK, color)
	_explored[coord] = ImageTexture.create_from_image(image)


## Draws the explored chunks around us at px world pixels per map pixel, then the dots.
func _draw_map(control: Control, px: float) -> void:
	var center := control.size / 2
	control.draw_rect(Rect2(Vector2.ZERO, control.size), FOG)
	var side := Vector2.ONE * WorldGen.CHUNK_PX / px
	for coord: Vector2i in _explored:
		var at := center + (Vector2(coord * WorldGen.CHUNK_PX) - me) / px
		if Rect2(Vector2.ZERO, control.size).intersects(Rect2(at, side)):
			control.draw_texture_rect(_explored[coord], Rect2(at, side), false)
	var dot := func(world: Vector2, color: Color) -> void:
		var spot: Vector2 = center + (world - me) / px
		control.draw_rect(Rect2(spot - Vector2.ONE * 1.5, Vector2.ONE * 3), color)
	dot.call(Content.tuning.dungeon_entrance, BARROW_COLOR)
	for other in players:
		dot.call(other, PLAYER_COLOR)
	dot.call(me, ME_COLOR)
	control.draw_rect(Rect2(Vector2.ZERO, control.size), Color(1, 1, 1, 0.3), false)
