extends GdUnitTestSuite
## Terrain: height levels from the seed, broad and sealed by cliffs with ramps, flat at the
## spawn, and cliffs blocking walking, hits, arrows and building in SimWorld.

const TICK := 0.1
## The area the shape tests look at, in tiles: away from the flat spawn.
const AREA := Rect2i(200, -100, 256, 256)


func test_same_seed_gives_same_terrain() -> void:
	var a := WorldGen.chunk(42, Vector2i(9, -4))
	var b := WorldGen.chunk(42, Vector2i(9, -4))
	assert_array(Array(a.levels)).is_equal(Array(b.levels))
	assert_array(Array(a.terrain)).is_equal(Array(b.terrain))


func test_the_spawn_is_flat_ground() -> void:
	for world_seed in [0, 1, 2, 3]:
		for coord in WorldGen.around(Vector2i.ZERO, 1):
			var data := WorldGen.chunk(world_seed, coord)
			for id in WorldGen.CHUNK * WorldGen.CHUNK:
				var tile := Building.tile_at(coord, id)
				if Vector2(tile).length() > Terrain.FLAT_RADIUS - Terrain.LATTICE * 2:
					continue
				assert_int(data.levels[id]).is_equal(Terrain.Level.GROUND)
				assert_int(data.terrain[id]).is_equal(0)


func test_a_lower_neighbour_makes_a_cliff() -> void:
	for world_seed in [1, 2]:
		var levels := _levels(world_seed)
		var bits := _bits(world_seed)
		var cliffs := 0
		var ramps := 0
		for y in range(1, AREA.size.y - 1):
			for x in range(1, AREA.size.x - 1):
				var i := y * AREA.size.x + x
				var lower := false
				for dir in Terrain.AROUND:
					lower = lower or levels[i + dir.y * AREA.size.x + dir.x] < levels[i]
				assert_bool(bits[i] & Terrain.CLIFF != 0).is_equal(lower)
				cliffs += 1 if lower else 0
				if bits[i] & Terrain.RAMP:
					ramps += 1
					assert_bool(lower).is_true()
		assert_int(cliffs).is_greater(100)
		assert_int(ramps).is_greater(Terrain.RAMP_MIN * 3)


func test_every_level_is_broad() -> void:
	for world_seed in [1, 2, 3]:
		var levels := _levels(world_seed)
		var w := AREA.size.x
		var seen := {}
		var regions := 0
		for start in levels.size():
			if seen.has(start):
				continue
			# Flood fill one region of a level.
			var todo := [start]
			seen[start] = true
			var size := 0
			var at_edge := false
			while not todo.is_empty():
				var i: int = todo.pop_back()
				size += 1
				var x := i % w
				var y := i / w
				at_edge = at_edge or x == 0 or y == 0 or x == w - 1 or y == AREA.size.y - 1
				for dir in Terrain.DIRS:
					var nx := x + dir.x
					var ny := y + dir.y
					var j := ny * w + nx
					if nx < 0 or ny < 0 or nx >= w or ny >= AREA.size.y or seen.has(j):
						continue
					if levels[j] == levels[i]:
						seen[j] = true
						todo.append(j)
			regions += 1
			if not at_edge:
				assert_int(size).is_greater(200)
		assert_int(regions).is_greater(1)


func test_no_prop_stands_on_a_cliff() -> void:
	var found := 0
	for coord in WorldGen.around(Vector2i(10, 0), 2):
		var data := WorldGen.chunk(1, coord)
		for id: int in data.props:
			assert_int(data.terrain[id] & Terrain.CLIFF).is_equal(0)
		for id in data.terrain.size():
			found += 1 if data.terrain[id] & Terrain.CLIFF else 0
	assert_int(found).is_greater(0)


