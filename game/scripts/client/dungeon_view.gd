class_name DungeonView
extends Node2D
## A dungeon run's rooms on the client: stone floor below everything, a wall around each room
## where no other room joins it, and the exit.
# ponytail: flat rects until there is tile art for the room chunks.

const FLOOR := Color("3e2731")
const WALL := Color("262b44")
const WALL_WIDTH := 8.0

var rooms: Array[Rect2] = []
var exit: Vector2


func _ready() -> void:
	# Floor below everything; the exit's +1 brings it back level with the players.
	z_index = -1
	var portal := PortalView.new()
	portal.label = "Way out"
	portal.position = exit
	portal.z_index = 1
	add_child(portal)


func _draw() -> void:
	for room in rooms:
		draw_rect(room.grow(WALL_WIDTH), WALL)
	for room in rooms:
		draw_rect(room, FLOOR)
