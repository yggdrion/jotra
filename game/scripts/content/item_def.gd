class_name ItemDef
extends Resource
## An item kind, one file per item in res://data/items/; its id is the file name. Materials
## stack, food is eaten, gear goes in an equipment slot and changes the wearer's stats.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC }
## NONE: a material, not wearable.
enum Slot { NONE, WEAPON, ARMOR }

const RARITY_COLORS: Array[Color] = [
	Color("c0cbdc"), Color("63c74d"), Color("0099db"), Color("b55088")
]

@export var display_name := ""
@export var rarity := Rarity.COMMON
@export var max_stack := 1
## Its sprite on the ground and in slots, at most 16×16.
@export var icon: Texture2D
## The placeholder square's color where there is no icon.
@export var color := Color.WHITE
@export var slot := Slot.NONE
## Hunger restored by eating one; 0: not food.
@export var food := 0.0
@export_group("Weapon")
@export var light: AttackDef
@export var heavy: AttackDef
@export_group("Armor")
## Taken off every hit the wearer takes, down to Tuning.min_damage.
@export var armor := 0.0
## Added to the wearer's max health.
@export var health := 0.0
