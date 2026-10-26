extends GdUnitTestSuite
## Content: the data in res://data/ loads and its cross references hold.


func test_everything_loads() -> void:
	assert_object(Content.tuning).is_not_null()
	assert_object(Content.tuning.enemy).is_not_null()
	assert_int(Content.items.size()).is_greater(0)
	assert_int(Content.recipes.size()).is_greater(0)
	assert_int(Content.item_ids.size()).is_equal(Content.items.size())


func test_items_are_complete() -> void:
	for id: StringName in Content.items:
		var item := Content.item(id)
		assert_str(item.display_name).override_failure_message(str(id)).is_not_empty()
		assert_int(item.max_stack).is_greater(0)
		if item.slot == ItemDef.Slot.WEAPON:
			assert_object(item.light).override_failure_message(str(id)).is_not_null()
			assert_object(item.heavy).override_failure_message(str(id)).is_not_null()


func test_recipes_and_drop_tables_name_real_items() -> void:
	var tables: Array = [Content.tuning.tree_drops, Content.tuning.rock_drops]
	for enemy: EnemyDef in Content.enemies.values():
		tables.append(enemy.drops)
	for table: Array in tables:
		for entry: Dictionary in table:
			(
				assert_object(Content.item(entry.item))
				. override_failure_message(entry.item)
				. is_not_null()
			)
	for id: StringName in Content.recipes:
		var recipe: RecipeDef = Content.recipes[id]
		assert_object(Content.item(recipe.result)).override_failure_message(str(id)).is_not_null()
		for item: StringName in recipe.inputs:
			assert_object(Content.item(item)).override_failure_message(str(id)).is_not_null()
		if recipe.station != &"":
			assert_bool(Content.tuning.stations.has(recipe.station)).is_true()


func test_bare_hands_without_a_weapon() -> void:
	assert_object(Content.attack(&"", false)).is_same(Content.tuning.fists_light)
	assert_object(Content.attack(&"wood", true)).is_same(Content.tuning.fists_heavy)
	assert_object(Content.attack(&"club", true)).is_same(Content.item(&"club").heavy)
