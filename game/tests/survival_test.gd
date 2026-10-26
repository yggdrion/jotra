extends GdUnitTestSuite
## Survival: hunger, eating, starving, the day/night clock and stronger nights.

const TICK := 0.1


func test_hunger_drains_and_eating_restores_it() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var t := Content.tuning
	assert_float(player.hunger).is_equal_approx(t.max_hunger - t.hunger_drain * TICK, 0.001)
	assert_bool(player.eat(-1)).is_false()  # nothing to eat
	player.hunger = 20.0
	player.inventory.add(&"wood", 1)
	player.inventory.add(&"berries", 2)
	assert_bool(player.eat(0)).is_false()  # wood is no food
	assert_bool(player.eat(-1)).is_true()
	assert_float(player.hunger).is_equal(20.0 + Content.item(&"berries").food)
	assert_int(player.inventory.count_of(&"berries")).is_equal(1)
	player.hunger = t.max_hunger
	assert_bool(player.eat(1)).is_false()  # full
	assert_int(player.inventory.count_of(&"berries")).is_equal(1)


func test_eating_never_overfills() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.hunger = Content.tuning.max_hunger - 1
	player.inventory.add(&"trail_ration", 1)
	assert_bool(player.eat(0)).is_true()
	assert_float(player.hunger).is_equal(Content.tuning.max_hunger)


func test_fed_players_heal_and_starving_ones_waste_away() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var t := Content.tuning
	player.health = 50.0
	world.tick(1.0)
	assert_float(player.health).is_equal_approx(50.0 + t.health_regen, 0.001)
	player.hunger = 0.0
	player.stamina = 0.0
	world.tick(1.0)
	assert_float(player.health).is_equal_approx(50.0 + t.health_regen - t.starve_damage, 0.001)
	assert_float(player.stamina).is_equal_approx(t.stamina_regen * t.starve_stamina, 0.001)


func test_starving_to_death_respawns_with_some_hunger() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.hunger = 0.0
	player.health = Content.tuning.starve_damage * TICK
	world.tick(TICK)
	assert_float(player.dead_until).is_greater(0.0)
	for i in ceili(Content.tuning.respawn_delay / TICK) + 1:
		world.tick(TICK)
	assert_float(player.dead_until).is_equal(0.0)
	assert_float(player.hunger).is_greater_equal(
		Content.tuning.respawn_hunger - Content.tuning.hunger_drain
	)


func test_hunger_is_saved() -> void:
	var path := create_temp_dir("survival_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	world.add_player(1, "ann").hunger = 12.5
	world.remove_player(1)
	assert_float(SimWorld.open(path).add_player(2, "ann").hunger).is_equal(12.5)


func test_day_turns_to_night_and_back() -> void:
	var t := Content.tuning
	var day := t.day_length + t.night_length
	assert_bool(Survival.is_night(0.0)).is_false()
	assert_float(Survival.daylight(0.0)).is_equal(1.0)
	assert_float(Survival.daylight(t.day_length / 2)).is_equal(1.0)
	assert_float(Survival.daylight(t.day_length - t.twilight / 2)).is_equal_approx(0.5, 0.001)
	assert_bool(Survival.is_night(t.day_length + 1)).is_true()
	assert_float(Survival.daylight(t.day_length + 1)).is_equal(0.0)
	assert_float(Survival.until_change(t.day_length + 1)).is_equal(t.night_length - 1)
	assert_int(Survival.day_number(day - 1)).is_equal(1)
	assert_int(Survival.day_number(day)).is_equal(2)
	assert_float(Survival.daylight(day)).is_equal(0.0)  # dawn of day 2 starts dark
	assert_float(Survival.daylight(day + t.twilight)).is_equal(1.0)


func test_nights_bring_more_and_stronger_enemies() -> void:
	var day := _spawned(0.0)
	var night := _spawned(Content.tuning.day_length)
	assert_int(night.size()).is_greater(day.size())
	for enemy: SimEnemy in night:
		assert_float(enemy.max_health).is_equal_approx(
			Content.tuning.enemy.health * Content.tuning.night_health, 0.001
		)


func _spawned(time: float) -> Array:
	var world := SimWorld.new()
	world.time = time
	world.add_player(1, "p1")
	for i in 300:
		world.tick(TICK)
	return world.enemies.values()


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1")
	world.tick(TICK)
	return world
