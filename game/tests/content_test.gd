extends GdUnitTestSuite
## Content: the data in res://data/ loads and its cross references hold.


func test_everything_loads() -> void:
	assert_object(Content.tuning).is_not_null()
	assert_object(Content.tuning.enemy).is_not_null()
	assert_object(Content.tuning.dungeon_boss).is_not_null()
	assert_str(Content.tuning.dungeon_boss.display_name).is_not_empty()
	assert_int(Content.items.size()).is_greater(0)
	assert_int(Content.recipes.size()).is_greater(0)
	assert_int(Content.item_ids.size()).is_equal(Content.items.size())


func test_items_are_complete() -> void:
	for id: StringName in Content.items:
		var item := Content.item(id)
		assert_str(item.display_name).override_failure_message(str(id)).is_not_empty()
		assert_int(item.max_stack).is_greater(0)
		if item.slot == ItemDef.Slot.WEAPON and item.ammo == &"":
			assert_object(item.light).override_failure_message(str(id)).is_not_null()
			assert_object(item.heavy).override_failure_message(str(id)).is_not_null()
		if item.ammo != &"":
			var message := str(id)
			assert_int(item.slot).override_failure_message(message).is_equal(ItemDef.Slot.WEAPON)
			assert_object(Content.item(item.ammo)).override_failure_message(message).is_not_null()
			assert_float(item.draw_time).override_failure_message(message).is_greater(0.0)
			assert_float(item.min_draw).override_failure_message(message).is_between(0.0, 1.0)
			assert_float(item.arrow_damage).override_failure_message(message).is_greater(0.0)
			assert_float(item.arrow_speed).override_failure_message(message).is_greater(0.0)
			assert_float(item.arrow_range).override_failure_message(message).is_greater(0.0)
		# ponytail: the interim pack has no armor sprites, so armor keeps its color square.
		if item.slot != ItemDef.Slot.ARMOR:
			assert_object(item.icon).override_failure_message(str(id)).is_not_null()


func test_recipes_and_drop_tables_name_real_items() -> void:
	var t := Content.tuning
	var tables: Array = [t.tree_drops, t.rock_drops, t.stick_drops, t.pebble_drops, t.chest_drops]
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
			var station := Content.piece(recipe.station)
			(
				assert_bool(station != null and station.station)
				. override_failure_message(str(id))
				. is_true()
			)


func test_pieces_are_complete() -> void:
	assert_int(Content.piece_ids.size()).is_equal(Content.pieces.size())
	for id: StringName in Content.pieces:
		var piece := Content.piece(id)
		assert_str(piece.display_name).override_failure_message(str(id)).is_not_empty()
		assert_float(piece.health).override_failure_message(str(id)).is_greater(0)
		assert_object(piece.icon).override_failure_message(str(id)).is_not_null()
		if piece.door:
			assert_object(piece.open_icon).override_failure_message(str(id)).is_not_null()
		assert_bool(piece.cost.is_empty()).override_failure_message(str(id)).is_false()
		for item: StringName in piece.cost:
			assert_object(Content.item(item)).override_failure_message(str(id)).is_not_null()
		# Nothing stands between a new player and a workbench but wood.
		if piece.station:
			assert_array(piece.cost.keys()).is_equal([&"wood"])


func test_bare_hands_without_a_weapon() -> void:
	assert_object(Content.attack(&"", false)).is_same(Content.tuning.fists_light)
	assert_object(Content.attack(&"wood", true)).is_same(Content.tuning.fists_heavy)
	assert_object(Content.attack(&"club", true)).is_same(Content.item(&"club").heavy)
	assert_object(Content.attack(&"bow", false)).is_same(Content.tuning.fists_light)


