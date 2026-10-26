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
