extends GdUnitTestSuite
## Building: placing, removing, repairing and saving pieces, doors and chests, and pieces
## blocking players and enemies.

const TICK := 0.1


func test_build_takes_the_cost_and_needs_reach() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var tile := _clear(world, Vector2i(2, 0))
	assert_bool(world.build(1, tile, &"wall")).is_false()
	player.inventory.add(&"wood", 10)
	var far := _clear(world, Vector2i(20, 0))
	assert_bool(world.build(1, far, &"wall")).is_false()
	assert_bool(world.build(1, tile, &"wall")).is_true()
	assert_str(world.pieces[tile].id).is_equal("wall")
	assert_int(player.inventory.count_of(&"wood")).is_equal(
		10 - Content.piece(&"wall").cost[&"wood"]
	)
	assert_bool(world.build(1, tile, &"floor")).is_false()
	assert_bool(world.build(1, tile, &"no_such_piece")).is_false()
	assert_array(world.events).contains([["piece", tile]])


func test_build_refuses_props_and_bodies_in_the_way() -> void:
	var world := _world()
	world.players[1].inventory.add(&"wood", 20)
	var coord := Vector2i.ZERO
	var chunk: SimWorld.SimChunk = world.chunks[coord]
	var prop_id: int = chunk.props.keys()[0]
	var prop_tile := Building.tile_at(coord, prop_id)
	world.players[1].position = Building.tile_center(prop_tile)
	assert_bool(world.build(1, prop_tile, &"floor")).is_false()
	chunk.removed[prop_id] = true
	# A wall can't go up on someone, a floor can.
	assert_bool(world.build(1, prop_tile, &"wall")).is_false()
	assert_bool(world.build(1, prop_tile, &"floor")).is_true()


func test_unbuild_refunds_and_spills_the_chest() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var tile := _clear(world, Vector2i(2, 0))
	player.inventory.add(&"wood", 8)
	player.inventory.add(&"stone", 2)
	assert_bool(world.build(1, tile, &"chest")).is_true()
	assert_int(player.inventory.count_of(&"wood")).is_equal(0)
	world.pieces[tile].items.add(&"bone", 3)
	assert_bool(world.unbuild(1, tile)).is_true()
	assert_bool(world.pieces.has(tile)).is_false()
	assert_int(player.inventory.count_of(&"wood")).is_equal(8)
	assert_int(player.inventory.count_of(&"stone")).is_equal(2)
	var bones := 0
	for drop: SimWorld.SimDrop in world.drops.values():
		bones += drop.count if drop.item == &"bone" else 0
	assert_int(bones).is_equal(3)
	assert_bool(world.unbuild(1, tile)).is_false()


func test_walls_block_moves_and_open_doors_dont() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 20)
	var wall := _clear(world, Vector2i(2, 0))
	var door := _clear(world, Vector2i(2, 1))
	world.build(1, wall, &"wall")
	world.build(1, door, &"door")
	world.tick(1.0)
	assert_bool(world.move_player(1, Building.tile_center(wall))).is_false()
	assert_bool(world.move_player(1, Building.tile_center(door))).is_false()
	assert_bool(world.use_piece(1, door)).is_true()
	assert_bool(world.move_player(1, Building.tile_center(door))).is_true()
	# Not shut on someone standing in it.
	assert_bool(world.use_piece(1, door)).is_false()


func test_enemies_break_walls_in_their_way() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 50)
	var walls: Array[Vector2i] = []
	for y in range(-2, 3):
		walls.append(_clear(world, Vector2i(2, y)))
		assert_bool(world.build(1, walls[-1], &"wall")).is_true()
	var enemy := world.add_enemy(Vector2(80, 8), 1000, 100)
	enemy.provoke(1)
	for i in 30:
		world.tick(TICK)
	assert_float(player.health).is_equal(player.max_health())
	assert_float(enemy.position.x).is_greater(40)
	var health := 0.0
	for tile in walls:
		health += world.pieces[tile].health
	assert_float(health).is_less(walls.size() * Content.piece(&"wall").health)
	for i in 300:
		world.tick(TICK)
	var standing := 0
	for tile in walls:
		standing += 1 if world.pieces.has(tile) else 0
	assert_int(standing).is_less(walls.size())
	assert_float(player.health).is_less(player.max_health())


