class_name PieceDef
extends Resource
## A piece players build on the tile grid (PLAN §5.5), one file per piece in
## res://data/pieces/; its id is the file name. Building one takes its cost from the inventory,
## removing it gives the cost back.

@export var display_name := ""
## Its sprite, standing on the tile's bottom edge; the build ghost draws it tinted.
@export var icon: Texture2D
## A door's sprite while open.
@export var open_icon: Texture2D
## {item id: count} used up.
@export var cost: Dictionary
## Enemies break it down to 0.
@export var health := 100.0
## Players and enemies can't walk through it; enemies in the way hit it instead.
@export var blocks := false
## Drawn under everything else, like the ground.
@export var flat := false
## E opens and closes it; open, it doesn't block.
@export var door := false
## Recipes naming this piece's id as their station are crafted next to it.
@export var station := false
## Slots of storage; E opens it.
@export var storage := 0
## Radius in px of the light it gives off at night (client only).
@export var light := 0.0
