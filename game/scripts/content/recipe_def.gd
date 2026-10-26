class_name RecipeDef
extends Resource
## What crafting turns into what, one file per recipe in res://data/recipes/; its id is the
## file name. Items are named by id.

@export var result: StringName
@export var count := 1
## {item id: count} used up.
@export var inputs: Dictionary
## Empty: by hand anywhere. Otherwise the station piece (PieceDef.station) the player must stand at.
@export var station: StringName