func test_a_cliff_blocks_walking_hits_arrows_and_building() -> void:
	var cliff := _south_cliff(0)
	var above := Building.tile_center(cliff + Vector2i(0, -1))
	var below := Building.tile_center(cliff + Vector2i(0, 1))
	var world := SimWorld.new()
	world.spawn_enemies = false
	var player := world.add_player(1, "p1")
	player.position = above
	world.tick(TICK)
	world.tick(1.0)
	assert_bool(world.cliffs.has(cliff)).is_true()
	# Neither a step into it nor a long move over it.
	assert_bool(world.move_player(1, above + Vector2(0, 4))).is_false()
	assert_bool(world.move_player(1, below)).is_false()
	assert_bool(world.move_player(1, above + Vector2(4, -4))).is_true()
	player.position = above
	assert_bool(world.reaches(above, below)).is_false()
	assert_bool(world.reaches(above, above + Vector2(0, -24))).is_true()
	# A swing down over the edge lands nothing, though it would reach that far.
	var foot := Vector2(above.x, Building.tile_center(cliff).y + WorldGen.TILE / 2.0 + 4)
	var move := Content.attack(player.inventory.weapon(), false)
	var reach := move.reach + Content.tuning.hit_slack
	assert_bool(Combat.in_arc(above, Vector2.DOWN, foot, reach, move.arc)).is_true()
	var enemy := world.add_enemy(foot, 100, 0)
	enemy.speed = 0.0
	world.tick(1.0)
	var hits := world.attack(1, false, Vector2.DOWN, PackedInt32Array([enemy.id]))
	assert_int(hits.size()).is_equal(0)
	assert_float(enemy.health).is_equal(100.0)
	# Nor does an arrow: it stops at the cliff.
	player.inventory.add(&"bow", 1)
	player.inventory.add(&"arrow", 5)
	player.inventory.equip(0)
	world.tick(1.0)
	assert_bool(world.shoot(1, Vector2.DOWN, 1.0)).is_true()
	for i in 10:
		world.tick(TICK)
	assert_float(enemy.health).is_equal(100.0)
	assert_int(world.projectiles.size()).is_equal(0)
	player.inventory.add(&"wood", 10)
	assert_bool(world.build(1, cliff, &"floor")).is_false()
	# An exploder below never blows up at the player over the edge, though it would reach.
	var bloated: EnemyDef = Content.enemies[&"bloated_draugr"]
	assert_float(bloated.attack_range).is_greater(foot.distance_to(above))
	var biter := world.add_enemy(foot + Vector2(1, 0), 100, 10, bloated)
	biter.speed = 0.0
	biter.provoke(1)
	for i in 50:
		world.tick(TICK)
	assert_float(player.health).is_equal(player.max_health())


## The levels of AREA in a world, row by row.
func _levels(world_seed: int) -> PackedByteArray:
	var field := _field(world_seed)
	var out := PackedByteArray()
	for y in AREA.size.y:
		for x in AREA.size.x:
			out.append(field.level_at(AREA.position + Vector2i(x, y)))
	return out


func _bits(world_seed: int) -> PackedByteArray:
	return _field(world_seed).bits_of(AREA.position, AREA.size.x)


func _field(world_seed: int) -> Terrain.Field:
	var field := Terrain.Field.new(world_seed)
	var margin := Terrain.RAMP_SIZE + 1
	field.cover(AREA.grow(margin))
	return field


## A cliff tile with lower ground south of it, open ground two tiles each way, near the spawn.
func _south_cliff(world_seed: int) -> Vector2i:
	for radius in range(2, 8):
		for coord in WorldGen.around(Vector2i.ZERO, radius):
			var data := WorldGen.chunk(world_seed, coord)
			for id in data.terrain.size():
				var bits: int = data.terrain[id]
				if not Terrain.blocks(bits) or bits != Terrain.CLIFF | Terrain.LOWER_S:
					continue
				var tile := Building.tile_at(coord, id)
				var field := Terrain.Field.new(world_seed)
				var open := true
				for dy in [-2, -1, 1, 2]:
					var near := tile + Vector2i(0, dy)
					field.cover(Rect2i(near - Vector2i.ONE * 6, Vector2i.ONE * 13))
					if field.bits_of(near, 1)[0] & Terrain.CLIFF:
						open = false
				if open:
					return tile
	assert_bool(false).override_failure_message("no cliff found").is_true()
	return Vector2i.ZERO
