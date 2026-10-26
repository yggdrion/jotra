extends GdUnitTestSuite
## Dungeon runs: the entrance, joining a run, the walls, the inventory snapshot rule (PLAN §4.8)
## and closing an empty run.

const TICK := 0.1


## A world with p1 standing at the entrance, nothing spawning on its own.
func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1")
	world.players[1].position = Content.tuning.dungeon_entrance
	world.tick(TICK)
	return world


func test_entering_needs_the_entrance_and_leaving_the_exit() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.position = Content.tuning.dungeon_entrance + Vector2(200, 0)
	assert_bool(world.use_portal(1)).is_false()
	player.position = Content.tuning.dungeon_entrance
	assert_bool(world.use_portal(1)).is_true()
	assert_object(player.run).is_not_null()
	assert_vector(player.position).is_equal(player.run.spawn)
	assert_array(world.events.back()).is_equal(
		["dungeon", 1, player.run.area, player.run.exit, player.position]
	)
	assert_bool(world.use_portal(1)).is_false()  # the exit is across the room
	player.position = player.run.exit
	assert_bool(world.use_portal(1)).is_true()
	assert_object(player.run).is_null()
	assert_vector(player.position).is_equal(Content.tuning.dungeon_entrance)


func test_a_run_shows_no_world_chunks() -> void:
	var world := _world()
	world.use_portal(1)
	assert_array(world.interest(1)).is_empty()
	world.tick(TICK)
	assert_int(world.chunks.size()).is_equal(0)


func test_the_layout_chains_start_middle_and_end_rooms() -> void:
	var t := Content.tuning
	for i in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var run := Dungeon.new(i % 3, 0.0, rng)
		var middle := run.rooms.size() - 2
		assert_int(middle).is_between(t.dungeon_rooms_min, t.dungeon_rooms_max)
		assert_int(run.defs[0].kind).is_equal(RoomDef.Kind.START)
		assert_int(run.defs[-1].kind).is_equal(RoomDef.Kind.END)
		assert_int(run.room_of(run.spawn)).is_equal(0)
		assert_int(run.room_of(run.exit)).is_equal(run.rooms.size() - 1)
		assert_int(run.area.size()).is_equal(run.rooms.size() * 2 - 1)
		for rect in run.area:
			assert_bool(run.owns(rect.position) and run.owns(rect.end)).is_true()
		# Each corridor joins the room before it to the one after: walk its middle line.
		for room in range(1, run.rooms.size()):
			var corridor := run.area[room - 1]
			var y := corridor.get_center().y
			assert_int(run.room_of(Vector2(corridor.position.x, y))).is_equal(room - 1)
			assert_int(run.room_of(Vector2(corridor.end.x, y))).is_equal(room)
			for step in 9:
				var at := Vector2(lerpf(corridor.position.x, corridor.end.x, step / 8.0), y)
				assert_vector(Dungeon.clamp_to(run.area, at)).is_equal(at)


func test_rooms_wake_when_walked_into_and_grow_stronger_deeper_and_later() -> void:
	var world := _world()
	world.use_portal(1)
	var run: Dungeon = world.players[1].run
	assert_dict(world.enemies).is_empty()  # nothing waits in the start room
	world.tick(120.0)
	world.players[1].position = run.rooms[2].get_center()
	world.tick(TICK)
	assert_int(run.reached).is_equal(2)
	var kind := Content.tuning.dungeon_enemy
	var spawns := run.defs[1].spawns.size() + run.defs[2].spawns.size()
	assert_int(world.enemies.size()).is_equal(spawns)
	var deeper := Combat.dungeon_scaled(2, run.minutes(world.time))
	var strongest := 0.0
	for enemy: SimEnemy in world.enemies.values():
		assert_int(run.room_of(enemy.home)).is_between(1, 2)
		strongest = maxf(strongest, enemy.max_health)
	assert_float(strongest).is_equal_approx(kind.health * deeper.health, 0.01)
	assert_float(strongest).is_greater(kind.health)
	# Walking back wakes nothing more.
	world.players[1].position = run.spawn
	world.tick(TICK)
	assert_int(run.reached).is_equal(2)


