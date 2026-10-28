extends GdUnitTestSuite
## What blocks inside a dungeon run: gates that stay shut until the room before them is
## cleared, room obstacles, and what depends on them (spawns, routes, arrows).

const TICK := 0.1


## A world with p1 standing at the entrance, nothing spawning on its own.
func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1")
	world.players[1].position = Content.tuning.dungeon_entrance
	world.tick(TICK)
	return world


## A run laid out from the first seed whose middle room 1 has a single-tile pillar and spawn
## points, entered by p1 through the entrance.
func _enter_pillar_run(world: SimWorld) -> Dungeon:
	var run: Dungeon
	for seed_value in 500:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		run = Dungeon.new(0, world.time, rng)
		var pillars := run.defs[1].obstacles.filter(
			func(o: RoomObstacle) -> bool: return o.tiles.size == Vector2i.ONE
		)
		if not pillars.is_empty() and not run.defs[1].spawns.is_empty():
			break
	world.dungeons[run.slot] = run
	world.interact(1)
	assert_object(world.players[1].run).is_same(run)
	return run


## The x px of a gate's west edge and the y of its middle.
func _gate_line(run: Dungeon, k: int) -> Vector2:
	var gate := run.gates[k]
	return Vector2(gate.position.x * WorldGen.TILE, (gate.position.y + gate.size.y / 2.0) * 16.0)


## Whether p1 can step from one side of gate k into it: from the west or the east.
func _crosses_gate(world: SimWorld, run: Dungeon, k: int, eastward: bool) -> bool:
	var player: SimWorld.SimPlayer = world.players[1]
	var line := _gate_line(run, k)
	var west := line + Vector2(-7, 0)
	var east := line + Vector2(WorldGen.TILE + 7, 0)
	player.position = west if eastward else east
	player.moved_at = world.time
	return world.move_player(1, line + Vector2(WorldGen.TILE / 2.0, 0))


func test_a_shut_gate_stops_the_player_until_the_room_is_cleared() -> void:
	var world := _world()
	var run := _enter_pillar_run(world)
	var player: SimWorld.SimPlayer = world.players[1]
	player.health = 1000000.0
	assert_int(run.cleared).is_equal(0)
	assert_bool(run.solid.has(Vector2i(run.gates[0].position))).is_false()
	assert_bool(run.solid.has(Vector2i(run.gates[1].position))).is_true()
	player.position = run.rooms[1].get_center()
	world.tick(TICK)
	assert_dict(world.enemies).is_not_empty()
	world.tick(1.0)
	assert_bool(_crosses_gate(world, run, 1, true)).is_false()
	world.enemies.clear()
	world.tick(TICK)
	assert_int(run.cleared).is_equal(1)
	(
		assert_array(world.events.filter(func(e: Array) -> bool: return e[0] == "gates"))
		. is_equal([["gates", 1, 1]])
	)
	for tile in range(run.gates[1].size.y):
		assert_bool(run.solid.has(run.gates[1].position + Vector2i(0, tile))).is_false()
		assert_bool(run.blocked.has(run.gates[1].position + Vector2i(0, tile))).is_false()
	assert_bool(_crosses_gate(world, run, 1, true)).is_true()
	assert_bool(run.solid.has(Vector2i(run.gates[2].position))).is_true()


func test_the_way_back_stays_open() -> void:
	var world := _world()
	var run := _enter_pillar_run(world)
	var player: SimWorld.SimPlayer = world.players[1]
	player.health = 1000000.0
	player.position = run.rooms[1].get_center()
	world.tick(TICK)
	world.enemies.clear()
	world.tick(TICK)
	player.position = run.rooms[2].get_center()
	world.tick(TICK)
	assert_dict(world.enemies).is_not_empty()
	assert_int(run.cleared).is_equal(1)
	world.tick(1.0)
	assert_bool(_crosses_gate(world, run, 1, false)).is_true()
	assert_bool(_crosses_gate(world, run, 0, false)).is_true()
	# A latecomer arrives at the start and finds the first gate open, too.
	world.add_player(2, "p2")
	world.players[2].position = Content.tuning.dungeon_entrance
	world.interact(2)
	assert_object(world.players[2].run).is_same(run)
	var line := _gate_line(run, 0)
	world.players[2].position = line + Vector2(-7, 0)
	world.tick(1.0)
	assert_bool(world.move_player(2, line + Vector2(WorldGen.TILE / 2.0, 0))).is_true()


