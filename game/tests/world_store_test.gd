extends GdUnitTestSuite
## WorldStore: round trips, atomic overwrites and the format version guard.


func test_new_world_is_empty() -> void:
	var store := WorldStore.new(create_temp_dir("store_new_%d" % Time.get_ticks_usec()))
	assert_dict(store.load_meta()).is_empty()
	assert_array(Array(store.load_chunk(Vector2i.ZERO).removed)).is_empty()
	assert_dict(store.load_player("nobody")).is_empty()


func test_round_trip_and_overwrite() -> void:
	var path := create_temp_dir("store_round_trip_%d" % Time.get_ticks_usec())
	var store := WorldStore.new(path)
	store.save_meta({seed = 5, time = 1.5})
	store.save_chunk(Vector2i(-1, 2), PackedInt32Array([3, 4]))
	store.save_chunk(Vector2i(-1, 2), PackedInt32Array([3, 4, 9]), [{t = 7, id = "wall"}])
	store.save_player("ann", {x = 1.0, y = 2.0})
	var again := WorldStore.new(path)
	var meta: Dictionary = again.load_meta()
	assert_int(int(meta.seed)).is_equal(5)
	assert_float(meta.time).is_equal(1.5)
	var chunk := again.load_chunk(Vector2i(-1, 2))
	assert_array(Array(chunk.removed)).is_equal([3, 4, 9])
	assert_str(chunk.pieces[0].id).is_equal("wall")
	assert_float(again.load_player("ann").y).is_equal(2.0)
	assert_bool(FileAccess.file_exists(store.dir.path_join("chunks/-1_2.json.tmp"))).is_false()


func test_newer_format_is_refused() -> void:
	var store := WorldStore.new(create_temp_dir("store_newer"))
	store.save_meta({seed = 1})
	var file := FileAccess.open(store.dir.path_join("world.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({version = WorldStore.FORMAT_VERSION + 1, seed = 1}))
	file.close()
	assert_that(store.load_meta()).is_null()


func test_version_1_chunks_have_no_pieces() -> void:
	var store := WorldStore.new(create_temp_dir("store_v1_%d" % Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(store.dir.path_join("chunks"))
	var file := FileAccess.open(store.dir.path_join("chunks/0_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({version = 1, removed = [5]}))
	file.close()
	var chunk := store.load_chunk(Vector2i.ZERO)
	assert_array(Array(chunk.removed)).is_equal([5])
	assert_array(chunk.pieces).is_empty()
