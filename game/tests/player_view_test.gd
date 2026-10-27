extends GdUnitTestSuite
## PlayerView's swing animation: the sweep through the arc, alternating lights, heavy pull-back.


func test_a_swing_sweeps_the_arc_and_ends_at_its_far_edge() -> void:
	var view: PlayerView = auto_free(PlayerView.new())
	var move := Content.tuning.fists_light
	view.swing(Vector2.RIGHT, move)
	var half := deg_to_rad(move.arc) / 2
	# Light swings alternate the side they start from; this one went the second way.
	var way := signf(view._sweep(1.0))
	assert_float(absf(view._sweep(0.0))).is_equal_approx(half, 0.001)
	assert_float(view._sweep(1.0) * way).is_equal_approx(half, 0.001)
	assert_float(view._sweep(0.0) * way).is_less(0.0)
	view.swing(Vector2.RIGHT, move)
	assert_float(signf(view._sweep(1.0))).is_equal(-way)


func test_a_heavy_pulls_back_before_it_sweeps() -> void:
	var view: PlayerView = auto_free(PlayerView.new())
	var move := Content.tuning.fists_heavy
	assert_float(move.pull_back).is_greater(0.0)
	view.swing(Vector2.RIGHT, move)
	var half := deg_to_rad(move.arc) / 2
	assert_float(view._sweep(0.0)).is_equal_approx(-half, 0.001)
	assert_float(view._sweep(move.pull_back)).is_less(-half)
	assert_float(view._sweep(1.0)).is_equal_approx(half, 0.001)


func test_swing_progress_is_negative_without_a_swing() -> void:
	var view: PlayerView = auto_free(PlayerView.new())
	assert_float(view.swing_progress()).is_less(0.0)
	view.swing(Vector2.RIGHT, Content.tuning.fists_light)
	assert_float(view.swing_progress()).is_between(0.0, 1.0)


func test_enemy_poses_follow_its_telegraph_and_death() -> void:
	var view: EnemyView = auto_free(EnemyView.new())
	view.def = Content.tuning.enemy
	var now := Time.get_ticks_msec()
	view.windup(1.0, 30.0)
	view._pose(now + 900)
	assert_vector(view.pose_scale).is_not_equal(Vector2.ONE)
	view.stagger()
	view._pose(Time.get_ticks_msec() + 40)
	assert_float(view.pose_rot).is_not_equal(0.0)
	view.strike()
	view._pose(Time.get_ticks_msec() + 70)
	assert_float(view.pose_offset.length()).is_greater(0.0)
	assert_bool(view.dying).is_false()
	view.die()
	view._pose(Time.get_ticks_msec() + 200)
	assert_float(view.pose_alpha).is_between(0.0, 1.0)
	assert_bool(view.dying).is_true()
