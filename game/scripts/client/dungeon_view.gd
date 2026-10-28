class_name DungeonView
extends Node2D
## A dungeon run's rooms and corridors on the client: cobble floor below everything, a dark slab
## wall around each where no other joins it, the obstacles and gates, the exit and the end chest.
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


## A room was cleared: the gates up to cleared open.
func set_cleared(count: int) -> void:
	cleared = count
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
