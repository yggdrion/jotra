extends GdUnitTestSuite
## Dungeon buffs: stacking, synergies, rolling, orbs, and what each stat does in the sim.

const TICK := 0.1


## A world with p1 inside a fresh run, no enemies around.
func _in_run() -> SimWorld:
	var world := SimWorld.new()
	world.spawn_enemies = false
	world.add_player(1, "p1")
	world.players[1].position = Content.tuning.dungeon_entrance
	world.tick(TICK)
	world.use_portal(1)
	world.tick(1.0)
	world.enemies.clear()
	return world


## An enemy right next to p1, with plenty of health unless given.
func _enemy_by(world: SimWorld, health := 1000.0) -> SimEnemy:
	return world.add_enemy(world.players[1].position + Vector2(10, 0), health, 0.0)


func test_stacks_up_to_the_max() -> void:
	var buffs := Buffs.new()
	var def: BuffDef = Content.buffs[&"grave_strength"]
	for i in def.max_stacks:
		assert_bool(buffs.add(&"grave_strength")).is_true()
	assert_bool(buffs.add(&"grave_strength")).is_false()
	assert_bool(buffs.add(&"no_such_buff")).is_false()
	assert_float(buffs.stat("damage")).is_equal_approx(def.amount * def.max_stacks, 0.0001)
	assert_float(buffs.stat("armor")).is_equal(0.0)


func test_synergies_add_once_both_buffs_are_held() -> void:
	var buffs := Buffs.new()
	var synergy: SynergyDef = Content.synergies[&"ghost_walk"]
	buffs.add(&"wraith_step")
	assert_array(buffs.synergies()).is_empty()
	buffs.add(&"light_feet")
	buffs.add(&"light_feet")
	assert_array(buffs.synergies()).is_equal([&"ghost_walk"])
	assert_float(buffs.stat(synergy.stat)).is_equal(synergy.amount)


func test_data_round_trips() -> void:
	var buffs := Buffs.new()
	buffs.add(&"bone_marrow")
	buffs.add(&"bone_marrow")
	buffs.add(&"rune_of_ruin")
	var again := Buffs.new()
	again.load_data(buffs.to_data())
	assert_dict(again.stacks).is_equal(buffs.stacks)


func test_rolls_favor_common_and_rare_bonus_shifts_them() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rare := [0, 0]
	for i in 2000:
		for bonus: int in [0, 1]:
			var def: BuffDef = Content.buffs[Buffs.roll(rng, bonus * 3.0)]
			if def.rarity == ItemDef.Rarity.RARE:
				rare[bonus] += 1
	assert_int(rare[0]).is_between(40, 180)  # about 5%
	assert_int(rare[1]).is_greater(rare[0] * 2)


func test_orbs_are_picked_up_until_the_max_stacks() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var def: BuffDef = Content.buffs[&"wraith_step"]
	for i in def.max_stacks:
		player.buffs.add(&"wraith_step")
	var orb := world._add_orb(&"wraith_step", player.position)
	var other := world._add_orb(&"grave_strength", player.position)
	world.tick(TICK)
	assert_bool(world.drops.has(orb.id)).is_true()
	assert_bool(world.drops.has(other.id)).is_false()
	assert_int(player.buffs.stacks[&"grave_strength"]).is_equal(1)
	var kind := -1 - Content.buff_ids.find(&"wraith_step")
	assert_float(world.snapshot_for(1).drops[orb.id].z).is_equal(float(kind))


func test_kills_inside_a_run_drop_orbs_and_outside_none() -> void:
	var world := _in_run()
	for i in 60:
		_enemy_by(world, 1.0)
		world.attack(1, false, Vector2.RIGHT, PackedInt32Array(world.enemies.keys()))
		world.tick(1.0)  # off cooldown, and the orb gets picked up
	assert_int(world.players[1].buffs.stacks.size()).is_greater(0)
	var outside := SimWorld.new()
	outside.spawn_enemies = false
	outside.add_player(1, "p1")
	outside.tick(TICK)
	for i in 60:
		_enemy_by(outside, 1.0)
		outside.attack(1, false, Vector2.RIGHT, PackedInt32Array(outside.enemies.keys()))
		outside.tick(1.0)
	assert_dict(outside.players[1].buffs.stacks).is_empty()


