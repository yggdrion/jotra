extends GdUnitTestSuite
## Healing and magic in SimWorld: regeneration from cooked food, the healing draught and its
## cooldown, and the three rune abilities with their cooldown and stamina gating.

const TICK := 0.1


func test_cooked_food_regenerates_health_over_time() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var def := Content.item(&"cooked_meat")
	player.hunger = 10.0
	player.health = 20.0
	player.inventory.add(&"cooked_meat", 1)
	assert_bool(world.eat(1, -1)).is_true()
	assert_float(player.hunger).is_equal(10.0 + def.food)
	assert_float(player.regen_left).is_equal(def.regen_time)
	var before := player.health
	for i in 20:
		world.tick(TICK)
	# Two seconds of it, on top of the base regeneration.
	assert_float(player.health - before).is_greater_equal(def.regen * 2.0 * 0.95)
	assert_float(player.regen_left).is_equal_approx(def.regen_time - 2.0, 0.01)
	for i in int(def.regen_time * 10):
		world.tick(TICK)
	assert_float(player.regen_left).is_equal(0.0)


func test_raw_food_gives_no_regeneration() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.hunger = 10.0
	player.inventory.add(&"meat", 1)
	assert_bool(world.eat(1, -1)).is_true()
	assert_float(player.regen_left).is_equal(0.0)


func test_dying_ends_the_regeneration() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.regen_left = 5.0
	player.regen = 1.0
	world._die(player)
	assert_float(player.regen_left).is_equal(0.0)


func test_a_draught_heals_at_once_and_cools_down() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	assert_bool(world.use_draught(1)).is_false()  # none carried
	player.inventory.add(&"healing_draught", 2)
	player.health = 10.0
	assert_bool(world.use_draught(1)).is_true()
	assert_float(player.health).is_equal_approx(10.0 + Content.item(&"healing_draught").heal, 0.01)
	assert_int(player.inventory.count_of(&"healing_draught")).is_equal(1)
	assert_bool(world.use_draught(1)).is_false()  # cooling down
	for i in int(Content.tuning.draught_cooldown / TICK) + 2:
		world.tick(TICK)
	assert_bool(world.use_draught(1)).is_true()


func test_a_draught_never_heals_past_the_maximum() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	player.inventory.add(&"healing_draught", 1)
	world.use_draught(1)
	assert_float(player.health).is_equal(player.max_health())


func test_an_ability_needs_its_rune_worn() -> void:
	var world := _world()
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_false()
	_wear(world, &"shock_rune")
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()


func test_an_ability_costs_stamina_and_cools_down() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var def: AbilityDef = Content.abilities[&"shockwave"]
	_wear(world, &"shock_rune")
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()
	assert_float(player.stamina).is_equal(Content.tuning.max_stamina - def.stamina_cost)
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_false()
	world.tick(def.cooldown + TICK)
	player.stamina = def.stamina_cost - 1.0
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_false()  # too tired
	player.stamina = def.stamina_cost
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()


func test_a_frost_bolt_hurts_and_slows_the_enemy_it_hits() -> void:
	var world := _world()
	var def: AbilityDef = Content.abilities[&"frost_bolt"]
	_wear(world, &"frost_rune")
	var enemy := _enemy(world, Vector2(80, 0))
	enemy.speed = 100.0
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()
	assert_int(world.projectiles.size()).is_equal(1)
	for i in 10:
		world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0 - def.damage)
	assert_bool(enemy.slowed(world)).is_true()
	assert_float(enemy._speed(world)).is_equal_approx(100.0 * def.slow, 0.001)
	assert_bool(Net.enemy_slowed(Net.enemy_z(0, 1.0, enemy.slowed(world)))).is_true()
	world.time += def.slow_time + 0.1
	assert_float(enemy._speed(world)).is_equal(100.0)


func test_a_slowed_enemy_walks_slower() -> void:
	var world := _world()
	var fast := world.add_enemy(Vector2(300, 0), 100, 0)
	var slow := world.add_enemy(Vector2(300, 50), 100, 0)
	fast.speed = 50.0
	slow.speed = 50.0
	fast.provoke(1)
	slow.provoke(1)
	slow.slow = 0.5
	slow.slow_until = world.time + 100.0
	for i in 10:
		world.tick(TICK)
	assert_float(300.0 - fast.position.x).is_greater(1.5 * (300.0 - slow.position.x) - 1.0)
	assert_float(300.0 - slow.position.x).is_greater(0.0)


func test_a_ward_heals_players_inside_it_until_it_ends() -> void:
	var world := _world()
	var def: AbilityDef = Content.abilities[&"healing_ward"]
	_wear(world, &"ward_rune")
	world.add_player(2, "p2").position = Vector2(def.radius - 4, 0)
	world.add_player(3, "p3").position = Vector2(def.radius + 40, 0)
	for id in [1, 2, 3]:
		world.players[id].health = 10.0
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()
	assert_int(world.wards.size()).is_equal(1)
	for i in 10:
		world.tick(TICK)
	# A second in: the two inside gained about heal_per_second (plus the base regeneration).
	var base := Content.tuning.health_regen * 1.0
	assert_float(world.players[1].health - 10.0).is_greater(def.heal_per_second * 0.9)
	assert_float(world.players[2].health - 10.0).is_greater(def.heal_per_second * 0.9)
	assert_float(world.players[3].health - 10.0).is_less(base + 0.5)
	for i in int(def.duration / TICK) + 5:
		world.tick(TICK)
	assert_dict(world.wards).is_empty()


func test_a_shockwave_hurts_breaks_and_pushes_back_what_is_near() -> void:
	var world := _world()
	var def: AbilityDef = Content.abilities[&"shockwave"]
	_wear(world, &"shock_rune")
	var near := _enemy(world, Vector2(40, 0))
	var far := _enemy(world, Vector2(def.radius + 60, 0))
	near.state = SimEnemy.State.CHASE
	near.target = 1
	near.poise = 1.0
	assert_bool(world.use_ability(1, Vector2.RIGHT)).is_true()
	assert_float(near.health).is_equal(100.0 - def.damage)
	assert_float(near.knock_vel.x).is_greater(0.0)
	assert_int(near.state).is_equal(SimEnemy.State.STAGGER)
	assert_float(far.health).is_equal(100.0)


func test_a_shockwave_breaks_a_windup() -> void:
	var world := _world()
	_wear(world, &"shock_rune")
	var enemy := _enemy(world, Vector2(30, 0))
	enemy.state = SimEnemy.State.WINDUP
	enemy._until = world.time + 5.0
	world.use_ability(1, Vector2.RIGHT)
	assert_int(enemy.state).is_equal(SimEnemy.State.STAGGER)


func test_runes_are_saved_with_the_inventory() -> void:
	var inventory := Inventory.new(4)
	inventory.add(&"frost_rune", 1)
	inventory.equip(0)
	var copy := inventory.copy()
	assert_str(copy.equipment[ItemDef.Slot.RUNE]).is_equal("frost_rune")
	assert_object(copy.ability()).is_same(Content.abilities[&"frost_bolt"])


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world


## Puts a rune in player 1's rune slot.
func _wear(world: SimWorld, rune: StringName) -> void:
	var inventory: Inventory = world.players[1].inventory
	inventory.add(rune, 1)
	var index := inventory.slots.find_custom(
		func(slot: Dictionary) -> bool: return slot.get("item") == rune
	)
	inventory.equip(index)


## A harmless enemy that stays where it is.
func _enemy(world: SimWorld, at: Vector2) -> SimEnemy:
	var enemy := world.add_enemy(at, 100, 0)
	enemy.speed = 0.0
	return enemy
