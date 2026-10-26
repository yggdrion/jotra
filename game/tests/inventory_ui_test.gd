extends GdUnitTestSuite
## InventoryUi's texts and drop rules: what the info panel says about items, and which drags
## turn into which requests.


func test_describe_says_where_from_and_what_for() -> void:
	assert_array(Array(InventoryUi.sources(&"wood"))).contains(["trees"])
	assert_array(Array(InventoryUi.sources(&"bone"))).contains(["draugr"])
	assert_array(Array(InventoryUi.sources(&"club"))).is_equal(["crafting"])
	assert_array(Array(InventoryUi.used_in(&"wood"))).contains(["Club"])
	var text := InventoryUi.describe(&"bone_armor")
	assert_str(text).contains("armor").contains("Blocks").contains("From: barrow king, crafting")
	text = InventoryUi.describe(&"berries")
	assert_str(text).contains("food").contains("Restores").contains("From: trees")


func test_drags_become_requests() -> void:
	var ui: InventoryUi = auto_free(InventoryUi.new())
	add_child(ui)
	var inventory := Inventory.new(Content.tuning.inventory_size)
	inventory.add(&"wood", 2)
	inventory.add(&"club", 1)
	inventory.add(&"stone_axe", 1)
	inventory.equip(2)  # wear the axe
	ui.show_inventory(inventory.to_data())
	var requests := []
	ui.move_requested.connect(func(a: int, b: int) -> void: requests.append(["move", a, b]))
	ui.equip_requested.connect(func(i: int) -> void: requests.append(["equip", i]))
	ui.unequip_requested.connect(func(k: int, to: int) -> void: requests.append(["off", k, to]))
	var slot := func(index: int) -> InventoryUi.SlotView:
		var view := InventoryUi.SlotView.new()
		view.index = index
		view.show_item(inventory.slots[index].get("item", &"") if index >= 0 else &"", 1)
		return auto_free(view)
	var weapon_slot: InventoryUi.SlotView = auto_free(InventoryUi.SlotView.new())
	weapon_slot.worn = ItemDef.Slot.WEAPON
	var armor_slot: InventoryUi.SlotView = auto_free(InventoryUi.SlotView.new())
	armor_slot.worn = ItemDef.Slot.ARMOR

	assert_bool(ui.can_drop({from = 0, worn = -1}, slot.call(5))).is_true()
	assert_bool(ui.can_drop({from = 0, worn = -1}, weapon_slot)).is_false()  # wood
	assert_bool(ui.can_drop({from = 1, worn = -1}, armor_slot)).is_false()  # club
	assert_bool(ui.can_drop({from = 1, worn = -1}, weapon_slot)).is_true()
	ui.drop({from = 0, worn = -1}, slot.call(5))
	ui.drop({from = 1, worn = -1}, weapon_slot)
	ui.drop({from = -1, worn = ItemDef.Slot.WEAPON}, slot.call(1))  # onto the club: swap
	ui.drop({from = -1, worn = ItemDef.Slot.WEAPON}, slot.call(7))
	assert_array(requests).is_equal(
		[["move", 0, 5], ["equip", 1], ["equip", 1], ["off", ItemDef.Slot.WEAPON, 7]]
	)
