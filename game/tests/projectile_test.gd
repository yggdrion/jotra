extends GdUnitTestSuite
## Projectiles in SimWorld: shooting a bow, flight, hits on enemies, players and pieces, and
## their place in the snapshots.

const TICK := 0.1


func test_a_bow_needs_arrows_and_a_full_enough_draw() -> void:
	var world := _world()
	var player: SimWorld.SimPlayer = world.players[1]
	var bow := Content.item(&"bow")
	player.inventory.add(&"arrow", 3)  # slot 0
	assert_bool(world.shoot(1, Vector2.RIGHT, 1.0)).is_false()  # no bow in hand
	player.inventory.add(&"bow", 1)
	player.inventory.equip(1)
	assert_bool(world.shoot(1, Vector2.RIGHT, bow.min_draw / 2)).is_false()
	assert_bool(world.shoot(1, Vector2.ZERO, 1.0)).is_false()
	assert_bool(world.shoot(1, Vector2.RIGHT, 1.0)).is_true()
	assert_int(player.inventory.count_of(&"arrow")).is_equal(2)
	assert_float(player.stamina).is_equal(Content.tuning.max_stamina - bow.draw_cost)
	assert_int(world.projectiles.size()).is_equal(1)
	# Drawing takes time: a second full shot right away is refused, one after the draw isn't.
	assert_bool(world.shoot(1, Vector2.RIGHT, 1.0)).is_false()
	world.tick(bow.draw_time)
	assert_bool(world.shoot(1, Vector2.RIGHT, 1.0)).is_true()
	player.inventory.take({&"arrow": 1})
	world.tick(bow.draw_time)
	assert_bool(world.shoot(1, Vector2.RIGHT, 1.0)).is_false()  # out of arrows


func test_an_arrow_hurts_the_first_enemy_and_is_spent() -> void:
	var world := _world()
	var bow := _arm(world)
	var near := _enemy(world, Vector2(60, 0))
	var behind := _enemy(world, Vector2(90, 0))
	world.shoot(1, Vector2.RIGHT, 1.0)
	for i in 10:
		world.tick(TICK)
	assert_float(near.health).is_equal(100.0 - bow.arrow_damage)
	assert_float(behind.health).is_equal(100.0)
	assert_dict(world.projectiles).is_empty()


func test_a_short_draw_flies_shorter_and_hits_softer() -> void:
	var world := _world()
	var bow := _arm(world)
	var enemy := _enemy(world, Vector2(bow.arrow_range * 0.8, 0))
	world.shoot(1, Vector2.RIGHT, 0.5)
	for i in 30:
		world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0)  # range ran out first
	assert_dict(world.projectiles).is_empty()
	enemy.position = Vector2(bow.arrow_range * 0.3, 0)
	world.tick(bow.draw_time)
	world.shoot(1, Vector2.RIGHT, 0.5)
	for i in 10:
		world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0 - bow.arrow_damage * 0.5)


func test_walls_stop_player_arrows() -> void:
	var world := _world()
	_arm(world)
	var tile := Vector2i(3, 0)
	var chunk: SimWorld.SimChunk = world.chunks[Building.chunk_of_tile(tile)]
	chunk.removed[Building.index_in_chunk(tile)] = true
	world.players[1].inventory.add(&"wood", 10)
	assert_bool(world.build(1, tile, &"wall")).is_true()
	var enemy := _enemy(world, Vector2(100, 8))
	world.shoot(1, Vector2(100, 8), 1.0)
	for i in 10:
		world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0)
	assert_dict(world.projectiles).is_empty()
	assert_float(world.pieces[tile].health).is_equal(Content.piece(&"wall").health)


func test_enemy_arrows_hurt_players_and_not_their_own_team() -> void:
	var world := _world()
	var enemy := _enemy(world, Vector2(100, 0))
	_enemy_arrow(world, enemy, Vector2(100, 0), Vector2.LEFT, 200.0)
	for i in 10:
		world.tick(TICK)
	# Hunger regenerates a little meanwhile.
	var hurt: float = world.players[1].health
	assert_float(hurt).is_equal_approx(Content.tuning.max_health - 12, 0.5)
	# A dashing player is passed through, and the arrow flies on.
	world.players[1].dashed_at = world.time
	_enemy_arrow(world, enemy, Vector2(40, 0), Vector2.LEFT, 200.0)
	world.tick(TICK)
	world.tick(TICK)
	assert_float(world.players[1].health).is_equal_approx(hurt, 0.1)
	assert_int(world.projectiles.size()).is_equal(1)
	# An enemy's arrow doesn't hurt enemies, nor a player's arrow players.
	_enemy_arrow(world, enemy, Vector2(80, 0), Vector2.RIGHT, 100.0)
	world.add_projectile(SimProjectile.Team.PLAYERS, 1, Vector2(-30, 0), Vector2.RIGHT, 300, 12, 20)
	world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0)
	assert_float(world.players[1].health).is_equal_approx(hurt, 0.1)


func test_enemy_arrows_damage_walls() -> void:
	var world := _world()
	var tile := Vector2i(3, 0)
	var chunk: SimWorld.SimChunk = world.chunks[Building.chunk_of_tile(tile)]
	chunk.removed[Building.index_in_chunk(tile)] = true
	world.players[1].inventory.add(&"wood", 10)
	world.build(1, tile, &"wall")
	world.players[1].position = Vector2(-100, 0)
	_enemy_arrow(world, _enemy(world, Vector2(100, 0)), Vector2(100, 0), Vector2.LEFT, 200.0)
	for i in 10:
		world.tick(TICK)
	assert_float(world.pieces[tile].health).is_equal(Content.piece(&"wall").health - 12)


func test_projectiles_are_in_snapshots_near_the_player() -> void:
	var world := _world()
	var p := world.add_projectile(
		SimProjectile.Team.PLAYERS, 1, Vector2(10, 0), Vector2.DOWN, 100, 1, 50
	)
	var seen: Vector3 = world.snapshot_for(1).projectiles[p.id]
	assert_vector(Vector2(seen.x, seen.y)).is_equal(Vector2(10, 0))
	assert_float(seen.z).is_equal_approx(PI / 2, 0.001)
	var packed := Net.unpack_entities(Net.pack_entities({p.id: seen}, Vector2.ZERO), Vector2.ZERO)
	assert_float(packed[p.id].z).is_equal_approx(PI / 2, 0.003)
	world.players[1].position = Vector2(100000, 0)
	assert_dict(world.snapshot_for(1).projectiles).is_empty()


func _world() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1").position = Vector2.ZERO
	world.tick(TICK)
	return world


## Gives player 1 a bow in hand and arrows, returns the bow.
func _arm(world: SimWorld) -> ItemDef:
	var inventory: Inventory = world.players[1].inventory
	inventory.add(&"bow", 1)
	inventory.add(&"arrow", 20)
	inventory.equip(0)
	return Content.item(&"bow")


## A harmless enemy that stays where it is.
func _enemy(world: SimWorld, at: Vector2) -> SimEnemy:
	var enemy := world.add_enemy(at, 100, 0)
	enemy.speed = 0.0
	return enemy


## An arrow of 12 damage shot by enemy.
func _enemy_arrow(
	world: SimWorld, enemy: SimEnemy, from: Vector2, direction: Vector2, max_range: float
) -> void:
	world.add_projectile(SimProjectile.Team.ENEMIES, enemy.id, from, direction, 300, 12, max_range)
