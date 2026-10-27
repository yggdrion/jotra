class_name AbilityDef
extends Resource
## An ability a worn rune grants (PLAN §5.2), one file per ability in res://data/abilities/; its
## id is the file name, ItemDef.ability names it. Q uses it; the cooldown and the stamina cost
## are checked on the server (SimWorld.use_ability).

enum Kind { FROST_BOLT, WARD, SHOCKWAVE }

@export var display_name := ""
@export var kind := Kind.FROST_BOLT
@export var cooldown := 10.0
@export var stamina_cost := 20.0
## Damage of the bolt or the shockwave, scaled by the damage buffs; 0 for a ward.
@export var damage := 0.0
## Shockwave and ward: the area around the player, px.
@export var radius := 0.0
@export_group("Frost bolt")
@export var speed := 300.0
@export var range := 260.0
## Speed multiplier of the enemy hit (1: none) and the seconds it lasts.
@export var slow := 0.5
@export var slow_time := 3.0
@export_group("Shockwave")
@export var poise_damage := 0.0
## How far enemies in the area are pushed, px.
@export var knock := 0.0
@export_group("Ward")
## Health per second to every player in the area, for duration seconds.
@export var heal_per_second := 0.0
@export var duration := 0.0
