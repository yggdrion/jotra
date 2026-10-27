class_name ItemDef
extends Resource
## An item kind, one file per item in res://data/items/; its id is the file name. Materials
## stack, food is eaten, gear goes in an equipment slot and changes the wearer's stats.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC }
## What a tool breaks: trees need an AXE, rocks a PICKAXE.
enum Tool { NONE, AXE, PICKAXE }
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
@export_group("Bow")
## The ammo item a bow shoots, one per shot; "" for anything that is not a bow. A bow has no
## light or heavy swing: the weapon button draws it and releasing shoots.
@export var ammo: StringName = &""
## Seconds to draw fully; arrow damage, speed and range scale with the share drawn.
@export var draw_time := 0.8
## Releasing before this share is drawn shoots nothing.
@export var min_draw := 0.3
@export var arrow_damage := 24.0
@export var arrow_speed := 360.0
@export var arrow_range := 280.0
## Stamina spent on the shot.
@export var draw_cost := 10.0
@export_group("Armor")
## Taken off every hit the wearer takes, down to Tuning.min_damage.
@export var armor := 0.0
## Added to the wearer's max health.
@export var health := 0.0
@export_group("Tool")
## A tool works from anywhere in the inventory; of several, the best damage counts.
@export var tool_kind := Tool.NONE
## Nodes (Tuning.tree_tier, rock_tier) need a tool of at least this tier.
@export var tool_tier := 0
## Health taken off a node per swing.
@export var tool_damage := 0.0
