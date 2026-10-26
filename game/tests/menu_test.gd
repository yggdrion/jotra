extends GdUnitTestSuite
## The world list (create, list, delete), the settings' key clashes and the character screen.


func test_world_list_creates_lists_and_deletes() -> void:
	var root := create_temp_dir("worlds_%d" % Time.get_ticks_usec())
	assert_str(WorldList.create("Ann's", 1, root)).is_not_empty()
	assert_str(WorldList.create("../x", 1, root)).is_not_empty()
	assert_str(WorldList.create("b", 7, root)).is_empty()
	assert_str(WorldList.create("a 1", 3, root)).is_empty()
	assert_str(WorldList.create("b", 9, root)).contains("exists")
	var worlds := WorldList.list(root)
	assert_array(worlds.map(func(w: Dictionary) -> String: return w.name)).is_equal(["a 1", "b"])
	assert_int(worlds[1].seed).is_equal(7)
	# The server opens what the menu made.
	assert_int(SimWorld.open(root.path_join("b")).world_seed).is_equal(7)
	WorldList.delete("b", root)
	assert_int(WorldList.list(root).size()).is_equal(1)
	assert_bool(DirAccess.dir_exists_absolute(root.path_join("b"))).is_false()


func test_a_key_cannot_be_bound_twice() -> void:
	assert_str(Settings.clash(&"dash", KEY_E)).is_equal("interact")
	assert_str(Settings.clash(&"interact", KEY_E)).is_empty()
	assert_str(Settings.clash(&"dash", KEY_I)).is_equal("inventory")


func test_character_screen_lists_gear_and_buffs() -> void:
	var inventory := Inventory.new(Content.tuning.inventory_size)
	var buffs := Buffs.new()
	assert_str(CharacterUi.describe(inventory, buffs, "ann")).contains("ann").contains("none")
	buffs.add(Content.buff_ids[0])
	var text := CharacterUi.describe(inventory, buffs, "ann")
	assert_str(text).contains(Content.buffs[Content.buff_ids[0]].display_name)
