class_name DungeonView
extends Node2D
## A dungeon run's rooms and corridors on the client: cobble floor below everything, a dark slab
## wall around each where no other joins it, the obstacles and gates, the exit and the end chest,
## and a little furnishing: sparse bones, cobwebs in some corners and torches at the gates.
# ponytail: one repeated tile for floor and wall until the room chunks get autotiled edges.

const FLOOR := preload("res://assets/craftpix/tiles/dungeon_floor.png")
const WALL := preload("res://assets/craftpix/tiles/dungeon_wall.png")
const RUBBLE := preload("res://assets/craftpix/props/decor/rubble.png")
const RUIN := preload("res://assets/craftpix/props/decor/ruin.png")
const WALL_WIDTH := 8.0
## How far an obstacle's lit top face reaches above its tiles, and its shadow below them.
const TOP_FACE := 8.0
const SHADOW := 4.0
const IRON := Color("5a6270")
const IRON_DARK := Color("262b33")
## Share of room floor tiles that get a bone: every BONE_EVERY-th by a hash of the tile.
const BONE_EVERY := 60
const BONES: Array[String] = [
	"bone",
	"bones_small",
	"bones_small",
	"long_bone",
	"long_bone",
	"ribs",
	"spine",
	"skull",
	"skulls",
]
## Every this many corners get a cobweb.
const WEB_EVERY := 2
const WEB := Color(1, 1, 1, 0.5)
const WEB_SIZE := 22.0
var area: Array[Rect2] = []
var exit: Vector2
var chest: Vector2
## World tiles of the obstacles, their RoomObstacle.Kind each, and the gates (one per
## corridor); the first cleared gates are open.
var obstacles: Array[Rect2i] = []
var kinds := PackedByteArray()
var gates: Array[Rect2i] = []
var cleared := 0
var _chest_view := ChestView.new()
var _torches := TorchLayer.new()
## Bone sprites and where they lie: [texture, center], found once on the first draw.
var _bones: Array = []
var _bones_made := false


func _ready() -> void:
	# Floor below everything; the exit's +1 brings it back level with the players.
	z_index = -1
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var portal := PortalView.new()
	portal.label = "Way out"
	portal.position = exit
	portal.z_index = 1
	add_child(portal)
	_chest_view.position = chest
	_chest_view.z_index = 1
	add_child(_chest_view)
	_torches.gates = gates.map(_px)
	_torches.cleared = cleared
	add_child(_torches)


## A room was cleared: the gates up to cleared open.
func set_cleared(count: int) -> void:
	cleared = count
	_torches.set_cleared(count)
	queue_redraw()


## We opened the chest: show it open.
func open_chest() -> void:
	_chest_view.opened = true
	_chest_view.queue_redraw()


func _draw() -> void:
	for rect in area:
		draw_texture_rect(WALL, rect.grow(WALL_WIDTH), true)
	for rect in area:
		draw_texture_rect(FLOOR, rect, true)
	for i in obstacles.size():
		_draw_obstacle(
			_px(obstacles[i]), kinds[i] if i < kinds.size() else RoomObstacle.Kind.PILLAR
		)
	for k in gates.size():
		_draw_gate(_px(gates[k]), k > cleared)
	if not _bones_made:
		_make_bones()
	for bone in _bones:
		var size: Vector2 = bone[0].get_size()
		draw_texture_rect(bone[0], Rect2(bone[1] - size / 2, size), false)
	for corner in _web_corners():
		_draw_web(corner[0], corner[1])


static func _px(tiles: Rect2i) -> Rect2:
	return Rect2(Vector2(tiles.position * WorldGen.TILE), Vector2(tiles.size * WorldGen.TILE))


## Flat on the floor like everything here: a block no taller than its tiles, a lit top face
## above them and a shadow south.
func _draw_obstacle(rect: Rect2, kind: int) -> void:
	if kind == RoomObstacle.Kind.RUBBLE:
		draw_rect(Rect2(rect.position + Vector2(0, SHADOW), rect.size), Color(0, 0, 0, 0.3))
		var sprite := (
			RUIN if rect.size.x > 2 * WorldGen.TILE and rect.size.y > WorldGen.TILE else RUBBLE
		)
		draw_texture_rect(sprite, rect, false)
		return
	draw_rect(Rect2(rect.position + Vector2(0, SHADOW), rect.size), Color(0, 0, 0, 0.35))
	draw_texture_rect(WALL, rect, true, Color(0.75, 0.75, 0.8))
	var top := Rect2(rect.position - Vector2(0, TOP_FACE), Vector2(rect.size.x, TOP_FACE))
	draw_texture_rect(WALL, top, true, Color(1.4, 1.4, 1.5))
	draw_rect(Rect2(top.position, Vector2(rect.size.x, 1)), Color(1, 1, 1, 0.25))
	if kind == RoomObstacle.Kind.TOMB:
		var lid := rect.grow(-3.0)
		draw_rect(lid, Color(0, 0, 0, 0.25), false, 1.0)
		draw_rect(Rect2(lid.position, Vector2(lid.size.x, 2)), Color(1, 1, 1, 0.18))


## Iron bars across the gate's column when shut, only the frame posts at its ends when open.
func _draw_gate(rect: Rect2, shut: bool) -> void:
	var post := Vector2(rect.size.x, 4.0)
	draw_rect(Rect2(rect.position, post), IRON)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - post.y), post), IRON)
	if not shut:
		return
	draw_rect(
		Rect2(rect.position + Vector2(rect.size.x * 0.5 - 1, 0), Vector2(2, rect.size.y)), IRON_DARK
	)
	for y in range(int(rect.position.y) + 2, int(rect.end.y), 6):
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 2), IRON)
	for x in [rect.position.x + 2, rect.end.x - 4]:
		draw_rect(Rect2(x, rect.position.y, 2, rect.size.y), IRON)


