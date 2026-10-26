class_name Combat
## Combat rules shared by server and client: the one self-scaling formula (PLAN §5.6), swing
## arcs and armor. The numbers are data: Content.tuning, enemy and item definitions.


## Multipliers on enemy health, damage and count for the number of players near an encounter.
static func scaled(nearby_players: int) -> Dictionary:
	var t := Content.tuning
	var extra := maxi(nearby_players - 1, 0)
	return {
		health = 1.0 + t.scale_health * extra,
		damage = 1.0 + t.scale_damage * extra,
		count = 1.0 + t.scale_count * extra,
	}


## Multipliers on enemy health, damage and count in a dungeon room depth rooms from the start,
## minutes after its run opened, with nearby_players near it. Rooms scale with players on their
## own terms: a group fights one room together instead of spread out over the world.
static func dungeon_scaled(depth: int, minutes: float, nearby_players := 1) -> Dictionary:
	var t := Content.tuning
	var extra := maxi(nearby_players - 1, 0)
	return {
		health = 1.0 + t.depth_health * depth + t.minute_health * minutes + t.room_health * extra,
		damage = 1.0 + t.depth_damage * depth + t.minute_damage * minutes,
		count = 1.0 + t.room_count * extra,
	}


## A swing's damage with a player's buffs, before crits.
static func swing_damage(move: AttackDef, heavy: bool, buffs: Buffs) -> float:
	var bonus := buffs.stat("damage") + (buffs.stat("heavy_damage") if heavy else 0.0)
	return move.damage * (1.0 + bonus)


## A swing's cooldown with a player's buffs; the client waits the same.
static func cooldown(move: AttackDef, buffs: Buffs) -> float:
	return move.cooldown * maxf(1.0 - buffs.stat("attack_speed"), 0.5)


## Whether a swing from origin toward aim, reach long and arc degrees wide, hits target.
static func in_arc(
	origin: Vector2, aim: Vector2, target: Vector2, reach: float, arc: float
) -> bool:
	var to := target - origin
	if to.length() > reach:
		return false
	if to.length() <= Content.tuning.point_blank:
		return true
	return absf(aim.angle_to(to)) <= deg_to_rad(arc) / 2


## A hit of amount on a wearer of armor: weapon damage − armor (PLAN §5.2), never below
## min_damage.
static func after_armor(amount: float, armor: float) -> float:
	return maxf(amount - armor, minf(Content.tuning.min_damage, amount))
