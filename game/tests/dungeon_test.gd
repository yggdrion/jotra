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
	assert_bool(world.interact(1)).is_false()
	player.position = Content.tuning.dungeon_entrance
	assert_bool(world.interact(1)).is_true()
	assert_object(player.run).is_not_null()
	assert_vector(player.position).is_equal(player.run.spawn)
	assert_array(world.events.back()).is_equal(
		["dungeon", 1, player.run.area, player.run.exit, player.run.chest, player.position]
	)
	assert_bool(world.interact(1)).is_false()  # the exit is across the room
	player.position = player.run.exit
	assert_bool(world.interact(1)).is_true()
	assert_object(player.run).is_null()
	assert_vector(player.position).is_equal(Content.tuning.dungeon_entrance)


func test_a_run_shows_no_world_chunks() -> void:
	var world := _world()
	world.interact(1)
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
	world.interact(1)
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
	world.interact(1)
	for id in [2, 3]:
		world.add_player(id, "p%d" % id)
	world.players[2].position = Content.tuning.dungeon_entrance
	world.interact(2)
	world.enemies.clear()  # nobody dies and closes the run while we wait
	assert_object(world.players[2].run).is_same(world.players[1].run)
	world.tick(Content.tuning.dungeon_join_window + 1)
	world.players[3].position = Content.tuning.dungeon_entrance
	world.interact(3)
	assert_object(world.players[3].run).is_not_same(world.players[1].run)
	assert_int(world.dungeons.size()).is_equal(2)


func test_moves_through_the_walls_are_dropped() -> void:
	var world := _world()
	world.interact(1)
	var player: SimWorld.SimPlayer = world.players[1]
	var start := player.position
	world.tick(1.0)
	assert_bool(world.move_player(1, start + Vector2(-40, 0))).is_false()
	assert_bool(world.move_player(1, start + Vector2(20, 0))).is_true()
	var room := player.run.rooms[0]
	assert_vector(Dungeon.clamp_to(player.run.area, room.position - Vector2(5, 5))).is_equal(
		room.position
	)


func test_an_enemy_walks_home_around_a_corner() -> void:
	var world := _world()
	# A layout whose corridor leaves the lower-topped room well below its top; unseeded, some
	# layouts have no such corner and the setup check below fails.
	world.rng.seed = 3
	world.interact(1)
	var run: Dungeon = world.players[1].run
	var west := run.rooms[0]
	var east := run.rooms[1]
	var corridor := run.area[0]
	# From near the top corner of the lower-topped room toward home near the top of the other:
	# the straight way runs into the corner the corridor leaves below it, where the clamp back
	# into the area kept it.
	var from := Vector2(west.end.x - 12, west.position.y + 4)
	var home := Vector2(east.position.x + 12, east.position.y + 4)
	if east.position.y > west.position.y:
		from = Vector2(east.position.x + 12, east.position.y + 4)
		home = Vector2(west.end.x - 12, west.position.y + 4)
	assert_float(corridor.position.y).is_greater(from.y + 4)
	var enemy := world.add_enemy(from, 10, 1)
	enemy.home = home
	enemy.state = SimEnemy.State.LEASH
	assert_bool(Pathing.clear(run.walls, enemy.position, home)).is_false()
	for i in 200:
		world.tick(TICK)
	assert_vector(enemy.position).is_equal(home)
	assert_int(enemy.state).is_not_equal(SimEnemy.State.LEASH)


func test_dying_inside_restores_the_inventory_from_entering() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 3)
	world.interact(1)
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
	world.interact(1)
	player.inventory.add(&"bone", 5)
	player.position = player.run.exit
	world.interact(1)
	assert_int(player.inventory.count_of(&"bone")).is_equal(5)


func test_the_last_one_out_closes_the_run() -> void:
	var world := _world()
	world.interact(1)
	var run: Dungeon = world.players[1].run
	var drop := world.add_drop(&"bone", 1, run.exit + Vector2(0, 30))
	world.players[1].position = run.exit
	world.tick(TICK)  # the end room wakes
	assert_dict(world.enemies).is_not_empty()
	world.interact(1)
	assert_dict(world.dungeons).is_empty()
	assert_dict(world.enemies).is_empty()
	assert_bool(world.drops.has(drop.id)).is_false()