func test_repair_waits_for_enemies_to_leave() -> void:
	var world := _world()
	world.players[1].inventory.add(&"wood", 10)
	var tile := _clear(world, Vector2i(2, 0))
	world.build(1, tile, &"wall")
	world.damage_piece(tile, 100)
	var enemy := world.add_enemy(Vector2(100, 0), 100, 0)
	assert_bool(world.build(1, tile, &"wall")).is_false()
	world.enemies.erase(enemy.id)
	assert_bool(world.build(1, tile, &"wall")).is_true()
	assert_float(world.pieces[tile].health).is_equal(Content.piece(&"wall").health)
	world.damage_piece(tile, 1000)
	assert_bool(world.pieces.has(tile)).is_false()


func test_chests_store_items() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 8)
	player.inventory.add(&"stone", 2)
	var tile := _clear(world, Vector2i(1, 1))
	world.build(1, tile, &"chest")
	player.inventory.add(&"bone", 5)
	assert_bool(world.chest_move(1, false, 0)).is_false()
	world.events.clear()
	assert_bool(world.use_piece(1, tile)).is_true()
	assert_array(world.events[0].slice(0, 2)).is_equal(["storage", 1])
	assert_bool(world.chest_move(1, false, 0)).is_true()
	assert_int(world.pieces[tile].items.count_of(&"bone")).is_equal(5)
	assert_int(player.inventory.count_of(&"bone")).is_equal(0)
	assert_bool(world.chest_move(1, true, 0)).is_true()
	assert_int(player.inventory.count_of(&"bone")).is_equal(5)
	# Walking off closes it.
	player.position = Vector2(500, 0)
	world.events.clear()
	world.tick(TICK)
	assert_that(player.open_chest).is_null()
	assert_array(world.events).contains([["storage", 1, {}]])


func test_crafting_needs_a_built_station() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var recipe: RecipeDef = Content.recipes[&"stone_axe"]
	for item: StringName in recipe.inputs:
		player.inventory.add(item, recipe.inputs[item])
	player.inventory.add(&"wood", 10)
	assert_bool(world.craft(1, &"stone_axe")).is_false()
	world.build(1, _clear(world, Vector2i(1, 0)), recipe.station)
	assert_bool(world.craft(1, &"stone_axe")).is_true()


func test_pieces_survive_a_restart() -> void:
	var path := create_temp_dir("building_restart_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	var player := world.add_player(1, "ann")
	player.position = Vector2.ZERO
	world.tick(TICK)
	player.inventory.add(&"wood", 30)
	player.inventory.add(&"stone", 2)
	var wall := _clear(world, Vector2i(2, 0))
	var door := _clear(world, Vector2i(2, 1))
	var chest := _clear(world, Vector2i(-2, 0))
	world.build(1, wall, &"wall")
	world.build(1, door, &"door")
	world.build(1, chest, &"chest")
	world.use_piece(1, door)
	world.damage_piece(wall, 50)
	world.pieces[chest].items.add(&"amber", 2)
	world.save()
	world.remove_player(1)

	var again := SimWorld.open(path)
	again.add_player(2, "ann")
	again.tick(TICK)
	assert_float(again.pieces[wall].health).is_equal(Content.piece(&"wall").health - 50)
	assert_bool(again.pieces[door].open).is_true()
	assert_int(again.pieces[chest].items.count_of(&"amber")).is_equal(2)
	assert_int(again.pieces.size()).is_equal(3)
	assert_int(again.chunk_pieces(Vector2i.ZERO).size()).is_equal(2)


## One player at the origin, chunks loaded, no spawning.
func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world


## The tile with any prop on it removed.
func _clear(world: SimWorld, tile: Vector2i) -> Vector2i:
	var chunk: SimWorld.SimChunk = world.chunks[Building.chunk_of_tile(tile)]
	chunk.removed[Building.index_in_chunk(tile)] = true
	return tile
