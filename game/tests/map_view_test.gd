extends GdUnitTestSuite
## MapView: explored chunks are kept per world seed and come back on the next load. In the
## tree, so its map controls are freed with it.

const DIR := "user://test_maps"


func after_test() -> void:
	DirAccess.remove_absolute(DIR + "/7.json")
	DirAccess.remove_absolute(DIR)


func test_explored_chunks_survive_a_reload() -> void:
	var map: MapView = auto_free(MapView.new())
	map.dir = DIR
	add_child(map)
	map.load_world(7)
	map.explore(Vector2i(0, 0))
	map.explore(Vector2i(-1, 2))
	map.explore(Vector2i(0, 0))
	assert_int(map.explored().size()).is_equal(2)
	var again: MapView = auto_free(MapView.new())
	again.dir = DIR
	add_child(again)
	again.load_world(7)
	assert_array(again.explored()).contains_exactly_in_any_order([Vector2i(0, 0), Vector2i(-1, 2)])
	again.load_world(8)
	assert_array(again.explored()).is_empty()
