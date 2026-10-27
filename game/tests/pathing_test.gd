extends GdUnitTestSuite
## Enemy pathing: around walls, through open doors, sieging only when walled off, and the
## search budget.

const TICK := 0.1


func test_route_goes_around_a_wall() -> void:
	var pieces := {}
	for y in range(-3, 4):
		pieces[Vector2i(2, y)] = Building.Piece.new(&"wall")
	var from := Building.tile_center(Vector2i(5, 0))
	var to := Building.tile_center(Vector2i(0, 0))
	assert_bool(Pathing.clear(Pathing.blocked_tiles(pieces), from, to)).is_false()
	var blocked := Pathing.blocked_tiles(pieces)
	var route := Pathing.find(blocked, from, to, 400)
	assert_bool(route.open).is_true()
	assert_array(route.points).is_not_empty()
	var at := from
	for point in route.points:
		# Tile to tile is always walkable; a pulled-straight first leg must be clear.
		assert_bool(Pathing.clear(blocked, at, point) or at.distance_to(point) < 24).is_true()
		assert_object(Building.blocker(pieces, point)).is_null()
		at = point
	assert_bool(Building.tile_of(route.points[-1]) == Vector2i(0, 0)).is_true()


func test_a_route_from_inside_a_blocked_tile_leaves_from_where_it_stands() -> void:
	# A dungeon room's top edge just below a tile center: the tile is a wall, the body inside.
	var blocked := {}
	for x in range(-1, 6):
		blocked[Vector2i(x, -1)] = true
		blocked[Vector2i(x, 0)] = true
	blocked.erase(Vector2i(3, 0))
	var from := Vector2(8, 15.5)
	var route := Pathing.find(blocked, from, Building.tile_center(Vector2i(3, 3)), 400)
	assert_array(route.points).is_not_empty()
	assert_bool(Building.tile_center(Vector2i(0, 0)) in route.points).is_false()


func test_route_is_straight_without_pieces_in_the_way() -> void:
	var pieces := {Vector2i(9, 9): Building.Piece.new(&"wall")}
	var route := Pathing.find(Pathing.blocked_tiles(pieces), Vector2(8, 8), Vector2(80, 8), 400)
	assert_bool(route.open).is_true()
	assert_array(route.points).is_empty()
	assert_int(route.used).is_equal(0)


func test_search_stays_within_its_budget() -> void:
	var pieces := _ring(Vector2i.ZERO, 2, false)
	var to := Building.tile_center(Vector2i.ZERO)
	var route := Pathing.find(Pathing.blocked_tiles(pieces), Vector2(200, 8), to, 50)
	assert_int(route.used).is_less_equal(50)
	assert_bool(route.open).is_false()


func test_enemy_walks_around_a_wall() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var walls: Array[Vector2i] = []
	for y in range(-3, 4):
		walls.append(Vector2i(2, y))
	_place(world, walls, &"wall")
	var enemy := world.add_enemy(Vector2(88, 8), 1000, 5)
	enemy.provoke(1)
	for i in 60:
		world.tick(TICK)
	assert_float(player.health).is_less(player.max_health())
	assert_float(_health(world, walls)).is_equal(walls.size() * Content.piece(&"wall").health)


func test_enemy_comes_in_through_an_open_door() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var pieces := _ring(Vector2i.ZERO, 2, true)
	_place_all(world, pieces)
	var enemy := world.add_enemy(Vector2(120, 8), 1000, 5)
	enemy.provoke(1)
	for i in 80:
		world.tick(TICK)
	assert_float(player.health).is_less(player.max_health())
	for tile: Vector2i in pieces:
		assert_float(world.pieces[tile].health).is_equal(world.pieces[tile].def().health)


func test_walled_in_gets_sieged() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var pieces := _ring(Vector2i.ZERO, 2, false)
	_place_all(world, pieces)
	var enemy := world.add_enemy(Vector2(120, 8), 1000, 100)
	enemy.provoke(1)
	for i in 30:
		world.tick(TICK)
	assert_float(player.health).is_equal(player.max_health())
	var health := 0.0
	var full := 0.0
	for tile: Vector2i in pieces:
		full += pieces[tile].def().health
		health += world.pieces[tile].health if world.pieces.has(tile) else 0.0
	assert_float(health).is_less(full)
	# Through the broken wall it gets at the player (a killing hit respawns it at full health).
	var lowest := player.health
	for i in 300:
		world.tick(TICK)
		lowest = minf(lowest, player.health)
	assert_float(lowest).is_less(player.max_health())


func test_path_searches_share_a_tick_budget() -> void:
	var world := _world()
	_place_all(world, _ring(Vector2i.ZERO, 2, false))
	var enemies: Array[SimEnemy] = []
	for i in 40:
		var enemy := world.add_enemy(Vector2(100 + i * 4, 120), 1000, 1)
		enemy.provoke(1)
		enemies.append(enemy)
	world.tick(TICK)
	assert_int(world.path_budget).is_greater_equal(0)
	var searched := 0
	for enemy in enemies:
		searched += 1 if enemy._path_version == world.pieces_version else 0
	assert_int(searched).is_less(enemies.size())
	for i in 20:
		world.tick(TICK)
	for enemy in enemies:
		assert_int(enemy._path_version).is_equal(world.pieces_version)


func test_no_pieces_no_search() -> void:
	var world := _world()
	var enemy := world.add_enemy(Vector2(88, 8), 1000, 5)
	enemy.provoke(1)
	world.tick(TICK)
	assert_array(enemy._path).is_empty()
	assert_int(world.path_budget).is_equal(SimWorld.PATH_BUDGET)


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Building.tile_center(Vector2i.ZERO)
	world.tick(TICK)
	return world


## The tiles around center at radius, walls with a door east of it (open or shut).
func _ring(center: Vector2i, radius: int, door_open: bool) -> Dictionary:
	var pieces := {}
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if maxi(absi(x), absi(y)) != radius:
				continue
			var tile := center + Vector2i(x, y)
			if Vector2i(x, y) == Vector2i(radius, 0):
				pieces[tile] = Building.Piece.new(&"door")
				pieces[tile].open = door_open
			else:
				pieces[tile] = Building.Piece.new(&"wall")
	return pieces


func _place(world: SimWorld, tiles: Array[Vector2i], id: StringName) -> void:
	var pieces := {}
	for tile in tiles:
		pieces[tile] = Building.Piece.new(id)
	_place_all(world, pieces)


func _place_all(world: SimWorld, pieces: Dictionary) -> void:
	for tile: Vector2i in pieces:
		world.chunks[Building.chunk_of_tile(tile)].pieces[tile] = pieces[tile]
		world.pieces[tile] = pieces[tile]
	world.pieces_version += 1


func _health(world: SimWorld, tiles: Array[Vector2i]) -> float:
	var total := 0.0
	for tile in tiles:
		total += world.pieces[tile].health
	return total
