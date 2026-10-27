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


## A hit of amount from an enemy (null: none) on a player, less its armor. Nothing lands while
## the player's dash i-frames run; a dash that began perfect_window or less before a hit dodges
## it perfectly: stamina back and the enemy left open. Returns whether it landed.
static func hit_player(
	world: SimWorld, player: SimWorld.SimPlayer, amount: float, from: SimEnemy
) -> bool:
	var t := Content.tuning
	var b := player.buffs
	var since := world.time - player.dashed_at
	if since <= t.iframes + b.stat("iframes") + t.iframe_slack:
		if from and since <= t.perfect_window:
			player.stamina = minf(player.stamina + t.perfect_stamina, t.max_stamina)
			from.punish(t.perfect_stagger)
			world.events.append(["perfect", player.id])
		return false
	var taken := after_armor(amount, player.inventory.worn("armor") + b.stat("armor"))
	player.health = maxf(player.health - taken, 0.0)
	var push := Vector2.ZERO
	if from:
		push = (player.position - from.position).normalized() * from.def.knock
	world.events.append(["hit", false, player.id, taken, player.position, push])
	return true
