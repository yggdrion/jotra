extends GdUnitTestSuite
## SimWorld: joining, the movement sanity check, pausing and snapshots.


func test_players_spawn_apart() -> void:
	var world := SimWorld.new()
	var a := world.add_player(1)
	var b := world.add_player(2)
	assert_vector(a.position).is_not_equal(b.position)


func test_move_within_speed_is_accepted() -> void:
	var world := SimWorld.new()
	world.add_player(1)
	world.tick(1.0)
	assert_bool(world.move_player(1, Vector2(SimWorld.MAX_SPEED, 0))).is_true()
	assert_vector(world.players[1].position).is_equal(Vector2(SimWorld.MAX_SPEED, 0))


func test_teleport_is_dropped() -> void:
	var world := SimWorld.new()
	world.add_player(1)
	world.tick(1.0)
	var far := Vector2(SimWorld.MAX_SPEED * (1.0 + SimWorld.MOVE_SLACK) + 1, 0)
	assert_bool(world.move_player(1, far)).is_false()
	assert_vector(world.players[1].position).is_equal(Vector2.ZERO)


func test_move_of_unknown_player_is_dropped() -> void:
	assert_bool(SimWorld.new().move_player(7, Vector2.ZERO)).is_false()


func test_snapshot_lists_current_players() -> void:
	var world := SimWorld.new()
	world.add_player(1)
	world.add_player(2)
	world.remove_player(1)
	assert_dict(world.snapshot()).is_equal({2: world.players[2].position})


func test_time_stands_still_while_empty() -> void:
	var world := SimWorld.new()
	world.tick(1.0)
	assert_float(world.time).is_equal(0.0)
	world.add_player(1)
	world.tick(1.0)
	world.remove_player(1)
	world.tick(1.0)
	assert_float(world.time).is_equal(1.0)
