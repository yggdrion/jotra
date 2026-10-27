class_name EnemyDef
extends Resource
## An enemy kind, one file per kind in res://data/enemies/; its id is the file name. Health and
## damage are before self-scaling (Combat.scaled). Distances in px, times in seconds.

## Shown on the boss bar; only bosses (size > 1) get one.
@export var display_name := ""
## Walk sheet, 16×16 frames: a column per facing (down, up, left, right), a row per frame.
@export var sheet: Texture2D
## Drawn this many times its sheet's size.
@export var size := 1.0
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
## Above 0, the windup ends in a slam that hits every player this close instead of the target.
@export var slam_radius := 0.0
## Gives up when its target is further than this from home, then walks back and heals
## leash_heal of its max health a second.
@export var leash := 400.0
@export var leash_heal := 0.25
## Standing still and open this long after an attack lands or whiffs.
@export var recovery := 0.5
## Hits take poise_damage off this; at 0 it staggers for stagger_time, then poise is back.
@export var poise := 30.0
@export var stagger_time := 0.6
## A hit with at least this much poise_damage breaks a windup; weaker ones don't. Poise is
## left alone while winding up.
@export var windup_armor := 30.0
## Share of a swing's knockback it takes.
@export var knock_scale := 1.0
## How far a hit pushes the player it lands on (px).
@export var knock := 12.0
## What it drops on death, see Loot.roll.
@export var drops: Array
