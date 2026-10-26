class_name SynergyDef
extends Resource
## Two dungeon buffs that do more together, one file per pair in res://data/synergies/: holding
## both adds amount to stat (Buffs.STATS) once, whatever the stacks.

@export var display_name := ""
@export var description := ""
@export var buffs: Array[StringName] = []
## One of Buffs.STATS.
@export var stat := "damage"
@export var amount := 0.1