func test_leaving_the_run_drops_the_buffs_and_their_health() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	player.buffs.add(&"bone_marrow")
	player.health = player.max_health()
	assert_float(player.health).is_greater(Content.tuning.max_health)
	player.position = player.run.exit
	world.use_portal(1)
	assert_dict(player.buffs.stacks).is_empty()
	assert_float(player.health).is_equal(Content.tuning.max_health)


func test_damage_crit_lifesteal_and_bleed() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var move := Content.attack(&"", false)
	var enemy := _enemy_by(world)
	player.buffs.add(&"grave_strength")
	player.buffs.add(&"draugr_thirst")
	player.buffs.stacks[&"rune_of_ruin"] = 10  # always crits
	player.health = 50.0
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	var dealt := move.damage * 1.15 * 2.0
	assert_float(enemy.health).is_equal_approx(1000.0 - dealt, 0.01)
	assert_float(player.health).is_equal_approx(50.0 + dealt * 0.05, 0.01)
	player.buffs.stacks.erase(&"rune_of_ruin")
	player.buffs.add(&"rusted_edge")
	world.tick(1.0)
	var before := enemy.health
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	var hit := move.damage * 1.15
	world.tick(1.0)
	var bleed: float = Content.buffs[&"rusted_edge"].amount
	assert_float(enemy.health).is_equal_approx(before - hit - bleed, 0.5)
	world.tick(Content.tuning.bleed_time)
	var after := enemy.health
	world.tick(1.0)
	assert_float(enemy.health).is_equal(after)  # the bleed ran out


func test_quick_hands_shortens_the_cooldown() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var move := Content.attack(&"", false)
	player.buffs.add(&"quick_hands")
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array())
	assert_float(player.cooldown_until - world.time).is_equal_approx(move.cooldown * 0.9, 0.001)


func test_kill_buffs_heal_and_refill_stamina() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	player.buffs.add(&"feast_of_bones")
	player.buffs.add(&"grim_momentum")
	player.health = 50.0
	player.stamina = 50.0
	var enemy := _enemy_by(world, 1.0)
	world.attack(1, false, Vector2.RIGHT, PackedInt32Array([enemy.id]))
	assert_bool(world.enemies.has(enemy.id)).is_false()
	assert_float(player.health).is_equal_approx(56.0, 0.01)
	var cost := Content.attack(&"", false).cost
	assert_float(player.stamina).is_equal_approx(50.0 - cost + 15.0, 0.01)


func test_dash_burst_and_longer_iframes() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var enemy := _enemy_by(world)
	player.buffs.add(&"charging_ram")
	player.buffs.add(&"wraith_step")
	assert_bool(world.dash(1)).is_true()
	assert_float(enemy.health).is_equal(1000.0 - 20.0)
	var t := Content.tuning
	world.tick(t.iframes + t.iframe_slack + 0.05)
	assert_bool(world.damage_player(1, 10.0)).is_false()  # still in the longer i-frames
	world.tick(0.1)
	assert_bool(world.damage_player(1, 10.0)).is_true()


func test_armor_and_thorns() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var enemy := _enemy_by(world)
	player.buffs.add(&"barrow_skin")
	player.buffs.add(&"bramble_mail")
	var synergy: SynergyDef = Content.synergies[&"iron_hide"]
	world.damage_player(1, 10.0, enemy)
	assert_float(player.health).is_equal(Content.tuning.max_health - 8.0)
	assert_float(enemy.health).is_equal(1000.0 - 6.0 - synergy.amount)


func test_light_feet_lets_moves_go_further() -> void:
	var world := _in_run()
	var player: SimWorld.SimPlayer = world.players[1]
	var t := Content.tuning
	var start := player.position
	player.moved_at = world.time - 1.0
	var far := start + Vector2(t.walk_speed * (1.0 + SimWorld.MOVE_SLACK) + 10, 0)
	assert_bool(world.move_player(1, far)).is_false()
	player.buffs.add(&"light_feet")
	assert_bool(world.move_player(1, far)).is_true()
