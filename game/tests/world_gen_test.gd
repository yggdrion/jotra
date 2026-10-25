extends GdUnitTestSuite
## WorldGen: determinism and the chunk grid math.


func test_same_seed_gives_same_chunk() -> void:
	var a := WorldGen.chunk(42, Vector2i(3, -2))
	var b := WorldGen.chunk(42, Vector2i(3, -2))
	assert_array(Array(a.tiles)).is_equal(Array(b.tiles))
	assert_dict(a.props).is_equal(b.props)


func test_other_seed_gives_other_chunk() -> void:
	var a := WorldGen.chunk(1, Vector2i.ZERO)
	var b := WorldGen.chunk(2, Vector2i.ZERO)
	assert_bool(a.tiles == b.tiles and a.props == b.props).is_false()


func test_chunk_has_props() -> void:
	var props := 0
	for coord in WorldGen.around(Vector2i.ZERO, 2):
		props += WorldGen.chunk(7, coord).props.size()
	assert_int(props).is_greater(0)


func test_prop_position_lies_in_its_chunk() -> void:
	var coord := Vector2i(-1, 2)
	var last := WorldGen.CHUNK * WorldGen.CHUNK - 1
	assert_vector(WorldGen.chunk_of(WorldGen.prop_position(coord, 0))).is_equal(coord)
	assert_vector(WorldGen.chunk_of(WorldGen.prop_position(coord, last))).is_equal(coord)


func test_chunk_of_negative_positions() -> void:
	assert_vector(WorldGen.chunk_of(Vector2(-1, -1))).is_equal(Vector2i(-1, -1))
	assert_vector(WorldGen.chunk_of(Vector2(WorldGen.CHUNK_PX, 0))).is_equal(Vector2i(1, 0))


func test_around_and_near() -> void:
	var chunks := WorldGen.around(Vector2i(5, 5), 2)
	assert_int(chunks.size()).is_equal(25)
	for coord in chunks:
		assert_bool(WorldGen.near(coord, Vector2i(5, 5), 2)).is_true()
	assert_bool(WorldGen.near(Vector2i(8, 5), Vector2i(5, 5), 2)).is_false()
