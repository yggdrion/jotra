extends GdUnitTestSuite
## Combat feel in SimWorld: knockback that slides, poise and stagger, heavies breaking windups,
## recovery after a hit, perfect dodges, leash and the events clients animate from.

const TICK := 0.1


func test_knockback_slides_and_stops_at_its_distance() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(20, 0), 1000, 0)
	enemy.speed = 0.0
	var move := Content.tuning.fists_heavy
	world.attack(1, true, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_float(enemy.position.x).is_equal(20.0)  # not at once
	world.tick(0.03)
	var early := enemy.position.x
	assert_float(early).is_greater(20.0)
	for i in 30:
		world.tick(0.03)
	assert_float(enemy.position.x).is_greater(early)
	assert_float(enemy.position.x).is_between(20 + move.knock * 0.8, 20 + move.knock * 1.1)
	assert_vector(enemy.knock_vel).is_equal(Vector2.ZERO)


func test_a_heavy_breaks_a_windup_but_a_light_does_not() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(10, 0), 1000, 15)
	enemy.provoke(1)
	world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.WINDUP)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_int(enemy.state).is_equal(SimEnemy.State.WINDUP)
	world.tick(Content.tuning.fists_light.cooldown)
	world.players[1].stamina = 100
	world.attack(1, true, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_int(enemy.state).is_equal(SimEnemy.State.STAGGER)
	var health: float = world.players[1].health
	world.tick(enemy.def.windup + TICK)
	assert_float(world.players[1].health).is_equal(health)  # the hit never landed
	world.tick(enemy.def.stagger_time)
	assert_int(enemy.state).is_not_equal(SimEnemy.State.STAGGER)


func test_lights_wear_poise_down_to_a_stagger_and_it_comes_back() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(60, 0), 1000, 0)
	enemy.provoke(1)
	var light := Content.tuning.fists_light
	var swings := ceili(enemy.def.poise / light.poise_damage)
	for i in swings:
		assert_int(enemy.state).is_not_equal(SimEnemy.State.STAGGER)
		enemy.hit_poise(world, light.poise_damage)
	assert_int(enemy.state).is_equal(SimEnemy.State.STAGGER)
	assert_float(enemy.poise).is_equal(enemy.def.poise)
	assert_array(world.events[-1]).is_equal(
		["enemy", enemy.id, Net.EnemyEvent.STAGGER, enemy.position]
	)


func test_enemy_is_open_for_its_recovery_after_a_hit() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(10, 0), 1000, 15)
	_tick_until_windup(world)
	world.tick(enemy.def.windup)
	assert_int(enemy.state).is_equal(SimEnemy.State.RECOVER)
	var at := enemy.position
	world.players[1].position = Vector2(300, 0)
	world.tick(enemy.def.recovery - TICK)
	assert_vector(enemy.position).is_equal(at)
	world.tick(TICK * 2)
	assert_int(enemy.state).is_equal(SimEnemy.State.CHASE)


func test_a_perfect_dodge_refunds_stamina_and_leaves_the_enemy_open() -> void:
	var world := _world()
	var t := Content.tuning
	var enemy := world.add_enemy(Vector2(10, 0), 1000, 15)
	_tick_until_windup(world)
	world.tick(enemy.def.windup - t.perfect_window / 2)
	world.dash(1)
	assert_float(world.players[1].stamina).is_equal(t.max_stamina - t.dash_cost)
	world.events.clear()
	world.tick(TICK)
	assert_float(world.players[1].health).is_equal(t.max_health)
	assert_float(world.players[1].stamina).is_equal(t.max_stamina)
	assert_bool(world.events.any(func(e: Array) -> bool: return e[0] == "perfect")).is_true()
	world.tick(t.perfect_stagger - TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.RECOVER)
	world.tick(TICK * 2)
	assert_int(enemy.state).is_equal(SimEnemy.State.CHASE)


func test_an_early_dash_is_not_perfect() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(10, 0), 1000, 15)
	_tick_until_windup(world)
	world.dash(1)
	world.tick(enemy.def.windup - TICK)
	world.events.clear()
	world.tick(TICK * 2)
	assert_bool(world.events.any(func(e: Array) -> bool: return e[0] == "perfect")).is_false()


func test_a_death_is_announced() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(20, 0), 1, 0)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_array(world.events[-1]).is_equal(
		["enemy", enemy.id, Net.EnemyEvent.DIED, enemy.position]
	)


func test_leash_is_measured_from_the_target_and_heals_gradually() -> void:
	var world := _world()
	var def := Content.tuning.enemy
	world.players[1].position = Vector2(def.leash * 0.8, 0)
	var enemy := world.add_enemy(Vector2(def.leash * 0.5, 0), 100, 0)
	enemy.health = 10
	enemy.home = Vector2(def.leash * 0.5, 0)
	enemy.provoke(1)
	world.tick(TICK)
	# The enemy is far from its target but the target is near home: it keeps chasing.
	assert_int(enemy.state).is_not_equal(SimEnemy.State.LEASH)
	world.players[1].position = Vector2(def.leash * 0.5 + def.leash + 10, 0)
	world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.LEASH)
	(
		assert_array(world.events.filter(func(e: Array) -> bool: return e[0] == "enemy")[-1])
		. is_equal(["enemy", enemy.id, Net.EnemyEvent.GAVE_UP, enemy.position])
	)
	world.tick(1.0)
	assert_float(enemy.health).is_greater(10.0)
	assert_float(enemy.health).is_less(100.0)


func test_enemy_slows_down_while_winding_up() -> void:
	var world := _world()
	var def := Content.tuning.enemy
	var enemy := world.add_enemy(Vector2(def.attack_range, 0), 100, 15)
	enemy.provoke(1)
	world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.WINDUP)
	# The player stands off at 3 attack ranges: the enemy closes in at windup_speed only.
	world.players[1].position = Vector2(-def.attack_range * 3, 0)
	var at := enemy.position
	world.tick(TICK)
	assert_float(at.x - enemy.position.x).is_equal_approx(
		enemy.speed * def.windup_speed * TICK, 0.01
	)
	assert_float(def.windup_speed).is_less(1.0)


## One player at the origin, chunks loaded, no spawning.
func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world


func _tick_until_windup(world: SimWorld) -> void:
	for i in 100:
		world.tick(TICK)
		if world.events.any(func(e: Array) -> bool: return e[0] == "windup"):
			return
	fail("no windup")
