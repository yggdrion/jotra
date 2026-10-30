extends GdUnitTestSuite
## The enemy behaviors in SimWorld (EnemyDef.behavior): archer, wolf pack, shield, exploder and
## the day/night spawn mix.

const TICK := 0.1


func test_archer_keeps_its_distance_and_shoots_along_the_telegraphed_line() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"draugr_archer"]
	var archer := world.add_enemy(Vector2(def.preferred_distance - 40, 0), 45, 10, def)
	world.tick(TICK)
	world.tick(TICK)
	assert_float(archer.position.x).is_greater(def.preferred_distance - 40)  # backing off
	var windup := _windup(world)
	assert_array(windup).is_not_empty()
	assert_vector(windup[5]).is_equal_approx(Vector2.LEFT, Vector2(0.01, 0.01))
	assert_float(windup[4]).is_equal(def.arrow_range)
	assert_int(world.projectiles.size()).is_equal(0)
	for i in 20:
		if not world.projectiles.is_empty():
			break
		world.tick(TICK)
	assert_int(world.projectiles.size()).is_equal(1)
	var arrow: SimProjectile = world.projectiles.values()[0]
	assert_int(arrow.team).is_equal(SimProjectile.Team.ENEMIES)
	assert_int(arrow.owner_id).is_equal(archer.id)
	assert_float(arrow.velocity.angle_to(Vector2.LEFT)).is_equal_approx(0.0, 0.01)
	for i in 10:
		world.tick(TICK)
	assert_float(world.players[1].health).is_less(Content.tuning.max_health)


func test_archer_arrow_keeps_the_telegraphed_aim_when_target_moves() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"draugr_archer"]
	var archer := world.add_enemy(Vector2(def.preferred_distance + 20, 0), 45, 10, def)
	var windup: Array = []
	for i in 5:
		world.tick(TICK)
		windup = _windup(world)
		if not windup.is_empty():
			break
	assert_array(windup).is_not_empty()
	var telegraphed: Vector2 = windup[5]
	world.players[1].position += Vector2(0, 100)
	for i in 20:
		if not world.projectiles.is_empty():
			break
		world.tick(TICK)
	var arrow: SimProjectile = world.projectiles.values()[0]
	assert_vector(arrow.velocity.normalized()).is_equal_approx(telegraphed, Vector2(0.01, 0.01))
	assert_bool(world.enemies.has(archer.id)).is_true()


func test_dashing_sideways_dodges_the_arrow() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"draugr_archer"]
	world.add_enemy(Vector2(def.preferred_distance + 20, 0), 45, 10, def)
	_windup(world)
	world.tick(def.windup - 0.1)
	assert_bool(world.dash(1)).is_true()
	assert_bool(world.move_player(1, Vector2(0, Content.tuning.dash_distance))).is_true()
	for i in 12:
		world.tick(TICK)
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health)


func test_a_provoked_wolf_wakes_its_pack_and_lunges() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"wolf"]
	var pack: Array[SimEnemy] = []
	for at in [Vector2(300, 0), Vector2(320, 20), Vector2(320, -20)]:
		var wolf := world.add_enemy(at, 28, 14, def)
		wolf.pack = 7
		pack.append(wolf)
	var stranger := world.add_enemy(Vector2(0, 300), 28, 14, def)
	# Out of notice range for all of them; only a hit on the first wakes it.
	world.tick(TICK)
	assert_int(pack[1].state).is_equal(SimEnemy.State.IDLE)
	pack[0].provoke(1)
	world.tick(TICK)
	assert_int(pack[1].state).is_equal(SimEnemy.State.CHASE)
	assert_int(pack[2].state).is_equal(SimEnemy.State.CHASE)
	assert_int(stranger.state).is_equal(SimEnemy.State.IDLE)
	# Within lunge range the windup ends in a dash that reaches a target further than melee.
	var lone := world.add_enemy(Vector2(def.attack_range - 5, 0), 28, 14, def)
	lone.provoke(1)
	_windup(world)
	world.tick(def.windup + TICK)
	assert_float(world.players[1].health).is_less(Content.tuning.max_health)
	assert_float(lone.position.length()).is_less(def.attack_range - 5)


