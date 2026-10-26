class_name RoomDef
extends Resource
## A handmade dungeon room, one file per room in res://data/rooms/; its id is the file name.
## Dungeon chains a start room, some middle rooms and an end room into a run's layout.
## Positions in px from the room's top-left corner.

enum Kind { START, MIDDLE, END }

@export var kind := Kind.MIDDLE
@export var size := Vector2(320, 240)
## Where its enemies (Tuning.dungeon_enemy) wait, one each, spawned when a player walks in.
@export var spawns: Array[Vector2] = []
