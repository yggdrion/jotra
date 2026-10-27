extends GdUnitTestSuite
## SimWorld: joining, the movement sanity check, pausing, snapshots, chunks and saving.


func test_players_spawn_apart() -> void:
	var world := SimWorld.new()
	var a := world.add_player(1, "p1")
	var b := world.add_player(2, "p2")
	assert_vector(a.position).is_not_equal(b.position)


func test_move_within_speed_is_accepted() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.tick(1.0)
	assert_bool(world.move_player(1, Vector2(Content.tuning.walk_speed, 0))).is_true()
	assert_vector(world.players[1].position).is_equal(Vector2(Content.tuning.walk_speed, 0))


func test_teleport_is_dropped() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.tick(1.0)
	var far := Vector2(Content.tuning.walk_speed * (1.0 + SimWorld.MOVE_SLACK) + 1, 0)
	assert_bool(world.move_player(1, far)).is_false()
	assert_vector(world.players[1].position).is_equal(Vector2.ZERO)


func test_move_of_unknown_player_is_dropped() -> void:
	assert_bool(SimWorld.new().move_player(7, Vector2.ZERO)).is_false()


func test_snapshot_lists_only_nearby_players() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.add_player(2, "p2")
	world.add_player(3, "p3")
	world.remove_player(2)
	world.players[3].position = Vector2(WorldGen.CHUNK_PX * (SimWorld.VIEW_CHUNKS + 1), 0)
	var me: Vector2 = world.players[1].position
	assert_dict(world.snapshot_for(1).players).is_equal({1: Vector3(me.x, me.y, 1.0)})


func test_time_stands_still_while_empty() -> void:
	var world := SimWorld.new()
	world.tick(1.0)
	assert_float(world.time).is_equal(0.0)
	world.add_player(1, "p1")
	world.tick(1.0)
	world.remove_player(1)
	world.tick(1.0)
	assert_float(world.time).is_equal(1.0)


func test_chunks_around_players_load_and_unload() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.tick(0.1)
	var seen := (2 * SimWorld.VIEW_CHUNKS + 1) ** 2
	assert_int(world.chunks.size()).is_equal(seen)
	world.players[1].position = Vector2(WorldGen.CHUNK_PX * 10, 0)
	world.tick(0.1)
	assert_int(world.chunks.size()).is_equal(seen)
	assert_bool(world.chunks.has(Vector2i.ZERO)).is_false()


func test_remove_prop_needs_reach_and_happens_once() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.tick(0.1)
	var found := _some_prop(world)
	var coord: Vector2i = found[0]
	var id: int = found[1]
	assert_bool(world.remove_prop(1, coord, id)).is_false()
	world.players[1].position = WorldGen.prop_position(coord, id)
	assert_bool(world.remove_prop(1, coord, id)).is_true()
	assert_bool(world.remove_prop(1, coord, id)).is_false()
	assert_array(Array(world.removed_props(coord))).is_equal([id])


func test_world_survives_a_restart() -> void:
	var path := create_temp_dir("sim_restart_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	world.add_player(1, "ann")
	world.tick(0.1)
	var found := _some_prop(world)
	world.players[1].position = WorldGen.prop_position(found[0], found[1])
	world.remove_prop(1, found[0], found[1])
	world.save()
	world.remove_player(1)

	var again := SimWorld.open(path)
	assert_int(again.world_seed).is_equal(world.world_seed)
	assert_float(again.time).is_equal_approx(0.1, 0.001)
	var ann := again.add_player(5, "ann")
	assert_vector(ann.position).is_equal(WorldGen.prop_position(found[0], found[1]))
	again.tick(0.1)
	assert_array(Array(again.removed_props(found[0]))).is_equal([found[1]])
	assert_bool(again.remove_prop(5, found[0], found[1])).is_false()


## [coord, id] of a prop within a player's view, one that is not right at the spawn.
func _some_prop(world: SimWorld) -> Array:
	for coord: Vector2i in world.chunks:
		for id: int in world.chunks[coord].props:
			if (
				not WorldGen.is_node(world.chunks[coord].props[id])
				and WorldGen.prop_position(coord, id).length() > SimWorld.REACH * 4
			):
				return [coord, id]
	return []


## Ids of the sticks and pebbles in a chunk.
func _pickups(world: SimWorld, coord: Vector2i) -> Array:
	return world.chunks[coord].props.keys().filter(
		func(id: int) -> bool: return not WorldGen.is_node(world.chunks[coord].props[id])
	)


func test_gathering_takes_time() -> void:
	var world := SimWorld.new()
	world.add_player(1, "p1")
	world.tick(0.1)
	var coord: Vector2i = _some_prop(world)[0]
	var ids := _pickups(world, coord)
	var player: SimWorld.SimPlayer = world.players[1]
	player.position = WorldGen.prop_position(coord, ids[0])
	assert_bool(world.remove_prop(1, coord, ids[0])).is_true()
	player.position = WorldGen.prop_position(coord, ids[1])
	assert_bool(world.remove_prop(1, coord, ids[1])).is_false()
	world.tick(Content.tuning.gather_time)
	player.position = WorldGen.prop_position(coord, ids[1])
	assert_bool(world.remove_prop(1, coord, ids[1])).is_true()
