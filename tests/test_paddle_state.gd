extends SceneTree

func _initialize() -> void:
	_test_follows_finger_sideways()
	_test_forward_push_is_slower_than_sideways()
	_test_stays_inside_band_and_walls()
	_test_tilt_follows_sideways_velocity()
	_test_normal_points_toward_swing_direction()
	_test_contact_normal_aims_when_still()
	_test_velocity_is_smoothed()
	_test_swept_rect_covers_previous_position()
	_test_paddle_starts_at_the_top_of_the_band()
	_test_spring_speed_scales_with_pull_depth()
	_test_spring_rises_at_constant_speed_ignoring_the_finger()
	_test_spring_ends_at_home()
	_test_touching_cancels_the_spring()
	_test_spring_velocity_ignores_the_downward_drag()
	print("test_paddle_state: OK")
	quit()

const DT := 1.0 / 120.0

func _test_follows_finger_sideways() -> void:
	var p := PaddleState.new(0.0)
	# 판 밖을 목표로 주면 클램프에 걸려 테스트가 조작 자체를 못 본다.
	var goal := Tuning.BOARD_HALF_WIDTH * 0.5
	for i in 60:
		p.update(Vector2(goal, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(absf(p.pos.x - goal) < 0.01, "손가락을 못 따라갔다: %f" % p.pos.x)

func _test_forward_push_is_slower_than_sideways() -> void:
	var a := PaddleState.new(0.0)
	var b := PaddleState.new(0.0)
	a.update(Vector2(5.0, Tuning.PADDLE_BAND_MAX_V), DT)
	b.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var moved_u := absf(a.pos.x)
	var moved_v := absf(b.pos.y - Tuning.PADDLE_BAND_MAX_V)
	assert(moved_u > moved_v,
		"앞으로 밀기가 좌우보다 느려야 한다: u=%f v=%f" % [moved_u, moved_v])
	assert(moved_u <= Tuning.PADDLE_MAX_SPEED_U * DT + 0.0001, "좌우 상한을 넘었다")
	assert(moved_v <= Tuning.PADDLE_MAX_SPEED_V * DT + 0.0001, "앞뒤 상한을 넘었다")

func _test_stays_inside_band_and_walls() -> void:
	var p := PaddleState.new(0.0)
	for i in 300:
		p.update(Vector2(99.0, 99.0), DT)
	assert(p.pos.y <= Tuning.PADDLE_BAND_MAX_V + 0.0001, "밴드 위로 나갔다: %f" % p.pos.y)
	assert(p.pos.x + p.half_width <= Tuning.BOARD_HALF_WIDTH + 0.0001,
		"패들이 벽을 뚫었다: %f" % p.pos.x)
	for i in 300:
		p.update(Vector2(-99.0, -99.0), DT)
	assert(p.pos.y >= Tuning.PADDLE_BAND_MIN_V - 0.0001, "밴드 아래로 나갔다: %f" % p.pos.y)
	assert(p.pos.x - p.half_width >= -Tuning.BOARD_HALF_WIDTH - 0.0001, "왼쪽 벽을 뚫었다")

func _test_tilt_follows_sideways_velocity() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(p.tilt_deg > 0.0, "오른쪽으로 휘두르는데 기울기가 0 이하: %f" % p.tilt_deg)
	assert(p.tilt_deg <= Tuning.PADDLE_MAX_TILT_DEG + 0.0001,
		"최대 기울기를 넘었다: %f" % p.tilt_deg)

func _test_normal_points_toward_swing_direction() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var n := p.normal()
	assert(n.x > 0.0, "오른쪽으로 휘둘렀는데 법선이 오른쪽을 안 본다: %s" % n)
	assert(n.y > 0.0, "법선이 블럭 쪽을 안 본다: %s" % n)
	assert(is_equal_approx(n.length(), 1.0), "법선이 단위벡터가 아니다")

func _test_contact_normal_aims_when_still() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(absf(p.tilt_deg) < 0.001, "정지 상태인데 기울어져 있다: %f" % p.tilt_deg)
	# 정지 상태에서도 접촉점으로 좌우를 겨눌 수 있어야 한다.
	var right := p.contact_normal(p.pos.x + p.half_width)
	var left := p.contact_normal(p.pos.x - p.half_width)
	assert(right.x > 0.1, "패들 오른쪽 끝에 맞았는데 오른쪽으로 안 간다: %s" % right)
	assert(left.x < -0.1, "패들 왼쪽 끝에 맞았는데 왼쪽으로 안 간다: %s" % left)
	var center := p.contact_normal(p.pos.x)
	assert(absf(center.x) < 0.001, "정중앙은 수직이어야 한다: %s" % center)

func _test_velocity_is_smoothed() -> void:
	var p := PaddleState.new(0.0)
	# 한 프레임만 크게 튀는 지터. 평활 없이는 그대로 공에 실린다.
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var raw := (p.pos.x - p.prev_pos.x) / DT
	assert(p.vel.x < raw * 0.9,
		"한 프레임 지터가 그대로 속도가 됐다: vel=%f raw=%f" % [p.vel.x, raw])

func _test_swept_rect_covers_previous_position() -> void:
	var p := PaddleState.new(-3.0)
	# 10 프레임이면 아직 목표에도 벽에도 못 닿아 계속 움직이는 중이다.
	# 멈춘 뒤에 재면 스윕 상자가 정지 상자와 같아져 아무것도 안 잰다.
	for i in 10:
		p.update(Vector2(3.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var swept := p.swept_rect()
	assert(swept.has_point(p.prev_pos), "스윕 상자가 이전 위치를 안 덮는다")
	assert(swept.has_point(p.pos), "스윕 상자가 현재 위치를 안 덮는다")
	assert(swept.size.x > p.rect().size.x, "움직이는 중인데 스윕 상자가 정지 상자와 같다")

# --- 스프링 조작. 기본 위치는 밴드 위끝이고, 끌어내렸다 놓으면 그 깊이에
# --- 비례한 속도로 등속 상승한다.

func _test_paddle_starts_at_the_top_of_the_band() -> void:
	var p := PaddleState.new(0.0)
	assert(is_equal_approx(p.pos.y, Tuning.PADDLE_BAND_MAX_V),
		"패들 기본 위치가 밴드 위끝이 아니다: %f" % p.pos.y)

# 깊이가 곧 파워다. 등속이면서 크기까지 매번 같으면, 깊게 당길수록 더
# 낮은 곳에서 쏘게 되어 당기는 것이 손해만 된다.
func _test_spring_speed_scales_with_pull_depth() -> void:
	var shallow := PaddleState.new(0.0)
	shallow.pos.y = Tuning.PADDLE_BAND_MAX_V - 0.2
	shallow.start_spring()
	shallow.update(Vector2.ZERO, DT)
	var deep := PaddleState.new(0.0)
	deep.pos.y = Tuning.PADDLE_BAND_MIN_V
	deep.start_spring()
	deep.update(Vector2.ZERO, DT)
	assert(deep.vel.y > shallow.vel.y,
		"깊게 당겼는데 복귀가 더 안 빠르다: %f vs %f" % [deep.vel.y, shallow.vel.y])
	# 이 상한을 넘으면 공이 v_max 에 잘려 자기를 친 패들보다 느려진다 —
	# 그러면 패들이 공을 추월해 메시를 뚫고 지나간다.
	assert(deep.vel.y <= Tuning.V_MAX_START + 0.0001,
		"풀당김 복귀 속도가 공 속도 상한을 넘었다: %f" % deep.vel.y)

func _test_spring_rises_at_constant_speed_ignoring_the_finger() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	assert(p.springing(), "스프링을 걸었는데 스프링 중이 아니다")
	var first := 0.0
	for i in 3:
		var before := p.pos.y
		# 손가락은 아직 아래를 가리키고 있다. 스프링은 타깃을 무시해야 한다.
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		var moved := p.pos.y - before
		assert(moved > 0.0, "스프링 중인데 안 올라간다: %f" % moved)
		if i == 0:
			first = moved
		assert(is_equal_approx(moved, first),
			"복귀가 등속이 아니다: %f vs %f" % [moved, first])

func _test_spring_ends_at_home() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	for i in 300:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MAX_V), DT)
		if not p.springing():
			break
	assert(not p.springing(), "300 프레임을 돌려도 스프링이 안 끝났다")
	assert(is_equal_approx(p.pos.y, Tuning.PADDLE_BAND_MAX_V),
		"스프링이 끝났는데 홈이 아니다: %f" % p.pos.y)

func _test_touching_cancels_the_spring() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	p.cancel_spring()
	assert(not p.springing(), "터치했는데 스프링이 안 풀렸다")
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(is_equal_approx(p.pos.y, Tuning.PADDLE_BAND_MIN_V),
		"스프링을 풀었는데 여전히 올라간다: %f" % p.pos.y)

# 평활 표본에는 손가락을 끌어내리던 아래 방향 속도가 들어 있다. 그대로
# 두면 릴리즈 직후 한두 프레임 동안 평균이 파워를 깎거나 부호를 뒤집는데,
# 공은 바로 그 프레임에 맞는다.
func _test_spring_velocity_ignores_the_downward_drag() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(p.vel.y < 0.0, "끌어내리는 중인데 속도가 위를 향한다 — 테스트가 헛돈다")
	var pulled_to := p.pos.y
	p.start_spring()
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(p.vel.y > 0.0, "스프링 첫 프레임인데 속도가 아직 아래를 향한다: %f" % p.vel.y)
	var span := Tuning.PADDLE_BAND_MAX_V - Tuning.PADDLE_BAND_MIN_V
	var t := clampf((Tuning.PADDLE_BAND_MAX_V - pulled_to) / span, 0.0, 1.0)
	var expected := lerpf(Tuning.PADDLE_RETURN_SPEED_MIN,
		Tuning.PADDLE_RETURN_SPEED_MAX, t)
	assert(is_equal_approx(p.vel.y, expected),
		"첫 프레임 속도가 스프링 속도와 다르다: %f vs %f" % [p.vel.y, expected])