func test_a_wolf_telegraphs_its_lane_and_a_side_step_dodges_it() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"wolf"]
	var wolf := world.add_enemy(Vector2(def.attack_range - 5, 0), 28, 14, def)
	wolf.provoke(1)
	world.events.clear()
	var windup := _windup(world)
	assert_vector(windup[5]).is_equal_approx(Vector2.LEFT, Vector2(0.01, 0.01))
	assert_float(windup[4]).is_equal(def.lunge_distance + def.lunge_reach)
	assert_float(windup[6]).is_equal(0.0)
	# Out of the lane before the windup ends: the lunge runs past.
	world.players[1].position = Vector2(0, def.lunge_reach * 2)
	world.tick(def.windup + TICK)
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health)


func test_shield_blocks_the_front_but_not_the_back_or_a_heavy() -> void:
	var def: EnemyDef = Content.enemies[&"shield_draugr"]
	var light := Content.tuning.fists_light.damage
	var front := _swing(def, Vector2.LEFT, false)
	assert_float(front.health).is_equal_approx(100.0 - light * def.block_pass, 0.001)
	var back := _swing(def, Vector2.RIGHT, false)  # looking away from the player
	assert_float(back.health).is_equal(100.0 - light)
	var heavy := _swing(def, Vector2.LEFT, true)
	assert_float(heavy.health).is_less(100.0 - light)


## A fresh world: player 1 swings at a shield draugr 20 px to the right, facing the way given.
## Returns the enemy.
func _swing(def: EnemyDef, facing: Vector2, heavy: bool) -> SimEnemy:
	var world := _world()
	var enemy := world.add_enemy(Vector2(20, 0), 100, 0, def)
	enemy.facing = facing
	world.attack(1, heavy, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	var blocked := world.events.any(
		func(e: Array) -> bool: return e[0] == "enemy" and e[2] == Net.EnemyEvent.BLOCK
	)
	assert_bool(blocked).is_equal(not heavy and facing == Vector2.LEFT)
	return enemy


func test_shield_blocks_arrows_from_the_front_only() -> void:
	var def: EnemyDef = Content.enemies[&"shield_draugr"]
	var world := _world()
	var shield := world.add_enemy(Vector2(300, 0), 100, 0, def)
	shield.facing = Vector2.LEFT
	world.add_projectile(
		SimProjectile.Team.PLAYERS, 1, Vector2(250, 0), Vector2.RIGHT, 300, 40, 200
	)
	world.tick(0.3)
	assert_float(shield.health).is_equal_approx(100.0 - 40 * def.block_pass, 0.001)
	shield.health = 100.0
	world.add_projectile(SimProjectile.Team.PLAYERS, 1, Vector2(350, 0), Vector2.LEFT, 300, 40, 200)
	world.tick(0.3)
	assert_float(shield.health).is_equal_approx(60.0, 0.001)


func test_shield_turns_slowly() -> void:
	var def: EnemyDef = Content.enemies[&"shield_draugr"]
	var world := _world()
	var shield := world.add_enemy(Vector2(100, 0), 100, 0, def)
	shield.facing = Vector2.RIGHT
	world.tick(TICK)  # notices the player
	world.tick(TICK)
	var turned := absf(shield.facing.angle_to(Vector2.RIGHT))
	assert_float(turned).is_equal_approx(def.turn_speed * TICK, 0.02)


func test_snapshots_send_a_shields_facing_through_packing() -> void:
	var world := _world()
	var shield := world.add_enemy(Vector2(100, 0), 100, 0, Content.enemies[&"shield_draugr"])
	shield.facing = Vector2.from_angle(2.0)
	var other := world.add_enemy(Vector2(-100, 0), 100, 0, Content.enemies[&"draugr"])
	var snap := world.snapshot_for(1)
	assert_dict(snap.facings).is_equal({shield.id: shield.facing.angle()})
	var bytes := Net.pack_facings(snap.enemies, snap.facings)
	assert_int(bytes.size()).is_equal(1)
	var enemies := Net.unpack_entities(Net.pack_entities(snap.enemies, Vector2.ZERO), Vector2.ZERO)
	var back := Net.unpack_facings(enemies, bytes)
	assert_array(back.keys()).contains_exactly([shield.id])
	assert_float(back[shield.id]).is_equal_approx(2.0, TAU / 512)
	assert_bool(back.has(other.id)).is_false()


func test_exploder_blasts_everyone_in_radius_and_dies() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"bloated_draugr"]
	world.add_player(2, "p2").position = Vector2(def.slam_radius * 3, 0)
	var bloated := world.add_enemy(Vector2(def.attack_range * 2, 0), 40, 40, def)
	_windup(world)
	assert_bool(world.enemies.has(bloated.id)).is_true()
	world.tick(def.windup + TICK)
	assert_bool(world.enemies.has(bloated.id)).is_false()
	assert_float(world.players[1].health).is_less(Content.tuning.max_health)
	assert_float(world.players[2].health).is_equal(Content.tuning.max_health)
	(
		assert_bool(
			world.events.any(
				func(e: Array) -> bool: return e[0] == "enemy" and e[2] == Net.EnemyEvent.DIED
			)
		)
		. is_true()
	)


