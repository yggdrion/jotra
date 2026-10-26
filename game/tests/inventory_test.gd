extends GdUnitTestSuite
## Inventory: stacking, taking, moving, equipment and the save/RPC form.


func test_add_fills_stacks_then_empty_slots() -> void:
	var inventory := Inventory.new(3)
	var stack := Content.item(&"wood").max_stack
	assert_int(inventory.add(&"wood", stack - 2)).is_equal(0)
	assert_int(inventory.add(&"wood", 5)).is_equal(0)
	assert_dict(inventory.slots[0]).is_equal({item = &"wood", count = stack})
	assert_dict(inventory.slots[1]).is_equal({item = &"wood", count = 3})
	assert_int(inventory.add(&"club", 1)).is_equal(0)
	assert_int(inventory.add(&"club", 1)).is_equal(1)  # full, gear doesn't stack
	assert_int(inventory.add(&"no_such_item", 1)).is_equal(1)
	assert_bool(inventory.changed).is_true()


func test_take_and_has_all() -> void:
	var inventory := Inventory.new(4)
	inventory.add(&"wood", 3)
	inventory.add(&"stone", 2)
	assert_bool(inventory.has_all({&"wood": 3, &"stone": 2})).is_true()
	assert_bool(inventory.has_all({&"wood": 4})).is_false()
	inventory.take({&"wood": 3, &"stone": 1})
	assert_int(inventory.count_of(&"wood")).is_equal(0)
	assert_int(inventory.count_of(&"stone")).is_equal(1)
	assert_dict(inventory.slots[0]).is_empty()


func test_move_merges_or_swaps() -> void:
	var inventory := Inventory.new(4)
	inventory.slots[0] = {item = &"wood", count = 3}
	inventory.slots[1] = {item = &"wood", count = 4}
	inventory.slots[2] = {item = &"stone", count = 1}
	assert_bool(inventory.move(0, 1)).is_true()
	assert_dict(inventory.slots[0]).is_empty()
	assert_dict(inventory.slots[1]).is_equal({item = &"wood", count = 7})
	assert_bool(inventory.move(1, 2)).is_true()
	assert_dict(inventory.slots[1]).is_equal({item = &"stone", count = 1})
	assert_dict(inventory.slots[2]).is_equal({item = &"wood", count = 7})
	assert_bool(inventory.move(0, 1)).is_false()  # nothing there
	assert_bool(inventory.move(1, 9)).is_false()


func test_equip_swaps_with_what_is_worn() -> void:
	var inventory := Inventory.new(2)
	inventory.add(&"club", 1)
	inventory.add(&"stone_axe", 1)
	assert_bool(inventory.equip(0)).is_true()
	assert_str(inventory.weapon()).is_equal("club")
	assert_dict(inventory.slots[0]).is_empty()
	assert_bool(inventory.equip(1)).is_true()
	assert_str(inventory.weapon()).is_equal("stone_axe")
	assert_dict(inventory.slots[1]).is_equal({item = &"club", count = 1})
	inventory.add(&"wood", 1)
	assert_bool(inventory.equip(0)).is_false()  # wood isn't wearable
	assert_bool(inventory.unequip(ItemDef.Slot.WEAPON)).is_false()  # no room
	inventory.take({&"wood": 1})
	assert_bool(inventory.unequip(ItemDef.Slot.WEAPON)).is_true()
	assert_str(inventory.weapon()).is_empty()


func test_unequip_into_a_chosen_slot() -> void:
	var inventory := Inventory.new(3)
	inventory.add(&"club", 1)
	inventory.equip(0)
	inventory.add(&"wood", 1)  # lands in slot 0
	assert_bool(inventory.unequip(ItemDef.Slot.WEAPON, 2)).is_true()
	assert_dict(inventory.slots[2]).is_equal({item = &"club", count = 1})
	inventory.equip(2)
	assert_bool(inventory.unequip(ItemDef.Slot.WEAPON, 0)).is_true()  # taken: first free
	assert_dict(inventory.slots[1]).is_equal({item = &"club", count = 1})


func test_copy_is_separate() -> void:
	var inventory := Inventory.new(2)
	inventory.add(&"wood", 3)
	var other := inventory.copy()
	other.take({&"wood": 3})
	assert_int(inventory.count_of(&"wood")).is_equal(3)
	assert_int(other.count_of(&"wood")).is_equal(0)


func test_worn_sums_armor_stats() -> void:
	var inventory := Inventory.new(1)
	inventory.add(&"bone_armor", 1)
	inventory.equip(0)
	assert_float(inventory.worn("armor")).is_equal(Content.item(&"bone_armor").armor)
	assert_float(inventory.worn("health")).is_equal(Content.item(&"bone_armor").health)


func test_data_round_trip_drops_unknown_items() -> void:
	var inventory := Inventory.new(3)
	inventory.add(&"wood", 7)
	inventory.add(&"bone_armor", 1)
	inventory.equip(1)
	var data := inventory.to_data()
	# Through JSON, as a save does.
	data = JSON.parse_string(JSON.stringify(data))
	data.slots[2] = ["removed_item", 1]
	var again := Inventory.new(3)
	again.load_data(data)
	assert_dict(again.slots[0]).is_equal({item = &"wood", count = 7})
	assert_dict(again.slots[2]).is_empty()
	assert_str(again.equipment[ItemDef.Slot.ARMOR]).is_equal("bone_armor")
	assert_str(again.weapon()).is_empty()