func test_drops_inside_a_run_stay_without_chunks() -> void:
	var world := _world()
	world.interact(1)
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
	world.interact(1)
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


func test_the_end_chest_opens_once_per_player_when_no_enemy_is_near() -> void:
	var world := _world()
	world.interact(1)
	var run: Dungeon = world.players[1].run
	var player: SimWorld.SimPlayer = world.players[1]
	player.position = run.chest
	world.tick(TICK)  # the end room wakes
	assert_dict(world.enemies).is_not_empty()
	assert_bool(world.interact(1)).is_false()  # locked
	world.enemies.clear()
	var before := world.drops.size()
	assert_bool(world.interact(1)).is_true()
	assert_array(world.events.back()).is_equal(["chest", 1])
	assert_int(world.drops.size()).is_greater(before)
	assert_bool(world.interact(1)).is_false()  # once
	world.add_player(2, "p2")
	world.players[2].position = Content.tuning.dungeon_entrance
	world.interact(2)
	world.players[2].position = run.chest
	assert_bool(world.interact(2)).is_true()  # everyone gets their own


func test_buff_orbs_get_rarer_deeper_in() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bonus := Content.tuning.buff_depth_bonus
	var rare := [0, 0]
	for i in 3000:
		for deep: int in [0, 1]:
			var buff: BuffDef = Content.buffs[Buffs.roll(rng, (deep * 7) * bonus)]
			if buff.rarity == ItemDef.Rarity.RARE:
				rare[deep] += 1
	assert_int(rare[1]).is_greater(rare[0])


func test_clearing_the_woken_rooms_heals_those_inside() -> void:
	var world := _world()
	world.interact(1)
	var player: SimWorld.SimPlayer = world.players[1]
	var run := player.run
	player.position = run.rooms[1].get_center()
	world.tick(TICK)
	player.health = 20.0
	world.tick(TICK)
	assert_float(player.health).is_less(21.0)  # enemies still up
	world.enemies.clear()
	world.tick(TICK)
	var healed := player.max_health() * Content.tuning.room_clear_heal
	assert_float(player.health).is_greater(20.0 + healed - 1.0)
	var after := player.health
	world.tick(TICK)
	assert_float(player.health).is_less(after + 1.0)  # once per room


func test_more_players_wake_more_enemies() -> void:
	var world := _world()
	world.add_player(2, "p2")
	world.add_player(3, "p3")
	for id in [1, 2, 3]:
		world.players[id].position = Content.tuning.dungeon_entrance
		world.interact(id)
	var run: Dungeon = world.players[1].run
	for id in [1, 2, 3]:
		world.players[id].position = run.rooms[1].get_center()
	world.tick(TICK)
	var scale := Combat.dungeon_scaled(1, run.minutes(world.time), 3)
	var expected := roundi(run.defs[1].spawns.size() * scale.count)
	assert_int(world.enemies.size()).is_equal(expected)
	assert_int(expected).is_greater(run.defs[1].spawns.size())
	for enemy: SimEnemy in world.enemies.values():
		assert_int(run.room_of(enemy.position)).is_equal(1)


func test_the_end_room_wakes_one_boss_at_the_chest() -> void:
	var world := _world()
	world.interact(1)
	var run: Dungeon = world.players[1].run
	world.players[1].position = run.rooms[run.rooms.size() - 2].get_center()
	world.tick(TICK)
	var bosses := func() -> Array:
		return world.enemies.values().filter(
			func(e: SimEnemy) -> bool: return e.def == Content.tuning.dungeon_boss
		)
	assert_array(bosses.call()).is_empty()
	world.players[1].position = run.chest + Vector2(0, 120)
	world.tick(TICK)
	assert_array(bosses.call()).has_size(1)
	var boss: SimEnemy = bosses.call()[0]
	assert_vector(boss.home).is_equal(run.chest)
	var scale := Combat.dungeon_scaled(run.reached, run.minutes(world.time))
	assert_float(boss.max_health).is_equal_approx(
		Content.tuning.dungeon_boss.health * scale.health, 0.01
	)
