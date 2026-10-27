extends GdUnitTestSuite
## Map markers: placed and removed by anyone in the world, capped per player, saved with the
## world meta, and found under the mouse on the big map.


func test_markers_are_shared_capped_and_removed_by_anyone() -> void:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "ann")
	world.add_player(2, "bo")
	world.set_character(1, 4, &"")
	var id := world.add_marker(1, Vector2(10, 20))
	assert_int(id).is_not_equal(0)
	assert_array(world.events).contains([["markers"]])
	assert_array(world.marker_list()).is_equal([[id, 10.0, 20.0, "ann", 4]])
	for i in SimWorld.MARKERS_EACH - 1:
		assert_int(world.add_marker(1, Vector2(i, 0))).is_not_equal(0)
	assert_int(world.add_marker(1, Vector2(99, 0))).is_equal(0)
	assert_int(world.add_marker(2, Vector2(99, 0))).is_not_equal(0)
	assert_bool(world.remove_marker(2, id)).is_true()
	assert_bool(world.remove_marker(2, id)).is_false()
	assert_int(world.add_marker(1, Vector2(99, 0))).is_not_equal(0)
	assert_int(world.add_marker(3, Vector2.ZERO)).is_equal(0)


func test_markers_survive_a_restart() -> void:
	var dir := create_temp_dir("markers_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(dir)
	world.add_player(1, "ann")
	world.add_marker(1, Vector2(-5, 7))
	world.save()
	var again := SimWorld.open(dir)
	assert_int(again.markers.size()).is_equal(1)
	var marker: Array = again.marker_list()[0]
	assert_array(marker.slice(1)).is_equal([-5.0, 7.0, "ann", 0])
	again.add_player(1, "ann")
	assert_int(again.add_marker(1, Vector2.ZERO)).is_not_equal(marker[0])


func test_the_big_map_finds_world_positions_and_markers() -> void:
	var map: MapView = auto_free(MapView.new())
	add_child(map)
	map.me = Vector2(100, 100)
	map.markers = [[7, 100.0, 100.0, "ann", 0], [8, 400.0, 100.0, "bo", 1]]
	var center: Vector2 = map._big.size / 2
	assert_vector(map.world_at(center)).is_equal(Vector2(100, 100))
	assert_vector(map.world_at(center + Vector2(10, 0))).is_equal(
		Vector2(100 + 10 * MapView.BIG_SCALE, 100)
	)
	assert_int(map.marker_near(Vector2(102, 101))).is_equal(7)
	assert_int(map.marker_near(Vector2(250, 100))).is_equal(0)
