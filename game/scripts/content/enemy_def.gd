class_name EnemyDef
extends Resource
## An enemy kind, one file per kind in res://data/enemies/; its id is the file name. Health and
## damage are before self-scaling (Combat.scaled). Distances in px, times in seconds.

## Walk sheet, 16×16 frames: a column per facing (down, up, left, right), a row per frame.
@export var sheet: Texture2D
@export var health := 40.0
@export var damage := 15.0
@export var speed := 70.0
@export var notice_radius := 160.0
@export var attack_range := 22.0
## Extra range for the hit at the end of a windup, as the server's copy of the target lags.
@export var attack_slack := 8.0
## The telegraph before a hit lands: dash out or away.
@export var windup := 0.5
## Share of its speed it keeps closing in at while winding up: near 1, walking away is no
## escape and only a dash dodges.
@export var windup_speed := 0.0
@export var cooldown := 1.0
## Chasing further than this from home it gives up, walks back and heals.
@export var leash := 400.0
## What it drops on death, see Loot.roll.
@export var drops: Array
