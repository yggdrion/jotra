extends GdUnitTestSuite
## Net: snapshot entities survive packing to quarter pixels and half floats, enemies with their
## kind.


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
