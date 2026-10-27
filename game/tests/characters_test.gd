extends GdUnitTestSuite
## Characters: the list kept on this machine, the starting kit a new player gets once, the look
## in snapshots, and the start menu's pages.


func test_character_list_creates_remembers_and_deletes() -> void:
	var path := create_temp_dir("chars_%d" % Time.get_ticks_usec()).path_join("c.json")
	assert_dict(CharacterList.last(path)).is_empty()
	assert_str(CharacterList.create("Ann's", 0, &"warrior", path)).is_not_empty()
	assert_str(CharacterList.create("ann", 3, &"nope", path)).is_not_empty()
	assert_str(CharacterList.create("ann", 3, &"warrior", path)).is_empty()
	assert_str(CharacterList.create("bo", 7, &"hunter", path)).is_empty()
	assert_str(CharacterList.create("ann", 1, &"hunter", path)).contains("exists")
	(
		assert_array(CharacterList.list(path).map(func(c: Dictionary) -> String: return c.name))
		. is_equal(["ann", "bo"])
	)
	assert_str(CharacterList.last(path).name).is_equal("bo")
	CharacterList.remember("ann", path)
	assert_dict(CharacterList.last(path)).is_equal({name = "ann", look = 3, kit = &"warrior"})
	CharacterList.delete("ann", path)
	assert_str(CharacterList.last(path).name).is_equal("bo")


func test_every_kit_holds_real_items_it_can_wear() -> void:
	assert_array(Content.kit_ids).is_not_empty()
	for id in Content.kit_ids:
		var kit: KitDef = Content.kits[id]
		assert_str(kit.display_name).is_not_empty()
		for item: StringName in kit.items:
			assert_object(Content.item(item)).is_not_null()
		for item in kit.wear:
			assert_bool(kit.items.has(item)).is_true()
			assert_int(Content.item(item).slot).is_not_equal(ItemDef.Slot.NONE)


func test_a_new_player_gets_its_kit_once_and_wears_it() -> void:
	var world := SimWorld.new()
	world.spawn_enemies = false
	var player := world.add_player(1, "ann")
	assert_bool(world.set_character(1, 5, &"hunter")).is_true()
	assert_str(player.inventory.weapon()).is_equal("bow")
	assert_int(player.inventory.count_of(&"arrow")).is_equal(30)
	assert_int(player.look).is_equal(5)
	assert_bool(world.set_character(1, 2, &"hunter")).is_false()
	assert_int(player.inventory.count_of(&"arrow")).is_equal(30)
	assert_int(player.look).is_equal(2)
	world.tick(0.1)
	var z: float = world.snapshot_for(1).players[1].z
	assert_int(Net.player_look(z)).is_equal(2)
	assert_float(Net.player_health(z)).is_equal_approx(1.0, 0.01)


func test_a_player_saved_in_the_world_gets_no_kit() -> void:
	var dir := create_temp_dir("kit_world_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(dir)
	world.spawn_enemies = false
	world.add_player(1, "ann")
	world.remove_player(1)
	var player := world.add_player(2, "ann")
	assert_bool(world.set_character(2, 0, &"warrior")).is_false()
	assert_str(player.inventory.weapon()).is_empty()


func test_looks_fit_the_protocol_and_survive_packing() -> void:
	assert_int(PlayerView.SHEETS.size() * PlayerView.TINTS.size()).is_equal(Net.LOOKS)
	for look in Net.LOOKS:
		for health: float in [0.0, 0.37, 1.0]:
			var packed := Net.pack_entities(
				{1: Vector3(0, 0, Net.player_z(look, health))}, Vector2.ZERO
			)
			var z: float = Net.unpack_entities(packed, Vector2.ZERO)[1].z
			assert_int(Net.player_look(z)).is_equal(look)
			assert_float(Net.player_health(z)).is_equal_approx(health, 0.02)


func test_start_menu_opens_on_create_without_a_character() -> void:
	var menu: StartMenu = auto_free(StartMenu.new())
	add_child(menu)
	var create: Control = menu._pages["create"]
	assert_bool(create.visible).is_equal(menu.character.is_empty())
	assert_bool(menu._pages["home"].visible).is_equal(not menu.character.is_empty())
