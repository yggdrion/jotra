extends GdUnitTestSuite
## Death and base (M18): the grave an overworld death leaves, looted by its owner alone, saved
## with its chunk, and the bed a player respawns at.

const TICK := 0.1
const DEATH_SPOT := Vector2(150, 40)


func test_overworld_death_leaves_the_inventory_in_a_grave() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	_carry(player)
	_kill(world, 1, DEATH_SPOT)
	assert_int(player.inventory.count_of(&"wood")).is_equal(0)
	assert_int(player.inventory.count_of(&"berries")).is_equal(0)
	assert_str(player.inventory.weapon()).is_equal("club")
	assert_int(world.graves.size()).is_equal(1)
	var grave: SimWorld.SimGrave = world.graves.values()[0]
	assert_str(grave.owner).is_equal("ann")
	assert_vector(grave.position).is_equal(DEATH_SPOT)
	assert_int(grave.items.count_of(&"wood")).is_equal(20)
	assert_int(grave.items.count_of(&"berries")).is_equal(5)
	assert_array(player.graves).is_equal([DEATH_SPOT])
	var coord := WorldGen.chunk_of(DEATH_SPOT)
	assert_array(world.events).contains([["grave", coord, grave.id], ["graves", 1]])
	assert_array(world.chunk_graves(coord)).is_equal([[grave.id, 150.0, 40.0, "ann"]])


func test_dying_empty_handed_leaves_no_grave() -> void:
	var world := _world()
	_kill(world, 1, DEATH_SPOT)
	assert_dict(world.graves).is_empty()
	assert_array(world.players[1].graves).is_empty()


func test_dungeon_death_restores_the_snapshot_without_a_grave() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"wood", 3)
	player.position = Content.tuning.dungeon_entrance
	assert_bool(world.interact(1)).is_true()
	player.inventory.add(&"bone", 4)
	world.damage_player(1, 1e6)
	_respawn(world)
	assert_dict(world.graves).is_empty()
	assert_int(player.inventory.count_of(&"wood")).is_equal(3)
	assert_int(player.inventory.count_of(&"bone")).is_equal(0)


func test_only_the_owner_loots_and_takes_what_fits() -> void:
	var world := _world()
	world.add_player(2, "bob")
	_carry(world.players[1])
	_kill(world, 1, DEATH_SPOT)
	_respawn(world)
	var bob: SimWorld.SimPlayer = world.players[2]
	bob.position = DEATH_SPOT
	assert_bool(world.interact(2)).is_false()
	assert_int(bob.inventory.count_of(&"wood")).is_equal(0)
	var ann: SimWorld.SimPlayer = world.players[1]
	ann.position = DEATH_SPOT
	# Room for one stack: the wood comes out first, the berries stay in the grave.
	for i in ann.inventory.slots.size() - 1:
		ann.inventory.slots[i] = {item = &"stone", count = Content.item(&"stone").max_stack}
	assert_bool(world.interact(1)).is_true()
	assert_int(ann.inventory.count_of(&"wood")).is_equal(20)
	var grave: SimWorld.SimGrave = world.graves.values()[0]
	assert_int(grave.items.count_of(&"wood")).is_equal(0)
	assert_int(grave.items.count_of(&"berries")).is_equal(5)
	assert_array(ann.graves).has_size(1)
	# Full now: nothing moves, the player is told.
	world.events.clear()
	assert_bool(world.interact(1)).is_false()
	assert_array(world.events).contains([["full", 1]])
	# Room again: the rest comes out and the grave is gone.
	for i in ann.inventory.slots.size():
		ann.inventory.slots[i] = {}
	world.events.clear()
	assert_bool(world.interact(1)).is_true()
	assert_int(ann.inventory.count_of(&"berries")).is_equal(5)
	assert_dict(world.graves).is_empty()
	assert_array(ann.graves).is_empty()
	var coord := WorldGen.chunk_of(DEATH_SPOT)
	assert_array(world.events).contains([["grave", coord, grave.id], ["graves", 1]])
	assert_array(world.chunk_graves(coord)).is_empty()


func test_a_second_death_makes_a_second_grave() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	_carry(player)
	_kill(world, 1, DEATH_SPOT)
	_respawn(world)
	player.inventory.add(&"stone", 7)
	_kill(world, 1, Vector2(-120, 60))
	assert_int(world.graves.size()).is_equal(2)
	assert_array(player.graves).is_equal([DEATH_SPOT, Vector2(-120, 60)])
	var total := {}
	for grave: SimWorld.SimGrave in world.graves.values():
		for item: StringName in [&"wood", &"berries", &"stone"]:
			total[item] = total.get(item, 0) + grave.items.count_of(item)
	assert_dict(total).is_equal({&"wood": 20, &"berries": 5, &"stone": 7})


