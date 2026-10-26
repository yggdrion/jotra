extends GdUnitTestSuite
## Net: snapshot entities survive packing to quarter pixels and half floats.


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
