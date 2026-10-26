class_name DungeonView
extends Node2D
## A dungeon run's rooms and corridors on the client: brick floor below everything, a darker
## wall around each where no other joins it, the exit and the end chest.
# ponytail: one repeated tile for floor and wall until the room chunks get autotiled edges.

const BRICK := preload("res://assets/ninja_adventure/tilesets/TilesetInteriorFloor.png")
const BRICK_REGION := Rect2(192, 208, 16, 16)
const WALL := Color(0.45, 0.45, 0.55)
const WALL_WIDTH := 8.0
var area: Array[Rect2] = []
var exit: Vector2
var chest: Vector2
var _chest_view := ChestView.new()
## BRICK_REGION cut out, as draw_texture_rect only repeats a whole texture.
var _brick: Texture2D = ImageTexture.create_from_image(
	BRICK.get_image().get_region(Rect2i(BRICK_REGION))
)


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


## We opened the chest: show it open.
func open_chest() -> void:
	_chest_view.opened = true
	_chest_view.queue_redraw()


func _draw() -> void:
	for rect in area:
		draw_texture_rect(_brick, rect.grow(WALL_WIDTH), true, WALL)
	for rect in area:
		draw_texture_rect(_brick, rect, true)
