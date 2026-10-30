extends GdUnitTestSuite
## BuildMenu's hotbar and CraftMenu's search.


func test_hotbar_keeps_slots_and_drops_the_oldest() -> void:
	var bar: Array[StringName] = [&"a", &"b", &"c"]
	assert_array(BuildMenu.remember(bar, &"b", 3)).is_equal([&"a", &"b", &"c"])
	assert_array(BuildMenu.remember(bar, &"d", 3)).is_equal([&"d", &"a", &"b"])
	assert_array(BuildMenu.remember(bar, &"d", 4)).is_equal([&"d", &"a", &"b", &"c"])


func test_build_menu_describes_pieces_and_lists_all() -> void:
	assert_str(BuildMenu.describe(Content.piece(&"door"))).contains("Door").contains("opens")
	var menu: BuildMenu = auto_free(BuildMenu.new())
	add_child(menu)
	assert_int(menu.recent.size()).is_equal(mini(BuildMenu.HOTBAR, Content.piece_ids.size()))
	menu.choose(Content.piece_ids[-1])
	assert_str(menu.selected).is_equal(str(Content.piece_ids[-1]))
	assert_array(menu.recent).contains([Content.piece_ids[-1]])
	assert_str(menu.hotbar_piece(99)).is_equal("")
	var inventory := Inventory.new(Content.tuning.inventory_size)
	menu.refresh(inventory)
	assert_bool(menu._buttons[&"wall"].disabled).is_true()
	inventory.add(&"wood", Content.piece(&"wall").cost[&"wood"])
	menu.refresh(inventory)
	assert_bool(menu._buttons[&"wall"].disabled).is_false()


func test_server_build_rejection_turns_a_green_preview_red_with_its_reason() -> void:
	var tile := Vector2i(2, 0)
	var index := Building.index_in_chunk(tile)
	var chunk := ChunkView.new(1, Vector2i.ZERO, PackedInt32Array([index]))
	var mode: BuildMode = auto_free(BuildMode.new())
	add_child(mode)
	mode.select(Content.piece_ids.find(&"wall"))
	var inventory := Inventory.new(Content.tuning.inventory_size)
	inventory.add(&"wood", Content.piece(&"wall").cost[&"wood"])
	var chunks := {Vector2i.ZERO: chunk}
	var bodies: Array[Vector2] = []
	mode.update(Building.tile_center(tile), {}, chunks, inventory, Vector2.ZERO, bodies)
	assert_int(mode.status).is_equal(Building.Status.OK)
	mode.reject(tile, &"wall", Building.Status.CLIFF)
	mode.update(Building.tile_center(tile), {}, chunks, inventory, Vector2.ZERO, bodies)
	assert_int(mode.status).is_equal(Building.Status.CLIFF)
	assert_bool(mode._ghost.ghost == BuildMode.BAD).is_true()


func test_craft_menu_search_and_x5() -> void:
	var axe: RecipeDef = Content.recipes[&"stone_axe"]
	assert_bool(CraftMenu.matches(axe, "")).is_true()
	assert_bool(CraftMenu.matches(axe, " AXE ")).is_true()
	assert_bool(CraftMenu.matches(axe, "weapon")).is_true()
	assert_bool(CraftMenu.matches(axe, "berry")).is_false()
	var menu: CraftMenu = auto_free(CraftMenu.new())
	add_child(menu)
	var crafted := []
	menu.craft_requested.connect(func(id: StringName) -> void: crafted.append(id))
	menu._recipes[&"club"].many.pressed.emit()
	assert_array(crafted).is_equal([&"club", &"club", &"club", &"club", &"club"])
