class_name BuffDef
extends Resource
## A dungeon buff, one file per buff in res://data/buffs/; its id is the file name. It raises one
## stat (Buffs.STATS) by amount per stack, up to max_stacks, and is lost on leaving the run.

@export var display_name := ""
## What one stack does, shown in the HUD, e.g. "+15% damage".
@export var description := ""
## ItemDef.Rarity: how often it drops (Tuning.buff_rarity_weights) and its color.
@export var rarity := ItemDef.Rarity.COMMON
## One of Buffs.STATS.
@export var stat := "damage"
@export var amount := 0.1
@export var max_stacks := 5
