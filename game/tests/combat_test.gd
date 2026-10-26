extends GdUnitTestSuite
## Combat in SimWorld: attacks and stamina, enemy AI, dash i-frames, death and respawn,
## self-scaling.

const TICK := 0.1


func test_attack_spends_stamina_and_cools_down() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(20, 0), 100, 0)
	var hits := PackedInt32Array([enemy.id])
	assert_array(Array(world.attack(1, false, Vector2.RIGHT, hits))).is_equal([enemy.id])
	assert_float(world.players[1].stamina).is_equal(
		Content.tuning.max_stamina - Content.tuning.fists_light.cost
	)
	assert_array(world.events[0]).is_equal(["swing", 1, false, Vector2.RIGHT, Vector2.ZERO, &""])
	assert_array(Array(world.attack(1, false, Vector2.RIGHT, hits))).is_empty()
	(
		assert_int(world.events.filter(func(e: Array) -> bool: return e[0] == "swing").size())
		. is_equal(1)
	)
	world.tick(Content.tuning.fists_light.cooldown)
	world.players[1].stamina = Content.tuning.fists_light.cost - 1
	assert_array(Array(world.attack(1, false, Vector2.RIGHT, hits))).is_empty()
	assert_float(enemy.health).is_equal(100.0 - Content.tuning.fists_light.damage)


func test_hits_only_what_is_in_the_arc() -> void:
	var world := _world()
	var front := world.add_enemy(Vector2(20, 0), 100, 0)
	var behind := world.add_enemy(Vector2(-20, 0), 100, 0)
	var far := world.add_enemy(Vector2(100, 0), 100, 0)
	var hits := PackedInt32Array([front.id, behind.id, far.id])
	assert_array(Array(world.attack(1, true, Vector2.RIGHT, hits))).is_equal([front.id])
	assert_float(front.health).is_equal(100.0 - Content.tuning.fists_heavy.damage)
	assert_bool(front.position.x > 20).is_true()  # knocked back


func test_enemy_dies_and_leaves_the_snapshot() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(20, 0), Content.tuning.fists_light.damage, 0)
	assert_int(world.snapshot_for(1).enemies.size()).is_equal(1)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_dict(world.snapshot_for(1).enemies).is_empty()
	assert_array(world.events[-1].slice(0, 3)).is_equal(["hit", true, enemy.id])


func test_enemy_chases_and_hits_after_the_windup() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(100, 0), 100, 15)
	_tick_until_windup(world)
	assert_bool(enemy.position.x <= Content.tuning.enemy.attack_range).is_true()
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health)
	world.tick(Content.tuning.enemy.windup)
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health - 15)


func test_dash_at_the_right_moment_avoids_the_hit() -> void:
	var world := _world()
	world.add_enemy(Vector2(100, 0), 100, 15)
	_tick_until_windup(world)
	world.tick(Content.tuning.enemy.windup - TICK)
	assert_bool(world.dash(1)).is_true()
	world.tick(2 * TICK)
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health)


func test_dead_player_cannot_move_and_respawns() -> void:
	var world := _world()
	world.players[1].position = Vector2(50, 0)
	world.damage_player(1, Content.tuning.max_health)
	assert_float(world.players[1].dead_until).is_greater(0.0)
	assert_bool(world.move_player(1, Vector2(51, 0))).is_false()
	assert_bool(world.dash(1)).is_false()
	world.tick(Content.tuning.respawn_delay)
	var player: SimWorld.SimPlayer = world.players[1]
	assert_float(player.dead_until).is_equal(0.0)
	assert_float(player.health).is_equal(Content.tuning.max_health)
	assert_vector(player.position).is_equal(Content.tuning.respawn_at)
	assert_array(world.events[-1]).is_equal(["respawn", 1, Content.tuning.respawn_at])


func test_enemy_led_too_far_walks_home_and_heals() -> void:
	var world := _world()
	world.players[1].position = Vector2(30, 0)
	var enemy := world.add_enemy(Vector2.ZERO, 100, 0)
	enemy.health = 10
	world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.CHASE)
	world.players[1].position = Vector2(600, 0)
	for i in 200:
		world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.IDLE)
	assert_vector(enemy.position).is_equal(Vector2.ZERO)
	assert_float(enemy.health).is_equal(100.0)


func test_more_players_nearby_bring_more_and_stronger_enemies() -> void:
	assert_dict(Combat.scaled(1)).is_equal({health = 1.0, damage = 1.0, count = 1.0})
	var solo := _spawned(1)
	var duo := _spawned(2)
	assert_int(solo.size()).is_equal(Content.tuning.enemies_per_player)
	assert_int(duo.size()).is_greater(solo.size())
	for enemy: SimEnemy in solo:
		assert_float(enemy.max_health).is_equal(Content.tuning.enemy.health)
	for enemy: SimEnemy in duo:
		assert_float(enemy.max_health).is_equal(
			Content.tuning.enemy.health * Combat.scaled(2).health
		)


func test_dash_allows_its_distance_once() -> void:
	var world := _world()
	var far := Vector2(Content.tuning.walk_speed * (TICK + SimWorld.MOVE_SLACK) + 30, 0)
	assert_bool(world.move_player(1, far)).is_false()
	world.dash(1)
	assert_bool(world.move_player(1, far)).is_true()
	world.tick(1.0)
	var further := far + Vector2(Content.tuning.walk_speed * (1.0 + SimWorld.MOVE_SLACK) + 30, 0)
	assert_bool(world.move_player(1, further)).is_false()


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


## The enemies spawned around count players standing together, after long enough.
func _spawned(count: int) -> Array:
	var world := SimWorld.new()
	for i in count:
		world.add_player(i + 1, "p%d" % i)
	for i in 300:
		world.tick(TICK)
	return world.enemies.values()


func test_walking_away_from_a_windup_is_no_escape() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(Content.tuning.enemy.attack_range, 0), 100, 15)
	enemy.provoke(1)
	world.tick(TICK)
	assert_int(enemy.state).is_equal(SimEnemy.State.WINDUP)
	var player: SimWorld.SimPlayer = world.players[1]
	var health := player.health
	for i in ceili(Content.tuning.enemy.windup / TICK) + 1:
		world.move_player(1, player.position + Vector2(-Content.tuning.walk_speed * TICK, 0))
		world.tick(TICK)
	assert_float(player.health).is_less(health)


func test_dungeon_enemies_grow_with_depth_and_time() -> void:
	assert_dict(Combat.dungeon_scaled(0, 0.0)).is_equal({health = 1.0, damage = 1.0})
	var shallow := Combat.dungeon_scaled(1, 0.0)
	var deep := Combat.dungeon_scaled(5, 0.0)
	var late := Combat.dungeon_scaled(1, 10.0)
	assert_float(deep.health).is_greater(shallow.health)
	assert_float(deep.damage).is_greater(shallow.damage)
	assert_float(late.health).is_greater(shallow.health)
	assert_float(late.damage).is_greater(shallow.damage)
