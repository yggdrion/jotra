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
		["dungeon", 1, player.run.rooms, player.run.exit, player.position]
	)
	assert_bool(world.use_portal(1)).is_false()  # the exit is across the room
	player.position = player.run.exit
	assert_bool(world.use_portal(1)).is_true()
	assert_object(player.run).is_null()
	assert_vector(player.position).is_equal(Content.tuning.dungeon_entrance)


func test_a_run_shows_no_world_chunks_and_spawns_its_own_enemies() -> void:
	var world := _world()
	world.use_portal(1)
	assert_array(world.interest(1)).is_empty()
	assert_int(world.enemies.size()).is_equal(Content.tuning.dungeon_enemies)
	var run: Dungeon = world.players[1].run
	for enemy: SimEnemy in world.enemies.values():
		assert_bool(run.owns(enemy.position)).is_true()
	world.tick(TICK)
	assert_int(world.chunks.size()).is_equal(0)


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
	assert_vector(Dungeon.clamp_to(player.run.rooms, room.position - Vector2(5, 5))).is_equal(
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
