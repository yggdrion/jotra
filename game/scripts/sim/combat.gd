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