func test_rooms_fit_the_layout() -> void:
	var kinds := {}
	for id: StringName in Content.rooms:
		var room: RoomDef = Content.rooms[id]
		kinds[room.kind] = true
		var message := str(id)
		assert_float(room.size.y).override_failure_message(message).is_greater_equal(
			Content.tuning.corridor_width
		)
		for at in room.spawns:
			(
				assert_bool(Rect2(Vector2.ZERO, room.size).has_point(at))
				. override_failure_message(message)
				. is_true()
			)
	assert_dict(kinds).contains_keys([RoomDef.Kind.START, RoomDef.Kind.MIDDLE, RoomDef.Kind.END])


func test_buffs_and_synergies_name_real_stats_and_buffs() -> void:
	assert_int(Content.buffs.size()).is_greater_equal(15)
	assert_int(Content.buff_ids.size()).is_equal(Content.buffs.size())
	for id: StringName in Content.buffs:
		var buff: BuffDef = Content.buffs[id]
		assert_str(buff.display_name).override_failure_message(str(id)).is_not_empty()
		assert_bool(buff.stat in Buffs.STATS).override_failure_message(str(id)).is_true()
		assert_int(buff.max_stacks).is_greater(0)
		assert_int(buff.rarity).is_less(Content.tuning.buff_rarity_weights.size())
	for id: StringName in Content.synergies:
		var synergy: SynergyDef = Content.synergies[id]
		assert_bool(synergy.stat in Buffs.STATS).override_failure_message(str(id)).is_true()
		assert_int(synergy.buffs.size()).is_equal(2)
		for buff in synergy.buffs:
			assert_bool(Content.buffs.has(buff)).override_failure_message(str(id)).is_true()


func test_enemies_have_a_sheet_and_what_their_behavior_needs() -> void:
	for id: StringName in Content.enemies:
		var enemy: EnemyDef = Content.enemies[id]
		var message := str(id)
		assert_object(enemy.sheet).override_failure_message(message).is_not_null()
		match enemy.behavior:
			EnemyDef.Behavior.ARCHER:
				assert_float(enemy.preferred_distance).is_greater(0.0)
				assert_float(enemy.preferred_distance).is_less(enemy.attack_range)
				assert_float(enemy.arrow_range).is_greater(0.0)
				assert_float(enemy.arrow_speed).is_greater(0.0)
			EnemyDef.Behavior.PACK:
				assert_int(enemy.pack_min).is_greater(1)
				assert_int(enemy.pack_max).is_greater_equal(enemy.pack_min)
				assert_float(enemy.lunge_distance).is_greater(0.0)
			EnemyDef.Behavior.SHIELD:
				assert_float(enemy.block_arc).is_greater(0.0)
			EnemyDef.Behavior.EXPLODER:
				assert_float(enemy.slam_radius).is_greater(0.0)


func test_wolves_drop_meat_and_hide_and_hide_is_used() -> void:
	var drops: Array = Content.enemies[&"wolf"].drops.map(
		func(d: Dictionary) -> StringName: return d.item
	)
	assert_array(drops).contains([&"meat", &"hide"])
	var uses := Content.recipes.values().filter(
		func(r: RecipeDef) -> bool: return r.inputs.has(&"hide")
	)
	assert_int(uses.size()).is_greater(0)
	assert_int(Content.item(uses[0].result).slot).is_equal(ItemDef.Slot.ARMOR)


func test_every_spawnable_enemy_has_a_weight_and_the_day_has_no_ranged_or_exploders() -> void:
	var day := 0.0
	var night := 0.0
	for enemy: EnemyDef in Content.enemies.values():
		day += enemy.spawn_weight_day
		night += enemy.spawn_weight_night
		if enemy.behavior in [EnemyDef.Behavior.ARCHER, EnemyDef.Behavior.EXPLODER]:
			assert_float(enemy.spawn_weight_day).is_equal(0.0)
			assert_float(enemy.spawn_weight_night).is_greater(0.0)
	assert_float(day).is_greater(0.0)
	assert_float(night).is_greater(0.0)
