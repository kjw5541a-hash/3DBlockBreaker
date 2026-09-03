extends SceneTree

func _initialize() -> void:
	_test_reflect_off_flat_paddle()
	_test_reflect_preserves_speed()
	_test_clamp_speed_raises_and_caps()
	_test_clamp_speed_on_zero_vector()
	_test_min_angle_lifts_near_horizontal()
	_test_min_angle_leaves_steep_alone()
	print("test_ball_physics: OK")
	quit()

func _test_reflect_off_flat_paddle() -> void:
	var up := Vector2(0.0, 1.0)
	var out := BallPhysics.reflect(Vector2(1.0, -1.0), up)
	assert(out.is_equal_approx(Vector2(1.0, 1.0)), "평평한 패들 반사가 틀렸다: %s" % out)

func _test_reflect_preserves_speed() -> void:
	var n := Vector2(0.3, 1.0).normalized()
	var v := Vector2(2.0, -7.0)
	var out := BallPhysics.reflect(v, n)
	assert(absf(out.length() - v.length()) < 0.0001,
		"반사가 속력을 바꿨다: %f -> %f" % [v.length(), out.length()])

func _test_clamp_speed_raises_and_caps() -> void:
	var slow := BallPhysics.clamp_speed(Vector2(0.0, 3.0), 10.0, 30.0)
	assert(absf(slow.length() - 10.0) < 0.0001, "하한으로 못 올렸다: %f" % slow.length())
	assert(slow.normalized().is_equal_approx(Vector2(0.0, 1.0)), "방향이 바뀌었다")
	var fast := BallPhysics.clamp_speed(Vector2(0.0, 99.0), 10.0, 30.0)
	assert(absf(fast.length() - 30.0) < 0.0001, "상한을 안 물었다: %f" % fast.length())

func _test_clamp_speed_on_zero_vector() -> void:
	# 0 벡터는 방향이 없다. 그대로 두면 공이 죽으므로 위로 세운다.
	var out := BallPhysics.clamp_speed(Vector2.ZERO, 10.0, 30.0)
	assert(absf(out.length() - 10.0) < 0.0001, "0 벡터에서 하한이 안 나왔다")
	assert(out.y > 0.0, "0 벡터는 위로 세워야 한다: %s" % out)

func _test_min_angle_lifts_near_horizontal() -> void:
	var v := Vector2(20.0, 0.2)
	var out := BallPhysics.enforce_min_angle(v, 15.0)
	var deg := absf(rad_to_deg(asin(out.y / out.length())))
	assert(deg >= 14.99, "최소각까지 못 세웠다: %f도" % deg)
	assert(absf(out.length() - v.length()) < 0.0001, "속력이 바뀌었다")
	assert(out.x > 0.0 and out.y > 0.0, "부호가 뒤집혔다: %s" % out)

func _test_min_angle_leaves_steep_alone() -> void:
	var v := Vector2(1.0, -20.0)
	var out := BallPhysics.enforce_min_angle(v, 15.0)
	assert(out.is_equal_approx(v), "이미 충분히 가파른데 건드렸다: %s" % out)
