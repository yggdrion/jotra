extends GdUnitTestSuite
## Net: snapshot entities survive packing to quarter pixels and half floats, enemies with their
## kind, a shield's facing in a byte.


func test_entities_survive_packing() -> void:
	var origin := Vector2(-5000.3, 12000.7)
	var entities := {
		7: Vector3(-5000.3 + 1500.25, 12000.7 - 1200.5, 0.5),
		2147483000: Vector3(-5000.3, 12000.7, 1.0),
		3: Vector3(-5000.3 + 10.0, 12000.7, -4.0),
	}
	var bytes := Net.pack_entities(entities, origin)
	assert_int(bytes.size()).is_equal(3 * Net.ENTITY_BYTES)
	var back := Net.unpack_entities(bytes, origin)
	assert_array(back.keys()).contains_exactly_in_any_order(entities.keys())
	for id: int in entities:
		assert_vector(back[id]).is_equal_approx(entities[id], Vector3(0.13, 0.13, 0.001))


func test_an_enemy_keeps_its_kind_and_health_through_packing() -> void:
	for kind in Content.enemy_ids.size():
		for health: float in [0.0, 0.004, 0.5, 1.0]:
			var entities := {1: Vector3(0, 0, Net.enemy_z(kind, health))}
			var z: float = (
				Net.unpack_entities(Net.pack_entities(entities, Vector2.ZERO), Vector2.ZERO)[1].z
			)
			assert_int(Net.enemy_kind(z)).is_equal(kind)
			assert_float(Net.enemy_health(z)).is_equal_approx(health, 0.005)
			assert_bool(Net.enemy_slowed(z)).is_false()
			var slowed: float = (
				Net
				. unpack_entities(
					Net.pack_entities(
						{1: Vector3(0, 0, Net.enemy_z(kind, health, true))}, Vector2.ZERO
					),
					Vector2.ZERO
				)[1]
				. z
			)
			assert_int(Net.enemy_kind(slowed)).is_equal(kind)
			assert_float(Net.enemy_health(slowed)).is_equal_approx(health, 0.01)
			assert_bool(Net.enemy_slowed(slowed)).is_true()


func test_a_facing_survives_its_byte() -> void:
	for angle: float in [0.0, 0.01, 1.0, PI, -PI, -0.5, TAU - 0.002, 5.0]:
		var back := Net.facing_angle(Net.facing_byte(angle))
		assert_float(absf(angle_difference(angle, back))).is_less_equal(TAU / 512 + 0.0001)


func test_facings_go_only_with_shields_in_enemy_order() -> void:
	var shield := Content.enemy_ids.find(&"shield_draugr")
	var plain := Content.enemy_ids.find(&"draugr")
	var enemies := {
		4: Vector3(0, 0, Net.enemy_z(plain, 1.0)),
		9: Vector3(5, 0, Net.enemy_z(shield, 0.5, true)),
		2: Vector3(9, 0, Net.enemy_z(shield, 1.0)),
	}
	var bytes := Net.pack_facings(enemies, {9: -1.0, 2: 3.0})
	assert_int(bytes.size()).is_equal(2)
	var unpacked := Net.unpack_entities(Net.pack_entities(enemies, Vector2.ZERO), Vector2.ZERO)
	var back := Net.unpack_facings(unpacked, bytes)
	assert_array(back.keys()).contains_exactly_in_any_order([9, 2])
	assert_float(angle_difference(back[9], -1.0)).is_equal_approx(0.0, TAU / 512)
	assert_float(angle_difference(back[2], 3.0)).is_equal_approx(0.0, TAU / 512)
