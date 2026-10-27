class_name KitDef
extends Resource
## A starting kit picked when a character is made, one file per kit in res://data/kits/; its id
## is the file name. A character gets it the first time it joins a world (SimWorld.set_character).

@export var display_name := ""
## One line for the character creation screen.
@export var description := ""
## {item id: count} put in the backpack.
@export var items := {}
## Items of the kit worn at once.
@export var wear: Array[StringName] = []
