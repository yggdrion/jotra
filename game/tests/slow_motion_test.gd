extends GdUnitTestSuite
## SlowMotion: the time scale goes back to 1 at the end, however late a frame reads it.


func test_slows_until_the_end_then_runs_normally() -> void:
	var slow := SlowMotion.new()
	assert_float(slow.scale_at(0)).is_equal(1.0)
	slow.start(0.02, 0.1, 1000)
	assert_float(slow.scale_at(1000)).is_equal(0.02)
	assert_float(slow.scale_at(1099)).is_equal(0.02)
	assert_float(slow.scale_at(1100)).is_equal(1.0)
	assert_float(slow.scale_at(99999)).is_equal(1.0)


func test_a_shorter_slowdown_does_not_cut_a_longer_one() -> void:
	var slow := SlowMotion.new()
	slow.start(0.3, 0.2, 1000)
	slow.start(0.02, 0.05, 1010)
	assert_float(slow.scale_at(1020)).is_equal(0.3)
	slow.start(0.02, 0.5, 1100)
	assert_float(slow.scale_at(1150)).is_equal(0.02)
	assert_float(slow.scale_at(1600)).is_equal(1.0)
