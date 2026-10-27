extends GdUnitTestSuite
## What lands with a player's hit beyond its damage, whatever made it (swing, arrow, rune):
## poise and push from arrows, lifesteal, bleed and kill buffs, magic through a shield, and an
## exploder that still detonates when killed in its windup.

const TICK := 0.1


func test_an_arrow_wears_poise_and_pushes_like_a_light_swing() -> void:
	var world := _world()
	var bow := _arm(world)
	var enemy := _enemy(world, Vector2(60, 0))
	enemy.poise = 1.0  # any arrow breaks it
	world.shoot(1, Vector2.RIGHT, 1.0)
	_tick_until_hit(world, enemy)
	assert_int(enemy.state).is_equal(SimEnemy.State.STAGGER)
	var hit := _event(world, "hit")
	assert_float((hit[5] as Vector2).x).is_equal_approx(
		bow.arrow_knock * enemy.def.knock_scale, 0.1
	)
	assert_float(bow.arrow_knock).is_greater(0.0)
	assert_float(bow.arrow_poise).is_greater(0.0)


func test_a_half_drawn_arrow_wears_half_the_poise() -> void:
	var world := _world()
	var bow := _arm(world)
	var enemy := _enemy(world, Vector2(60, 0))
	world.shoot(1, Vector2.RIGHT, 0.5)
	_tick_until_hit(world, enemy)
	# Regenerated a little in the ticks before the hit, never past full.
	assert_float(enemy.poise).is_equal_approx(enemy.def.poise - bow.arrow_poise * 0.5, 0.01)


func test_arrows_lifesteal_and_bleed() -> void:
	var plain := _world()
	_arm(plain)
	plain.players[1].health = 50.0
	_shoot_and_hit(plain)
	var world := _world()
	var bow := _arm(world)
	var player: SimWorld.SimPlayer = world.players[1]
	player.health = 50.0
	player.buffs.add(&"draugr_thirst")
	player.buffs.add(&"rusted_edge")
	var enemy := _shoot_and_hit(world)
	var stolen: float = bow.arrow_damage * Content.buffs[&"draugr_thirst"].amount
	var gained: float = player.health - plain.players[1].health
	assert_float(gained).is_equal_approx(stolen, 0.01)
	assert_float(enemy.bleed_dps).is_equal(Content.buffs[&"rusted_edge"].amount)
	assert_float(enemy.bleed_until).is_greater(world.time)
	assert_int(enemy.bleed_by).is_equal(1)


func test_an_arrow_kill_feeds_the_kill_buffs() -> void:
	var world := _world()
	_arm(world)
	var player: SimWorld.SimPlayer = world.players[1]
	player.buffs.add(&"feast_of_bones")
	player.health = 50.0
	var enemy := world.add_enemy(Vector2(60, 0), 1, 0)
	world.shoot(1, Vector2.RIGHT, 1.0)
	_tick_until_hit(world, enemy)
	assert_bool(world.enemies.has(enemy.id)).is_false()
	var kill_heal: float = Content.buffs[&"feast_of_bones"].amount
	assert_float(player.health).is_greater_equal(50.0 + kill_heal)


func test_ability_hits_lifesteal_and_bleed() -> void:
	for rune in [&"shock_rune", &"frost_rune"]:
		var world := _world()
		var player: SimWorld.SimPlayer = world.players[1]
		_wear(world, rune)
		player.buffs.add(&"draugr_thirst")
		player.buffs.add(&"rusted_edge")
		player.health = 50.0
		var enemy := _enemy(world, Vector2(40, 0))
		world.use_ability(1, Vector2.RIGHT)
		_tick_until_hit(world, enemy)
		assert_float(player.health).override_failure_message(str(rune)).is_greater(50.0)
		assert_float(enemy.bleed_until).override_failure_message(str(rune)).is_greater(world.time)


func test_magic_goes_through_a_shield_from_the_front() -> void:
	for rune in [&"shock_rune", &"frost_rune"]:
		var world := _world()
		_wear(world, rune)
		var def: EnemyDef = Content.enemies[&"shield_draugr"]
		var shield := world.add_enemy(Vector2(40, 0), 100, 0, def)
		shield.speed = 0.0
		shield.facing = Vector2.LEFT
		world.use_ability(1, Vector2.RIGHT)
		_tick_until_hit(world, shield)
		var ability: AbilityDef = Content.abilities[Content.item(rune).ability]
		assert_float(shield.health).override_failure_message(str(rune)).is_equal_approx(
			100.0 - ability.damage, 0.001
		)
		assert_array(_events(world, "enemy", Net.EnemyEvent.BLOCK)).is_empty()


## Also by a heavy, which would break the windup were the hit not the last.
func test_an_exploder_killed_in_its_windup_still_detonates() -> void:
	for heavy in [false, true]:
		var world := _world()
		var def: EnemyDef = Content.enemies[&"bloated_draugr"]
		var bloated := world.add_enemy(Vector2(def.attack_range * 2, 0), 40, 40, def)
		_windup(world)
		bloated.health = 1.0
		world.players[1].position = bloated.position - Vector2(10, 0)
		world.attack(1, heavy, Vector2.RIGHT, PackedInt32Array([bloated.id]))
		assert_bool(world.enemies.has(bloated.id)).is_false()
		var health: float = world.players[1].health
		assert_float(health).override_failure_message(str(heavy)).is_less(Content.tuning.max_health)
		assert_array(_events(world, "enemy", Net.EnemyEvent.DIED)).has_size(1)


func test_an_exploder_killed_outside_its_windup_just_dies() -> void:
	var world := _world()
	var def: EnemyDef = Content.enemies[&"bloated_draugr"]
	var bloated := world.add_enemy(Vector2(10, 0), 1, 40, def)
	assert_int(bloated.state).is_equal(SimEnemy.State.IDLE)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([bloated.id]))
	assert_bool(world.enemies.has(bloated.id)).is_false()
	assert_float(world.players[1].health).is_equal(Content.tuning.max_health)


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	world.events.clear()
	return world


## Gives player 1 a bow in hand and arrows, returns the bow.
func _arm(world: SimWorld) -> ItemDef:
	var inventory: Inventory = world.players[1].inventory
	inventory.add(&"bow", 1)
	inventory.add(&"arrow", 20)
	inventory.equip(0)
	return Content.item(&"bow")


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


## Shoots a full draw at a fresh enemy 60 px to the right and ticks until it is hit.
func _shoot_and_hit(world: SimWorld) -> SimEnemy:
	var enemy := _enemy(world, Vector2(60, 0))
	world.shoot(1, Vector2.RIGHT, 1.0)
	_tick_until_hit(world, enemy)
	return enemy


## Ticks until enemy took a hit (or died).
func _tick_until_hit(world: SimWorld, enemy: SimEnemy) -> void:
	for i in 20:
		if not world.enemies.has(enemy.id) or enemy.health < enemy.max_health:
			return
		world.tick(TICK)
	fail("no hit")


func _event(world: SimWorld, kind: String) -> Array:
	for e: Array in world.events:
		if e[0] == kind:
			return e
	fail("no %s event" % kind)
	return []


func _events(world: SimWorld, kind: String, enemy_event: int) -> Array:
	return world.events.filter(func(e: Array) -> bool: return e[0] == kind and e[2] == enemy_event)


## Ticks until an enemy has started a windup, returns its event.
func _windup(world: SimWorld) -> Array:
	for i in 100:
		for e in world.events:
			if e[0] == "windup":
				return e
		world.tick(TICK)
	fail("no windup")
	return []
