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
	_test_paddle_starts_at_the_middle_of_the_band()
	_test_spring_accelerates_instead_of_moving_at_a_constant_speed()
	_test_peak_speed_scales_with_pull_depth()
	_test_spring_overshoots_past_home_but_stays_in_the_band()
	_test_spring_settles_back_at_home()
	_test_touching_cancels_the_spring()
	_test_spring_velocity_ignores_the_downward_drag()
	_test_the_ball_separates_at_the_paddles_fastest_moment()
	_test_restitution_peaks_at_the_paddle_center()
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
	a.update(Vector2(5.0, Tuning.PADDLE_HOME_V), DT)
	b.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var moved_u := absf(a.pos.x)
	var moved_v := absf(b.pos.y - Tuning.PADDLE_HOME_V)
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

# --- 스프링 조작. 기본 위치는 밴드 한가운데다. 끌어내렸다 놓으면 진짜
# --- 용수철처럼 가속하며 올라와 홈을 지나 위로 넘어갔다가 되돌아온다.

func _test_paddle_starts_at_the_middle_of_the_band() -> void:
	var p := PaddleState.new(0.0)
	assert(is_equal_approx(p.pos.y, Tuning.PADDLE_HOME_V),
		"패들 기본 위치가 밴드 한가운데가 아니다: %f" % p.pos.y)

# 등속이 아니라 가속이다. 용수철은 늘어난 만큼 당기므로 홈에서 멀수록
# 세게 밀고, 홈에 가까울수록 힘이 준다.
func _test_spring_accelerates_instead_of_moving_at_a_constant_speed() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	assert(p.springing(), "스프링을 걸었는데 스프링 중이 아니다")
	var prev := 0.0
	for i in 4:
		var before := p.pos.y
		# 손가락은 아직 아래를 가리키고 있다. 스프링은 타깃을 무시해야 한다.
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		var moved := p.pos.y - before
		assert(moved > prev + 0.00001,
			"스프링이 가속을 안 한다 (등속이거나 멈췄다): %f -> %f" % [prev, moved])
		prev = moved

# 깊이가 곧 파워다. 최고 속도는 홈을 지날 때 나오고, 그 값이 곧 발사 속도다.
func _test_peak_speed_scales_with_pull_depth() -> void:
	var shallow := _peak_spring_speed(Tuning.PADDLE_HOME_V - 0.3)
	var deep := _peak_spring_speed(Tuning.PADDLE_BAND_MIN_V)
	assert(deep > shallow + 1.0,
		"깊게 당겼는데 더 안 빠르다: %f vs %f" % [deep, shallow])
	# 이 상한을 넘으면 공이 v_max 에 잘려 자기를 친 패들보다 느려진다 —
	# 그러면 패들이 공을 추월해 메시를 뚫고 지나간다.
	assert(deep <= Tuning.V_MAX_START + 0.0001,
		"풀당김 최고 속도가 공 속도 상한을 넘었다: %f" % deep)

func _peak_spring_speed(pull_v: float) -> float:
	var p := PaddleState.new(0.0)
	p.pos.y = pull_v
	p.start_spring()
	var peak := 0.0
	for i in 300:
		p.update(Vector2(0.0, pull_v), DT)
		peak = maxf(peak, p.vel.y)
	return peak

# 용수철은 홈에서 안 멈춘다 — 관성으로 넘어갔다가 돌아온다. 넘어가되
# 밴드 밖으로는 안 나간다.
func _test_spring_overshoots_past_home_but_stays_in_the_band() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	var top := p.pos.y
	for i in 300:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		top = maxf(top, p.pos.y)
	assert(top > Tuning.PADDLE_HOME_V + 0.05,
		"홈에서 그냥 멈췄다 — 용수철이 아니다: %f" % top)
	assert(top <= Tuning.PADDLE_BAND_MAX_V + 0.0001,
		"오버슈트가 밴드를 넘었다: %f" % top)

func _test_spring_settles_back_at_home() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	for i in 600:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if not p.springing():
			break
	assert(not p.springing(), "600 프레임(5초)을 돌려도 스프링이 안 끝났다")
	assert(is_equal_approx(p.pos.y, Tuning.PADDLE_HOME_V),
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
	p.start_spring()
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(p.vel.y > 0.0, "스프링 첫 프레임인데 속도가 아직 아래를 향한다: %f" % p.vel.y)
	assert(is_equal_approx(p.vel.y, (p.pos.y - p.prev_pos.y) / DT),
		"스프링 중 세로 속도가 실제 이동과 다르다 — 평활이 아직 끼어든다: %f" % p.vel.y)

# 패들에 얹힌 공이 떨어져 나가는 순간. 용수철이 중력보다 세게 잡아당기기
# 시작하면 패들이 공보다 빠르게 감속하므로 공은 그대로 날아간다. 감쇠가
# 있어 그 지점은 홈보다 조금 아래인데, 중요한 것은 높이가 아니라 그때가
# 패들이 가장 빠른 순간이라는 것이다 — 그 속도가 그대로 발사 속도가 된다.
func _test_the_ball_separates_at_the_paddles_fastest_moment() -> void:
	var p := PaddleState.new(0.0)
	p.pos.y = Tuning.PADDLE_BAND_MIN_V
	p.start_spring()
	assert(not p.separating(), "아직 올라오지도 않았는데 분리 신호가 떴다")
	var sep_vel := 0.0
	var peak := 0.0
	for i in 300:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		peak = maxf(peak, p.vel.y)
		if sep_vel == 0.0 and p.separating():
			sep_vel = p.vel.y
	assert(sep_vel > 0.0, "300 프레임을 돌려도 분리 신호가 안 떴다")
	assert(sep_vel >= peak * 0.95,
		"최고 속도를 한참 지나 쏜다: 분리 %f, 최고 %f" % [sep_vel, peak])

# 스윗스팟. 가운데로 정확히 받을수록 세게 튕기고, 가장자리로 스치면 깎인다.
func _test_restitution_peaks_at_the_paddle_center() -> void:
	var p := PaddleState.new(0.0)
	var center := p.restitution(p.pos.x)
	var edge := p.restitution(p.pos.x + p.half_width)
	var mid := p.restitution(p.pos.x + p.half_width * 0.5)
	assert(is_equal_approx(center, Tuning.PADDLE_RESTITUTION),
		"가운데 반발이 기준값이 아니다: %f" % center)
	assert(is_equal_approx(edge, Tuning.PADDLE_RESTITUTION_EDGE),
		"가장자리 반발이 기준값이 아니다: %f" % edge)
	assert(edge < mid and mid < center,
		"반발이 가운데에서 가장자리로 단조 감소하지 않는다: %f %f %f" % [center, mid, edge])
	# 패들 밖으로 나가도 가장자리 값으로 막아야 한다 — 안 그러면 스쳐 맞을 때
	# 반발이 음수가 되어 공이 패들 쪽으로 빨려 든다.
	assert(is_equal_approx(p.restitution(p.pos.x + p.half_width * 5.0),
		Tuning.PADDLE_RESTITUTION_EDGE), "패들 밖에서 반발이 안 잘린다")