func test_a_grave_survives_its_chunk_unloading_and_a_restart() -> void:
	var path := create_temp_dir("grave_restart_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	world.spawn_enemies = false
	var player := world.add_player(1, "ann")
	world.tick(TICK)
	_carry(player)
	_kill(world, 1, DEATH_SPOT)
	_respawn(world)
	# Far away: the grave's chunk unloads and is written.
	var far := Vector2(WorldGen.CHUNK_PX * 10, 0)
	player.position = far
	world.tick(TICK)
	assert_bool(world.chunks.has(WorldGen.chunk_of(DEATH_SPOT))).is_false()
	assert_dict(world.graves).is_empty()
	world.remove_player(1)
	world.save()
	var again := SimWorld.open(path)
	again.spawn_enemies = false
	var back := again.add_player(1, "ann")
	assert_array(back.graves).is_equal([DEATH_SPOT])
	back.position = DEATH_SPOT
	again.tick(TICK)
	assert_int(again.graves.size()).is_equal(1)
	assert_bool(again.interact(1)).is_true()
	assert_int(back.inventory.count_of(&"wood")).is_equal(20)
	assert_int(back.inventory.count_of(&"berries")).is_equal(5)
	assert_dict(again.graves).is_empty()


func test_a_bed_sets_the_respawn_and_survives_a_restart() -> void:
	var path := create_temp_dir("bed_restart_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	world.spawn_enemies = false
	var player := world.add_player(1, "ann")
	world.tick(TICK)
	var tile := _build_bed(world, Vector2i(6, 2))
	assert_that(player.bed).is_null()
	player.position = Building.tile_center(tile) + Vector2(0, 10)
	world.events.clear()
	assert_bool(world.use_piece(1, tile)).is_true()
	assert_that(player.bed).is_equal(tile)
	assert_array(world.events).contains([["bed", 1]])
	_kill(world, 1, DEATH_SPOT)
	_respawn(world)
	assert_vector(player.position).is_equal(Building.tile_center(tile))
	world.remove_player(1)
	world.save()
	var again := SimWorld.open(path)
	assert_that(again.add_player(1, "ann").bed).is_equal(tile)


func test_a_destroyed_bed_falls_back_to_the_spawn() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var tile := _build_bed(world, Vector2i(6, 2))
	player.position = Building.tile_center(tile)
	world.use_piece(1, tile)
	world.damage_piece(tile, 1e6)
	assert_bool(world.pieces.has(tile)).is_false()
	_kill(world, 1, DEATH_SPOT)
	_respawn(world)
	assert_vector(player.position).is_equal(Content.tuning.respawn_at)
	assert_that(player.bed).is_null()


func test_the_bed_is_a_buildable_piece() -> void:
	var bed := Content.piece(&"bed")
	assert_object(bed).is_not_null()
	assert_bool(bed.bed).is_true()
	assert_object(bed.icon).is_not_null()
	assert_str(bed.category).is_not_empty()
	assert_dict(bed.cost).is_not_empty()


func test_version_2_chunks_have_no_graves() -> void:
	var store := WorldStore.new(create_temp_dir("store_v2_%d" % Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(store.dir.path_join("chunks"))
	var file := FileAccess.open(store.dir.path_join("chunks/0_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({version = 2, removed = [5], pieces = [{t = 3, id = "wall"}]}))
	file.close()
	var chunk := store.load_chunk(Vector2i.ZERO)
	assert_array(Array(chunk.removed)).is_equal([5])
	assert_array(chunk.pieces).has_size(1)
	assert_array(chunk.graves).is_empty()


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "ann").position = Vector2.ZERO
	world.tick(TICK)
	return world


## Wood and berries in the slots, a club worn.
func _carry(player: SimWorld.SimPlayer) -> void:
	player.inventory.add(&"wood", 20)
	player.inventory.add(&"berries", 5)
	player.inventory.add(&"club", 1)
	player.equip(player.inventory.slots.find({item = &"club", count = 1}))


func _kill(world: SimWorld, id: int, at: Vector2) -> void:
	world.players[id].position = at
	world.tick(TICK)
	world.events.clear()
	world.damage_player(id, 1e6)


func _respawn(world: SimWorld) -> void:
	for i in ceili(Content.tuning.respawn_delay / TICK) + 1:
		world.tick(TICK)


## Builds a bed for player 1 on a cleared tile.
func _build_bed(world: SimWorld, tile: Vector2i) -> Vector2i:
	var chunk: SimWorld.SimChunk = world.chunks[Building.chunk_of_tile(tile)]
	chunk.removed[Building.index_in_chunk(tile)] = true
	var player: SimWorld.SimPlayer = world.players[1]
	player.position = Building.tile_center(tile) + Vector2(0, 20)
	player.inventory.add(&"wood", 6)
	player.inventory.add(&"grave_cloth", 2)
	assert_bool(world.build(1, tile, &"bed")).is_true()
	return tile