func test_obstacles_block_players_enemies_and_arrows() -> void:
	var world := _world()
	var run := _enter_pillar_run(world)
	var player: SimWorld.SimPlayer = world.players[1]
	var pillar := run.obstacles[run.obstacles.find_custom(
		func(r: Rect2i) -> bool:
			return r.size == Vector2i.ONE and run.room_of(Vector2(r.position * 16)) == 1
	)]
	var center := Building.tile_center(pillar.position)
	assert_bool(run.solid.has(pillar.position)).is_true()
	player.position = center + Vector2(-24, 0)
	world.tick(1.0)
	assert_bool(world.move_player(1, center)).is_false()
	assert_bool(world.move_player(1, center + Vector2(-16, 0))).is_true()
	assert_bool(world.move_player(1, center + Vector2(-12, 0))).is_false()
	# Knocked at the pillar, an enemy stops against it.
	var enemy := world.add_enemy(center + Vector2(-60, 0), 1000.0, 1.0)
	enemy.knock_vel = Vector2(900, 0)
	for i in 20:
		world.tick(0.05)
	assert_object(world.blocker(enemy.position)).is_null()
	assert_float(enemy.position.x).is_less(center.x)
	assert_float(enemy.position.x).is_greater(center.x - 60.0)
	# Arrows of both sides end at it; an enemy one finds no piece to hurt.
	world.enemies.clear()
	player.position = center + Vector2(-200, 0)
	for team: SimProjectile.Team in [SimProjectile.Team.PLAYERS, SimProjectile.Team.ENEMIES]:
		world.add_projectile(team, 99, center + Vector2(-30, 0), Vector2.RIGHT, 300.0, 10.0, 200.0)
		world.tick(0.2)
	assert_dict(world.projectiles).is_empty()


func test_extra_enemies_never_wake_inside_an_obstacle() -> void:
	var world := _world()
	var run := _enter_pillar_run(world)
	for id in range(2, 11):
		world.add_player(id, "p%d" % id)
		world.players[id].position = Content.tuning.dungeon_entrance
		world.interact(id)
	# A spot inside an obstacle moves to open ground.
	var inside := Building.tile_center(run.obstacles[0].position)
	assert_bool(run.blocked.has(Building.tile_of(run.open_spot(inside)))).is_false()
	for id in world.players:
		world.players[id].position = run.rooms[1].get_center()
	world.tick(TICK)
	assert_dict(world.enemies).is_not_empty()
	for enemy: SimEnemy in world.enemies.values():
		assert_bool(run.blocked.has(Building.tile_of(enemy.position))).is_false()


func test_enemies_path_around_obstacles() -> void:
	var world := _world()
	var run := _enter_pillar_run(world)
	var pillar := run.obstacles[run.obstacles.find_custom(
		func(r: Rect2i) -> bool:
			return r.size == Vector2i.ONE and run.room_of(Vector2(r.position * 16)) == 1
	)]
	var center := Building.tile_center(pillar.position)
	var from := center + Vector2(-48, 0)
	var to := center + Vector2(48, 0)
	var blocked := world.blocked_at(center)
	assert_bool(Pathing.clear(blocked, from, to)).is_false()
	var route := Pathing.find(blocked, from, to, SimEnemy.PATH_NODES)
	assert_bool(route.open).is_true()
	assert_array(route.points).is_not_empty()
	for point in route.points:
		assert_bool(run.blocked.has(Building.tile_of(point))).is_false()
