class_name MapView
extends CanvasLayer
## The map of the chunks this player has been near: a minimap in the bottom-right
## corner and, toggled with M, a big one over the whole screen. Terrain is painted
## from the world seed like the chunks themselves; dots mark us, the other players and the
## barrow, diamonds the markers anyone in the world placed (in their character's tint). On the
## big map a click places a marker and a right click takes the nearest one down (GameClient sends
## them; world_at and marker_near turn the mouse into world terms). The explored chunks are kept
## per world seed in `dir`.

const MINI := Vector2(80, 80)
const MARGIN := 6
## World pixels per map pixel: 2 tiles on the minimap, 1 on the big map.
const MINI_SCALE := WorldGen.TILE * 2.0
const BIG_SCALE := WorldGen.TILE * 1.0
const FOG := Color(0, 0, 0, 0.75)
const ME_COLOR := Color.WHITE
const PLAYER_COLOR := Color("feae34")
const BARROW_COLOR := Color("e43b44")
## Map px from the mouse a right click finds a marker within.
const PICK_PX := 6.0
const HINT := "Click: place a marker   Right click: remove one   M: close"

# ponytail: client-side, per device; move to the saved player on the server if maps should
# follow players across machines.
var dir := "user://maps"
## Our position and the other players', set every frame by GameClient.
var me := Vector2.ZERO
var players: Array[Vector2] = []
## [id, x, y, owner name, look] of every marker in the world, from the server.
var markers: Array = []

var _seed := 0
var _player := ""
var _explored := {}  # chunk coord -> ImageTexture
var _mini := Control.new()
var _big := Control.new()


func _ready() -> void:
	_mini.size = MINI
	_mini.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, MARGIN
	)
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


## Starts the map of this world over, with the chunks player_name explored in it before.
## Per player too, so clients on one machine (the load test's bots) don't share a file.
func load_world(world_seed: int, player_name: String) -> void:
	_seed = world_seed
	_player = player_name
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


## The world position under a point of the big map (viewport coordinates).
func world_at(screen: Vector2) -> Vector2:
	return me + (screen - _big.size / 2) * BIG_SCALE


## The id of the marker nearest to a world position within PICK_PX on the big map, 0 if none.
func marker_near(at: Vector2) -> int:
	var best := 0
	var best_distance := PICK_PX * BIG_SCALE
	for marker: Array in markers:
		var distance := at.distance_to(Vector2(marker[1], marker[2]))
		if distance <= best_distance:
			best = marker[0]
			best_distance = distance
	return best


func _path() -> String:
	return "%s/%d-%s.json" % [dir, _seed, _player]


## One pixel per tile in the biome's color, darker where a tree or rock stands.
@warning_ignore("integer_division")
func _add(coord: Vector2i) -> void:
	var chunk := WorldGen.chunk(_seed, coord)
	var image := Image.create(WorldGen.CHUNK, WorldGen.CHUNK, false, Image.FORMAT_RGB8)
	for id in WorldGen.CHUNK * WorldGen.CHUNK:
		var color := WorldGen.BIOME_COLORS[chunk.tiles[id]]
		match chunk.levels[id]:
			Terrain.Level.SUNKEN:
				color = color.darkened(0.3)
			Terrain.Level.RAISED:
				color = color.lightened(0.2)
		if chunk.props.has(id) and WorldGen.is_node(chunk.props[id]):
			color = color.darkened(0.35)
		if Terrain.blocks(chunk.terrain[id]):
			color = ChunkView.CLIFF_FACE
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
	for marker: Array in markers:
		var spot: Vector2 = center + (Vector2(marker[1], marker[2]) - me) / px
		var r := 3.0
		var diamond := PackedVector2Array(
			[
				spot + Vector2(0, -r),
				spot + Vector2(r, 0),
				spot + Vector2(0, r),
				spot + Vector2(-r, 0)
			]
		)
		control.draw_colored_polygon(diamond, PlayerView.TINTS[PlayerView.tint_of(marker[4])])
		control.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color.BLACK, 1.0)
	for other in players:
		dot.call(other, PLAYER_COLOR)
	dot.call(me, ME_COLOR)
	control.draw_rect(Rect2(Vector2.ZERO, control.size), Color(1, 1, 1, 0.3), false)
	if control == _big:
		var font := ThemeDB.fallback_font
		var at := Vector2(MARGIN, control.size.y - MARGIN)
		control.draw_string(font, at, HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.8))
