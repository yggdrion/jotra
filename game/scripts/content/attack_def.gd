class_name AttackDef
extends Resource
## One swing: a weapon's light or heavy attack, or a bare-handed one (Tuning). Arc is the full
## swing angle in degrees, centered on the aim.

@export var damage := 10.0
@export var reach := 28.0
@export var arc := 100.0
@export var cooldown := 0.35
@export var cost := 12.0
@export var knock := 10.0
## Poise damage to what it hits (EnemyDef.poise); at or above EnemyDef.windup_armor it also
## breaks a windup.
@export var poise_damage := 10.0
## The weapon's swing on screen, client only: seconds, the share of it spent pulling back
## first (heavies), how far the swinger steps toward the aim (px), and what a hit does to the
## game feel: seconds of hitstop and px of screenshake.
@export var swing_time := 0.15
@export var pull_back := 0.0
@export var lunge := 3.0
@export var hitstop := 0.04
@export var shake := 1.0