## Whether a rect of the area is a corridor, not a room: corridors are all one size.
static func _is_corridor(rect: Rect2) -> bool:
	var t := Content.tuning
	return rect.size.is_equal_approx(Vector2(t.corridor_length, t.corridor_width))


## A hash of a tile, the same on every client.
static func _roll(tile: Vector2i) -> int:
	return absi(hash([tile.x, tile.y, 22]))


## {tile: true} of every tile bones and webs keep off: obstacles, the chest and the exit with
## their neighbours.
func _keep_clear() -> Dictionary:
	var clear := {}
	var spots: Array[Rect2i] = obstacles.duplicate()
	for point in [chest, exit]:
		spots.append(Rect2i(Building.tile_of(point), Vector2i.ONE))
	for spot in spots:
		for y in range(spot.position.y - 1, spot.end.y + 1):
			for x in range(spot.position.x - 1, spot.end.x + 1):
				clear[Vector2i(x, y)] = true
	return clear


## Picks the bones from the tiles' hashes: room floor only, a few px off each tile's center.
func _make_bones() -> void:
	_bones_made = true
	var clear := _keep_clear()
	for rect in area:
		if _is_corridor(rect):
			continue
		var first := Building.tile_of(rect.position)
		var last := Building.tile_of(rect.end - Vector2.ONE)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var tile := Vector2i(x, y)
				var roll := _roll(tile)
				if roll % BONE_EVERY != 0 or clear.has(tile):
					continue
				var pick := BONES[(roll / BONE_EVERY) % BONES.size()]
				var jitter := Vector2((roll >> 8) % 9 - 4, (roll >> 12) % 9 - 4)
				var center := (Vector2(tile) + Vector2(0.5, 0.5)) * WorldGen.TILE + jitter
				_bones.append([Decor.sprite("decor/" + pick), center])


## [corner, direction into the room] of the room corners that get a cobweb, by the hash of
## the corner's tile; none where a corridor opens beside the corner.
func _web_corners() -> Array:
	var found: Array = []
	for rect in area:
		if _is_corridor(rect):
			continue
		for corner in [
			[rect.position, Vector2(1, 1)],
			[Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)],
			[Vector2(rect.position.x, rect.end.y), Vector2(1, -1)],
			[rect.end, Vector2(-1, -1)],
		]:
			if _roll(Building.tile_of(corner[0] + corner[1])) % WEB_EVERY != 0:
				continue
			var spot := Rect2(corner[0], corner[1] * WEB_SIZE).abs().grow(2.0)
			var open := false
			for other in area:
				if other != rect and _is_corridor(other) and other.intersects(spot):
					open = true
			if not open:
				found.append(corner)
	return found


## A cobweb fanned into the room from its corner: threads out to both walls and sagging
## arcs between them.
func _draw_web(corner: Vector2, dir: Vector2) -> void:
	var along_x := Vector2(dir.x, 0)
	var along_y := Vector2(0, dir.y)
	draw_line(corner, corner + dir * WEB_SIZE * 0.8, WEB)
	for step in [0.35, 0.7, 1.0]:
		var a: Vector2 = corner + along_x * WEB_SIZE * step
		var b: Vector2 = corner + along_y * WEB_SIZE * step
		var mid: Vector2 = (a + b) / 2 + dir * WEB_SIZE * 0.1 * step
		draw_polyline(PackedVector2Array([a, mid, b]), WEB)
	draw_line(corner, corner + along_x * WEB_SIZE, WEB)
	draw_line(corner, corner + along_y * WEB_SIZE, WEB)


## The torches on the corridor walls beside each gate: red while it is shut, warm and
## flickering once it is open. Its own node, so only it redraws every frame.
class TorchLayer:
	extends Node2D
	const SHUT := Color("b02a30")
	const LIT := Color("feae34")
	const BRACKET := Color("3a3f48")
	## The gates in px; gate k is open once cleared >= k.
	var gates: Array = []
	var cleared := 0
	var _time := 0.0

	func set_cleared(count: int) -> void:
		cleared = count
		set_process(_any_open())
		queue_redraw()

	func _any_open() -> bool:
		return not gates.is_empty()

	func _ready() -> void:
		set_process(_any_open())

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for k in gates.size():
			var rect: Rect2 = gates[k]
			var open := cleared >= k
			# Just outside the corridor's top and bottom edges, in the wall band.
			for y in [rect.position.y - 5.0, rect.end.y + 5.0]:
				_torch(Vector2(rect.position.x + rect.size.x / 2, y), open, k)

	func _torch(at: Vector2, open: bool, phase: int) -> void:
		draw_rect(Rect2(at + Vector2(-1, -1), Vector2(2, 5)), BRACKET)
		var flame := SHUT
		var glow := 0.12
		var lift := 0.0
		if open:
			flame = LIT
			var wobble := sin(_time * 11.0 + at.y * 0.3 + phase) * sin(_time * 7.3 + at.x)
			glow = 0.2 + 0.1 * wobble
			lift = wobble
		draw_circle(at + Vector2(0, -2), 11.0, Color(flame, glow))
		draw_circle(at + Vector2(0, -3 - lift), 2.5, flame)
		draw_circle(
			at + Vector2(0, -4 - lift), 1.2, Color(1, 0.95, 0.7) if open else Color(1, 0.6, 0.6)
		)