func test_others_join_an_open_run_until_the_window_closes() -> void:
	var world := _world()
	world.use_portal(1)
	for id in [2, 3]:
		world.add_player(id, "p%d" % id)
	world.players[2].position = Content.tuning.dungeon_entrance
	world.use_portal(2)
	world.enemies.clear()  # nobody dies and closes the run while we wait
	assert_object(world.players[2].run).is_same(world.players[1].run)
	world.tick(Content.tuning.dungeon_join_window + 1)
	world.players[3].position = Content.tuning.dungeon_entrance
	world.use_portal(3)
	assert_object(world.players[3].run).is_not_same(world.players[1].run)
	assert_int(world.dungeons.size()).is_equal(2)


func test_moves_through_the_walls_are_dropped() -> void:
	var world := _world()
	world.use_portal(1)
	var player: SimWorld.SimPlayer = world.players[1]
	var start := player.position
	world.tick(1.0)
	assert_bool(world.move_player(1, start + Vector2(-40, 0))).is_false()
	assert_bool(world.move_player(1, start + Vector2(20, 0))).is_true()
	var room := player.run.rooms[0]
	assert_vector(Dungeon.clamp_to(player.run.area, room.position - Vector2(5, 5))).is_equal(
		room.position
	)


func test_dying_inside_restores_the_inventory_from_entering() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 3)
	world.use_portal(1)
	player.inventory.add(&"bone", 5)
	player.inventory.take({&"wood": 1})
	player.health = 1.0
	assert_bool(world.damage_player(1, 50.0)).is_true()
	world.tick(Content.tuning.respawn_delay + TICK)
	assert_object(player.run).is_null()
	assert_vector(player.position).is_equal(Content.tuning.dungeon_entrance)
	assert_int(player.inventory.count_of(&"wood")).is_equal(3)
	assert_int(player.inventory.count_of(&"bone")).is_equal(0)
	assert_float(player.health).is_equal(player.max_health())


func test_leaving_by_the_exit_keeps_what_was_found() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	world.use_portal(1)
	player.inventory.add(&"bone", 5)
	player.position = player.run.exit
	world.use_portal(1)
	assert_int(player.inventory.count_of(&"bone")).is_equal(5)


func test_the_last_one_out_closes_the_run() -> void:
	var world := _world()
	world.use_portal(1)
	var run: Dungeon = world.players[1].run
	var drop := world.add_drop(&"bone", 1, run.exit + Vector2(0, 30))
	world.players[1].position = run.exit
	world.tick(TICK)  # the end room wakes
	assert_dict(world.enemies).is_not_empty()
	world.use_portal(1)
	assert_dict(world.dungeons).is_empty()
	assert_dict(world.enemies).is_empty()
	assert_bool(world.drops.has(drop.id)).is_false()


func test_drops_inside_a_run_stay_without_chunks() -> void:
	var world := _world()
	world.use_portal(1)
	var run: Dungeon = world.players[1].run
	var drop := world.add_drop(&"bone", 1, run.exit)
	world.tick(TICK)
	assert_bool(world.drops.has(drop.id)).is_true()


func test_saves_inside_store_the_snapshot_at_the_entrance() -> void:
	var path := create_temp_dir("dungeon_save_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	world.spawn_enemies = false
	var player := world.add_player(1, "ann")
	player.position = Content.tuning.dungeon_entrance
	player.inventory.add(&"wood", 2)
	world.tick(TICK)
	world.use_portal(1)
	player.inventory.add(&"bone", 4)
	# A periodic save inside, then a crash: the run is gone, and so is what was found in it.
	world.save()
	_assert_back_at_the_entrance(SimWorld.open(path).add_player(2, "ann"))
	# Leaving the game inside counts as dying there.
	world.remove_player(1)
	assert_dict(world.dungeons).is_empty()
	_assert_back_at_the_entrance(SimWorld.open(path).add_player(2, "ann"))


func _assert_back_at_the_entrance(ann: SimWorld.SimPlayer) -> void:
	assert_vector(ann.position).is_equal(Content.tuning.dungeon_entrance)
	assert_int(ann.inventory.count_of(&"wood")).is_equal(2)
	assert_int(ann.inventory.count_of(&"bone")).is_equal(0)
