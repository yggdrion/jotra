class_name DungeonView
extends Node2D
## A dungeon run's rooms and corridors on the client: stone floor below everything, a wall
## around each where no other joins it, the exit and the end chest.
# ponytail: flat rects until there is tile art for the room chunks.

const FLOOR := Color("3e2731")
const WALL := Color("262b44")
const WALL_WIDTH := 8.0

var area: Array[Rect2] = []
var exit: Vector2
var chest: Vector2
var _chest_view := ChestView.new()


func _ready() -> void:
	# Floor below everything; the exit's +1 brings it back level with the players.
	z_index = -1
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
		draw_rect(rect.grow(WALL_WIDTH), WALL)
	for rect in area:
		draw_rect(rect, FLOOR)
