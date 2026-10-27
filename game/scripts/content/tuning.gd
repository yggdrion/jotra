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

## Seconds before another healing draught can be drunk.
@export var draught_cooldown := 25.0

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
## Knocked back enemies slide: their speed falls off by this share a second.
@export var knock_decay := 10.0
## Seconds for an enemy's poise to come back to full once it is left alone.
@export var poise_regen_time := 2.0
## Screen shake and the red edge when the player is hurt: shake in px, and the health share
## below which the edge shows.
@export var hurt_shake := 3.0
@export var low_health := 0.35

@export_group("Projectiles")
## A projectile hits a body whose center is this close to its path.
@export var projectile_radius := 8.0
## The server only accepts a shot this share of the time its draw takes, as the client's clock
## and the packets lag.
@export var draw_slack := 0.7

@export_group("Dash")
@export var dash_distance := 64.0
@export var dash_time := 0.15
@export var dash_cost := 25.0
@export var dash_cooldown := 0.4
## I-frames from the start of a dash, plus a latency tolerance (PLAN §4.4).
@export var iframes := 0.25
@export var iframe_slack := 0.1
## A dash that starts this long or less before a hit lands dodges it perfectly: stamina back,
## and the attacker is left open for perfect_stagger seconds.
@export var perfect_window := 0.2
@export var perfect_stamina := 35.0
@export var perfect_stagger := 0.8

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
@export var scale_damage := 0.0
@export var scale_count := 0.3

@export_group("Gathering")
## Seconds a player needs per stick or pebble picked up by hand.
@export var gather_time := 1.0
## Health of a tree and a rock, and the tool tier (ItemDef.tool_tier) each needs. A swing that
## reaches one takes the best matching tool's damage off; damaged nodes are only remembered
## while their chunk is loaded.
@export var tree_health := 45.0
@export var rock_health := 60.0
@export var tree_tier := 1
## Stamina a swing that hits a tree or rock costs, in place of its weapon's cost.
@export var node_swing_cost := 4.0
@export var rock_tier := 1

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
@export var stick_drops: Array
@export var pebble_drops: Array

@export_group("Crafting")
## How close to a station (a PieceDef with station) a player must stand to craft there.
@export var station_reach := 40.0

@export_group("Building")
## How far from a tile's center a player can build or remove a piece there.
@export var build_reach := 64.0
## Damaged pieces can't be repaired while an enemy is this close.
@export var repair_lock_radius := 160.0

@export_group("Dungeon")
## Where the barrow's entrance stands in the overworld; players respawn here after dying inside.
@export var dungeon_entrance := Vector2(-96, -16)
## How close to the entrance or a run's exit a player must stand to use it.
@export var portal_reach := 40.0
## Seconds after a run opens during which others entering join it instead of opening their own.
@export var dungeon_join_window := 30.0
## The end chest stays shut while an enemy is this close, and gives each player who opens it
## these (see Loot.roll), heavier on rare items than anything else.
@export var chest_lock_radius := 200.0
@export var chest_drops: Array
## What waits at a room's spawns (RoomDef.spawns).
@export var dungeon_enemy: EnemyDef
## What waits at the end chest, one per run, scaled like the end room's enemies.
@export var dungeon_boss: EnemyDef
## Middle rooms between a run's start and end room, picked from res://data/rooms/.
@export var dungeon_rooms_min := 4
@export var dungeon_rooms_max := 6
## The corridors joining one room to the next.
@export var corridor_length := 64.0
@export var corridor_width := 48.0
## Share of max health everyone alive in a run gets back when its woken rooms are cleared.
@export var room_clear_heal := 0.4
## Added to the health and damage multipliers of a room's enemies per room from the start
## (depth), per minute since the run opened (the Risk of Rain timer, PLAN §5.6) and, for health
## and count, per extra player near the room: rooms scale with players in place of scale_*.
@export var depth_health := 0.15
@export var depth_damage := 0.075
@export var minute_health := 0.1
@export var minute_damage := 0.05
@export var room_health := 0.25
@export var room_count := 1.0

@export_group("Buffs")
## Chance an enemy killed inside a run drops a buff orb.
@export var buff_chance := 0.2
## Relative chance of a dropped buff being of each ItemDef.Rarity, common first.
@export var buff_rarity_weights: Array[float] = [70.0, 25.0, 5.0]
## Added to Buffs.roll's rare_bonus per room the run has reached: orbs get rarer deeper in.
@export var buff_depth_bonus := 0.25
## Seconds a bleed from one hit lasts; a new hit starts it over.
@export var bleed_time := 3.0
## Enemies this close to a dashing player take its dash_damage.
@export var dash_burst_radius := 48.0
