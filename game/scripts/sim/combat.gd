class_name Combat
## Combat numbers and rules shared by server and client: attacks, dash, enemies, and the one
## self-scaling formula (PLAN §5.6). Distances in px, times in seconds.
# ponytail: constants until M4 brings weapons and items as .tres resources.

const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0
## Stamina per second, once STAMINA_DELAY has passed since it was last spent.
const STAMINA_REGEN := 35.0
const STAMINA_DELAY := 0.6

## Arc is the full swing angle in degrees, centered on the aim.
const LIGHT := {damage = 10, reach = 28.0, arc = 100.0, cooldown = 0.35, cost = 12.0, knock = 10.0}
const HEAVY := {damage = 25, reach = 34.0, arc = 150.0, cooldown = 0.8, cost = 30.0, knock = 28.0}
## The server's copies of attacker and target lag the client's view, so it accepts hits a bit
## further and wider than the client reports them.
const HIT_SLACK := 24.0
const ARC_SLACK := 60.0
## Targets this close count as hit whatever the aim.
const POINT_BLANK := 8.0

const DASH_DISTANCE := 64.0
const DASH_TIME := 0.15
const DASH_COST := 25.0
const DASH_COOLDOWN := 0.4
## I-frames from the start of a dash, plus a latency tolerance (PLAN §4.4).
const IFRAMES := 0.25
const IFRAME_SLACK := 0.1

const RESPAWN_DELAY := 3.0
const RESPAWN_AT := Vector2.ZERO

const ENEMY_HEALTH := 40.0
const ENEMY_DAMAGE := 15.0
const ENEMY_SPEED := 70.0
const NOTICE_RADIUS := 160.0
const ATTACK_RANGE := 22.0
## Extra range for the hit at the end of a windup, as the server's copy of the target lags.
const ATTACK_SLACK := 8.0
## The telegraph before an enemy hit lands: dash out or away.
const WINDUP := 0.5
const ENEMY_COOLDOWN := 1.0
## An enemy chasing further than this from home gives up, walks back and heals.
const LEASH := 400.0

## Each living player is topped up to ENEMIES_PER_PLAYER × count scaling enemies within
## SPAWN_RADIUS, one spawn per player every SPAWN_INTERVAL, on a ring around them.
const ENEMIES_PER_PLAYER := 3
const SPAWN_INTERVAL := 2.0
const SPAWN_RADIUS := 500.0
const SPAWN_RING_MIN := 300.0
const SPAWN_RING_MAX := 450.0
## Enemies with no player this close are dropped.
const DESPAWN_RADIUS := 900.0
## Players this close to an encounter count for its scaling.
const SCALE_RADIUS := 400.0


## Multipliers on enemy health, damage and count for the number of players near an encounter.
static func scaled(nearby_players: int) -> Dictionary:
	var extra := maxi(nearby_players - 1, 0)
	return {health = 1.0 + 0.5 * extra, damage = 1.0 + 0.25 * extra, count = 1.0 + 0.75 * extra}


## Whether a swing from origin toward aim, reach long and arc degrees wide, hits target.
static func in_arc(
	origin: Vector2, aim: Vector2, target: Vector2, reach: float, arc: float
) -> bool:
	var to := target - origin
	if to.length() > reach:
		return false
	if to.length() <= POINT_BLANK:
		return true
	return absf(aim.angle_to(to)) <= deg_to_rad(arc) / 2
