extends GdUnitTestSuite
## Loot in SimWorld: drop tables, drops from enemies and props, pickup, equipment stats,
## crafting and saving the inventory.

const TICK := 0.1


func test_roll_respects_chance_and_counts() -> void:
	var rng := RandomNumberGenerator.new()
	var table := [
		{item = &"wood", chance = 1.0, min = 2, max = 2},
		{item = &"amber", chance = 0.0},
	]
	for i in 20:
		assert_array(Loot.roll(table, rng)).is_equal([[&"wood", 2]])


func test_killed_enemy_drops_and_walking_over_picks_up() -> void:
	var world := _world()
	var kind := EnemyDef.new()
	kind.drops = [{item = &"bone", chance = 1.0, min = 3, max = 3}]
	var enemy := world.add_enemy(Vector2(20, 0), 1, 0, kind)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_int(world.drops.size()).is_equal(1)
	var drop: SimWorld.SimDrop = world.drops.values()[0]
	var seen: Vector3 = world.snapshot_for(1).drops[drop.id]
	assert_int(int(seen.z)).is_equal(Content.item_index(&"bone"))
	world.players[1].position = drop.position
	world.events.clear()
	world.tick(TICK)
	assert_dict(world.drops).is_empty()
	assert_int(world.players[1].inventory.count_of(&"bone")).is_equal(3)
	assert_array(world.events).contains([["loot", 1, &"bone", 3]])


func test_removed_tree_drops_wood() -> void:
	var world := _world()
	for coord: Vector2i in world.chunks:
		for id: int in world.chunks[coord].props:
			if world.chunks[coord].props[id] == WorldGen.Prop.TREE:
				world.players[1].position = WorldGen.prop_position(coord, id)
				assert_bool(world.remove_prop(1, coord, id)).is_true()
				var drop: SimWorld.SimDrop = world.drops.values()[0]
				assert_str(drop.item).is_equal("wood")
				return
	fail("no tree")


func test_full_inventory_leaves_the_rest_lying() -> void:
	var world := _world()
	var inventory: Inventory = world.players[1].inventory
	for i in inventory.slots.size():
		inventory.slots[i] = {item = &"club", count = 1}
	world.add_drop(&"bone", 2, Vector2.ZERO)
	world.tick(TICK)
	assert_int(world.drops.size()).is_equal(1)
	inventory.slots[0] = {item = &"bone", count = Content.item(&"bone").max_stack - 1}
	world.tick(TICK)
	assert_int(world.drops.values()[0].count).is_equal(1)


func test_drops_vanish_after_their_lifetime() -> void:
	var world := _world()
	world.add_drop(&"bone", 1, Vector2(200, 0))
	world.tick(Content.tuning.drop_lifetime)
	assert_dict(world.drops).is_empty()


func test_equipped_weapon_sets_the_damage() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"club", 1)
	assert_bool(player.equip(0)).is_true()
	var enemy := world.add_enemy(Vector2(20, 0), 100, 0)
	world.attack(1, true, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_float(enemy.health).is_equal(100 - Content.item(&"club").heavy.damage)
	assert_str(world.events[0][5]).is_equal("club")


func test_armor_takes_off_damage_and_adds_health() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var armor := Content.item(&"bone_armor")
	player.inventory.add(&"bone_armor", 1)
	player.equip(0)
	assert_float(player.max_health()).is_equal(Content.tuning.max_health + armor.health)
	world.damage_player(1, 20)
	assert_float(player.health).is_equal(Content.tuning.max_health - (20 - armor.armor))
	world.damage_player(1, 1)
	assert_float(player.health).is_equal(
		Content.tuning.max_health - (20 - armor.armor) - Content.tuning.min_damage
	)
	player.health = player.max_health()
	assert_bool(player.unequip(ItemDef.Slot.ARMOR)).is_true()
	assert_float(player.health).is_equal(Content.tuning.max_health)


func test_craft_by_hand_uses_the_inputs() -> void:
	var player := _world().players[1] as SimWorld.SimPlayer
	var recipe: RecipeDef = Content.recipes[&"club"]
	assert_bool(Crafting.craft(player, &"club")).is_false()
	player.inventory.add(&"wood", recipe.inputs[&"wood"] + 1)
	assert_bool(Crafting.craft(player, &"club")).is_true()
	assert_int(player.inventory.count_of(&"club")).is_equal(1)
	assert_int(player.inventory.count_of(&"wood")).is_equal(1)
	assert_bool(Crafting.craft(player, &"no_such_recipe")).is_false()


func test_station_recipes_need_the_station() -> void:
	var player := _world().players[1] as SimWorld.SimPlayer
	var recipe: RecipeDef = Content.recipes[&"stone_axe"]
	for item: StringName in recipe.inputs:
		player.inventory.add(item, recipe.inputs[item])
	player.position = Content.tuning.stations[recipe.station] + Vector2(500, 0)
	assert_bool(Crafting.craft(player, &"stone_axe")).is_false()
	player.position = Content.tuning.stations[recipe.station]
	assert_bool(Crafting.craft(player, &"stone_axe")).is_true()
	assert_int(player.inventory.count_of(&"stone_axe")).is_equal(1)


func test_craft_without_room_changes_nothing() -> void:
	var player := _world().players[1] as SimWorld.SimPlayer
	var inventory := player.inventory
	inventory.slots[0] = {item = &"wood", count = Content.recipes[&"club"].inputs[&"wood"] + 1}
	for i in range(1, inventory.slots.size()):
		inventory.slots[i] = {item = &"stone_axe", count = 1}
	assert_bool(Crafting.craft(player, &"club")).is_false()
	assert_int(inventory.count_of(&"wood")).is_equal(Content.recipes[&"club"].inputs[&"wood"] + 1)


func test_inventory_survives_a_restart() -> void:
	var path := create_temp_dir("loot_restart_%d" % Time.get_ticks_usec())
	var world := SimWorld.open(path)
	var player := world.add_player(1, "ann")
	player.inventory.add(&"wood", 5)
	player.inventory.add(&"bone_armor", 1)
	player.equip(1)
	world.remove_player(1)

	var again := SimWorld.open(path).add_player(2, "ann")
	assert_int(again.inventory.count_of(&"wood")).is_equal(5)
	assert_str(again.inventory.equipment[ItemDef.Slot.ARMOR]).is_equal("bone_armor")
	assert_float(again.max_health()).is_greater(Content.tuning.max_health)


## One player at the origin, chunks loaded, no spawning.
func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world
