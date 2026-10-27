extends GdUnitTestSuite
## Tools and gathering: swinging at trees and rocks with an axe or pickaxe, the tier check,
## sticks and pebbles by hand, and the first tools being craftable from them.

const TICK := 0.1


func test_tree_needs_an_axe_and_falls_after_enough_swings() -> void:
	var world := _world()
	var tree := _stand_at(world, WorldGen.Prop.TREE)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	assert_array(world.events).contains([["node", 1, tree[2], "Needs an axe"]])
	world.players[1].inventory.add(&"pebble_axe", 1)
	var swings := ceili(Content.tuning.tree_health / Content.item(&"pebble_axe").tool_damage)
	for i in swings:
		assert_bool(world.chunks[tree[0]].removed.has(tree[1])).is_false()
		world.tick(1.0)
		world.players[1].stamina = 100.0
		world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	assert_bool(world.chunks[tree[0]].removed.has(tree[1])).is_true()
	assert_array(world.events).contains([["prop_removed", tree[0], tree[1]]])
	assert_str(world.drops.values()[0].item).is_equal("wood")


func test_rock_needs_a_pickaxe_not_an_axe() -> void:
	var world := _world()
	var rock := _stand_at(world, WorldGen.Prop.ROCK)
	world.players[1].inventory.add(&"pebble_axe", 1)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	assert_array(world.events).contains([["node", 1, rock[2], "Needs a pickaxe"]])
	assert_dict(world.chunks[rock[0]].node_health).is_empty()


func test_tier_gates_the_tool() -> void:
	var world := _world()
	var tree := _stand_at(world, WorldGen.Prop.TREE)
	var old_tier := Content.tuning.tree_tier
	Content.tuning.tree_tier = 2
	world.players[1].inventory.add(&"pebble_axe", 1)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	assert_array(world.events).contains([["node", 1, tree[2], "Needs a better axe"]])
	world.players[1].inventory.add(&"stone_axe", 1)
	world.tick(1.0)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	Content.tuning.tree_tier = old_tier
	assert_float(world.chunks[tree[0]].node_health[tree[1]]).is_equal(
		Content.tuning.tree_health - Content.item(&"stone_axe").tool_damage
	)


func test_a_swing_that_hits_an_enemy_spares_the_tree() -> void:
	var world := _world()
	var tree := _stand_at(world, WorldGen.Prop.TREE)
	world.players[1].inventory.add(&"pebble_axe", 1)
	var enemy := world.add_enemy(world.players[1].position + Vector2(10, 0), 100, 0)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_dict(world.chunks[tree[0]].node_health).is_empty()


func test_sticks_and_pebbles_are_picked_up_by_hand_and_make_the_first_tools() -> void:
	var world := _world()
	for kind: int in [WorldGen.Prop.STICK, WorldGen.Prop.PEBBLE]:
		var found := _stand_at(world, kind)
		assert_bool(world.remove_prop(1, found[0], found[1])).is_true()
		world.tick(Content.tuning.gather_time)
	var tree := _stand_at(world, WorldGen.Prop.TREE)
	assert_bool(world.remove_prop(1, tree[0], tree[1])).is_false()
	for tool: StringName in [&"pebble_axe", &"pebble_pickaxe"]:
		var recipe: RecipeDef = Content.recipes[tool]
		assert_str(recipe.station).is_empty()
		for item: StringName in recipe.inputs:
			assert_bool(item in [&"stick", &"pebble"]).is_true()
		world.players[1].inventory.add(&"stick", 3)
		world.players[1].inventory.add(&"pebble", 4)
		assert_bool(world.craft(1, tool)).is_true()
	assert_object(world.players[1].inventory.best_tool(ItemDef.Tool.PICKAXE)).is_not_null()


func test_best_tool_prefers_tier_then_damage() -> void:
	var inventory := Inventory.new(4)
	assert_object(inventory.best_tool(ItemDef.Tool.AXE)).is_null()
	inventory.add(&"pebble_axe", 1)
	inventory.add(&"stone_axe", 1)
	assert_object(inventory.best_tool(ItemDef.Tool.AXE)).is_same(Content.item(&"stone_axe"))
	assert_object(inventory.best_tool(ItemDef.Tool.PICKAXE)).is_null()


## Puts the player 10 px left of a prop of a kind in a loaded chunk; returns [chunk, prop id,
## position].
func _stand_at(world: SimWorld, kind: int) -> Array:
	for coord: Vector2i in world.chunks:
		for id: int in world.chunks[coord].props:
			if world.chunks[coord].props[id] != kind or world.chunks[coord].removed.has(id):
				continue
			var at := WorldGen.prop_position(coord, id)
			world.players[1].position = at - Vector2(10, 0)
			world.players[1].moved_at = world.time
			return [coord, id, at]
	fail("no prop of kind %d" % kind)
	return []


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1")
	world.tick(TICK)
	return world
