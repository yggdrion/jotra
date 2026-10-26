class_name Tuning
extends Resource
## The gameplay numbers not tied to an item or enemy (res://data/tuning.tres), shared by server
## and client. Distances in px, times in seconds.

@export_group("Player")
@export var max_health := 100.0
@export var max_stamina := 100.0
## Walk speed; the client moves at it, the server checks moves against it.
@export var walk_speed := 120.0
## Stamina per second, once stamina_delay has passed since it was last spent.
@export var stamina_regen := 35.0
@export var stamina_delay := 0.6
@export var respawn_delay := 3.0
@export var respawn_at := Vector2.ZERO

@export_group("Survival")
@export var max_hunger := 100.0
## Hunger lost per second.
@export var hunger_drain := 0.14
## Health per second while hunger is above zero.
@export var health_regen := 0.25
## At zero hunger: health lost per second, and stamina_regen times this.
@export var starve_damage := 1.0
@export var starve_stamina := 0.5
## A respawned player has at least this much hunger.
@export var respawn_hunger := 50.0

@export_group("Day and night")
## Seconds of day, then of night; world time 0 is dawn of day 1.
@export var day_length := 480.0
@export var night_length := 240.0
## Seconds over which the light fades at dusk and comes back at dawn (client only).
@export var twilight := 30.0
## Multipliers on the enemies spawned at night, on top of the self-scaling. Above
## walk_speed / enemy speed, night enemies outrun a walking player.
@export var night_count := 2.0
@export var night_health := 1.3
@export var night_damage := 1.5
@export var night_speed := 1.2

@export_group("Attacks")
## Swings without a weapon.
@export var fists_light: AttackDef
@export var fists_heavy: AttackDef
## The server's copies of attacker and target lag the client's view, so it accepts hits a bit
## further and wider than the client reports them.
@export var hit_slack := 24.0
@export var arc_slack := 60.0
## Targets this close count as hit whatever the aim.
@export var point_blank := 8.0
## No hit does less than this, whatever the armor.
@export var min_damage := 1.0

@export_group("Dash")
@export var dash_distance := 64.0
@export var dash_time := 0.15
@export var dash_cost := 25.0
@export var dash_cooldown := 0.4
## I-frames from the start of a dash, plus a latency tolerance (PLAN §4.4).
@export var iframes := 0.25
@export var iframe_slack := 0.1

@export_group("Spawning")
## Each living player is topped up to enemies_per_player × count scaling enemies within
## spawn_radius, one spawn per player every spawn_interval, on a ring around them.
@export var enemy: EnemyDef
@export var enemies_per_player := 3
@export var spawn_interval := 2.0
@export var spawn_radius := 500.0
@export var spawn_ring_min := 300.0
@export var spawn_ring_max := 450.0
## Enemies with no player this close are dropped.
@export var despawn_radius := 900.0

@export_group("Scaling")
## Players this close to an encounter count for its scaling (PLAN §5.6).
@export var scale_radius := 400.0
## Added per extra nearby player to the health, damage and count multipliers.
@export var scale_health := 0.15
@export var scale_damage := 0.1
@export var scale_count := 0.5

@export_group("Gathering")
## Seconds a player needs per tree felled or rock broken.
@export var gather_time := 1.0

@export_group("Loot")
## Slots in a player's inventory.
@export var inventory_size := 24
## Items on the ground within this of a living player go into their inventory.
@export var pickup_radius := 16.0
## Items within this of a living player slide toward them at magnet_speed.
@export var magnet_radius := 40.0
@export var magnet_speed := 180.0
## Items left on the ground vanish after this long.
@export var drop_lifetime := 300.0
## Spread of a drop's items around where it fell.
@export var drop_scatter := 10.0
## What removing a tree or a rock gives, see Loot.roll.
@export var tree_drops: Array
@export var rock_drops: Array

@export_group("Crafting")
## {station id: position} of the fixed crafting stations.
# ponytail: one workbench at the spawn until M8 lets players build their own.
@export var stations: Dictionary
## How close to a station a player must stand to craft there.
@export var station_reach := 40.0