func test_spawn_mix_follows_the_day_and_night_weights() -> void:
	var world := _world()
	world.rng.seed = 3
	var day := {}
	var night := {}
	for i in 600:
		day[world._pick_kind(false)] = true
		night[world._pick_kind(true)] = true
	for kind: EnemyDef in day:
		assert_float(kind.spawn_weight_day).is_greater(0.0)
	for kind: EnemyDef in night:
		assert_float(kind.spawn_weight_night).is_greater(0.0)
	assert_bool(day.has(Content.enemies[&"wolf"])).is_true()
	assert_bool(day.has(Content.enemies[&"draugr_archer"])).is_false()
	for id in [&"draugr_archer", &"shield_draugr", &"bloated_draugr", &"wolf", &"draugr"]:
		assert_bool(night.has(Content.enemies[id])).override_failure_message(str(id)).is_true()


func test_spawned_packs_share_an_id() -> void:
	var world := SimWorld.new()
	world.rng.seed = 5
	world.add_player(1, "p1").position = Vector2.ZERO
	var wolf: EnemyDef = Content.enemies[&"wolf"]
	for i in 200:
		world._spawn_due = 0.0
		world.time = 0.0
		world.tick(Content.tuning.spawn_interval)
		world.enemies = world.enemies.duplicate()
		var wolves := world.enemies.values().filter(func(e: SimEnemy) -> bool: return e.def == wolf)
		if wolves.size() >= wolf.pack_min:
			assert_int(wolves[0].pack).is_greater(0)
			(
				assert_int(
					wolves.filter(func(e: SimEnemy) -> bool: return e.pack == wolves[0].pack).size()
				)
				. is_greater_equal(wolf.pack_min)
			)
			return
		for id: int in world.enemies.keys():
			world.enemies.erase(id)
	fail("no wolf pack spawned")


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world


## Ticks until an enemy has started a windup, returns its event.
func _windup(world: SimWorld) -> Array:
	for i in 100:
		for e in world.events:
			if e[0] == "windup":
				return e
		world.tick(TICK)
	fail("no windup")
	return []


func test_a_pack_takes_turns_to_lunge() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"wolf"]
	var pack: Array[SimEnemy] = []
	for at in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40)]:
		var wolf := world.add_enemy(at, 28, 14, def)
		wolf.pack = 3
		wolf.provoke(1)
		pack.append(wolf)
	for i in 60:
		world.tick(TICK)
		var busy := pack.filter(
			func(w: SimEnemy) -> bool:
				return w.state in [SimEnemy.State.WINDUP, SimEnemy.State.RECOVER]
		)
		assert_int(busy.size()).is_less_equal(1)
