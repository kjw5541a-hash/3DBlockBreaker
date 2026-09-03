extends SceneTree

func _initialize() -> void:
	_test_gravity_pulls_toward_player()
	_test_apex_matches_formula()
	_test_substeps_keep_step_under_radius()
	_test_wall_bounce_left_and_right()
	_test_top_wall_bounce()
	print("test_ball_integration: OK")
	quit()

func _test_gravity_pulls_toward_player() -> void:
	var v := BallPhysics.step_vel(Vector2(0.0, 10.0), 0.5)
	assert(v.y < 10.0, "중력이 v 를 줄이지 않는다: %s" % v)
	assert(is_equal_approx(v.y, 10.0 - Tuning.GRAVITY * 0.5), "중력 크기가 틀렸다: %s" % v)
	assert(is_equal_approx(v.x, 0.0), "중력이 u 를 건드렸다: %s" % v)

# 적분 결과가 v0^2/(2g) 공식과 맞는지 본다. 이게 어긋나면 Task 2 의
# 사거리 계약이 실제 게임에서는 성립하지 않는다.
func _test_apex_matches_formula() -> void:
	var dt := 1.0 / 120.0
	var pos := Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	var vel := Vector2(0.0, Tuning.v_min())
	var apex := pos.y
	for i in 2000:
		vel = BallPhysics.step_vel(vel, dt)
		pos = BallPhysics.step_pos(pos, vel, dt)
		apex = maxf(apex, pos.y)
		if vel.y < 0.0:
			break
	var expected := Tuning.PADDLE_BAND_MIN_V + Tuning.v_min() * Tuning.v_min() / (2.0 * Tuning.GRAVITY)
	# 세미암시적 오일러는 도달 높이를 약 v0·dt/2 만큼 낮게 잡는다. 원인을
	# 아는 오차라 그 두 배까지만 허용한다 — 그냥 큰 수를 넣어 눈감는 것과
	# 다르다. 위로 넘어가면 적분이 에너지를 만들어내고 있다는 뜻이다.
	assert(apex <= expected + 0.001,
		"적분이 공식보다 높이 올라간다 — 에너지가 늘어난다: %f vs %f" % [apex, expected])
	assert(expected - apex < Tuning.v_min() * dt,
		"적분 도달 높이가 공식과 너무 어긋난다: %f vs %f" % [apex, expected])

func _test_substeps_keep_step_under_radius() -> void:
	var dt := 1.0 / 120.0
	var n := BallPhysics.substeps(Tuning.V_MAX, dt)
	var per_step := Tuning.V_MAX * dt / float(n)
	assert(per_step <= Tuning.BALL_RADIUS + 0.0001,
		"서브스텝을 나눠도 한 스텝이 반지름보다 크다: %f" % per_step)
	assert(BallPhysics.substeps(0.0, dt) >= 1, "서브스텝은 최소 1이어야 한다")

func _test_wall_bounce_left_and_right() -> void:
	var lim := Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS
	var r := BallPhysics.resolve_walls(Vector2(-lim - 0.5, 5.0), Vector2(-8.0, 3.0))
	assert(is_equal_approx(r[0].x, -lim), "왼쪽 벽에서 위치가 안 밀려났다: %s" % r[0])
	assert(r[1].x > 0.0, "왼쪽 벽에서 안 튕겼다: %s" % r[1])
	assert(is_equal_approx(r[1].y, 3.0), "벽이 v 속도를 건드렸다: %s" % r[1])
	var r2 := BallPhysics.resolve_walls(Vector2(lim + 0.5, 5.0), Vector2(8.0, 3.0))
	assert(r2[1].x < 0.0, "오른쪽 벽에서 안 튕겼다: %s" % r2[1])

func _test_top_wall_bounce() -> void:
	var top := Tuning.BOARD_TOP_V - Tuning.BALL_RADIUS
	var r := BallPhysics.resolve_walls(Vector2(0.0, top + 0.5), Vector2(2.0, 9.0))
	assert(is_equal_approx(r[0].y, top), "상단 벽에서 위치가 안 밀려났다: %s" % r[0])
	assert(r[1].y < 0.0, "상단 벽에서 안 튕겼다: %s" % r[1])
	# 벽은 에너지를 잃지 않는다. 손실원은 패들 하나뿐이다.
	assert(absf(r[1].length() - Vector2(2.0, 9.0).length()) < 0.0001,
		"벽이 에너지를 먹었다: %f" % r[1].length())
