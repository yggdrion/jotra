extends GdUnitTestSuite
## Interpolation.sample between buffered snapshots.

var _snapshots: Array = [
	{ms = 100, players = {1: Vector2(0, 0)}},
	{ms = 200, players = {1: Vector2(10, 0), 2: Vector2(50, 50)}},
]


func test_blends_between_snapshots() -> void:
	assert_vector(Interpolation.sample(_snapshots, 150)[1]).is_equal(Vector2(5, 0))


func test_holds_newest_after_buffer() -> void:
	assert_vector(Interpolation.sample(_snapshots, 900)[1]).is_equal(Vector2(10, 0))


func test_holds_oldest_before_buffer() -> void:
	assert_vector(Interpolation.sample(_snapshots, 0)[1]).is_equal(Vector2(0, 0))


func test_new_entity_shows_at_newer_position() -> void:
	assert_vector(Interpolation.sample(_snapshots, 150)[2]).is_equal(Vector2(50, 50))


func test_blends_another_key_of_vector3() -> void:
	var snapshots := [
		{ms = 100, enemies = {7: Vector3(0, 0, 1)}},
		{ms = 200, enemies = {7: Vector3(10, 0, 0.5)}},
	]
	var at: Vector3 = Interpolation.sample(snapshots, 150, "enemies")[7]
	assert_vector(at).is_equal(Vector3(5, 0, 0.75))


func test_empty_buffer_is_empty() -> void:
	assert_dict(Interpolation.sample([], 0)).is_empty()
