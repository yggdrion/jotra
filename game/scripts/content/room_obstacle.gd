class_name RoomObstacle
extends Resource
## Something solid in a dungeon room that players, enemies and projectiles cannot pass: a block
## of whole tiles, placed by hand in a RoomDef. The kind only picks how the client draws it.

enum Kind { PILLAR, TOMB, RUBBLE }

@export var kind := Kind.PILLAR
## The tiles it covers, in tiles from the room's top-left corner.
@export var tiles := Rect2i()
