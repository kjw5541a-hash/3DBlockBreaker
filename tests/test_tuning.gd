extends SceneTree

func _initialize() -> void:
	_test_v_min_reaches_bottom_row()
	_test_v_min_falls_short_of_second_row()
	_test_v_max_reaches_top()
	_test_speed_cap_ramps_with_time()
	_test_geometry_is_consistent()
	_test_home_is_the_middle_of_the_band()
	_test_edge_hits_are_weaker_than_centered_ones()
	print("test_tuning: OK")
	quit()

# 패들 밴드 아래끝에서 수직 발사한 공이 도달하는 v. v0^2 / (2g) 만큼 오른다.
func _apex(v0: float) -> float:
	return Tuning.PADDLE_BAND_MIN_V + v0 * v0 / (2.0 * Tuning.GRAVITY)

func _test_v_min_reaches_bottom_row() -> void:
	var apex := _apex(Tuning.v_min())
	assert(apex >= Tuning.BRICK_BOTTOM_V - 0.001,
		"V_MIN 이 최하단 블럭 줄에 못 닿는다: apex=%f" % apex)

func _test_v_min_falls_short_of_second_row() -> void:
	# 하한만으로 둘째 줄까지 닿으면 미는 이유가 사라진다.
	var apex := _apex(Tuning.v_min())
	assert(apex < Tuning.BRICK_BOTTOM_V + 1.0,
		"V_MIN 만으로 둘째 줄까지 닿는다: apex=%f" % apex)

func _test_v_max_reaches_top() -> void:
	var apex := _apex(Tuning.V_MAX)
	assert(apex >= Tuning.BOARD_TOP_V,
		"최대 속도로도 상단 벽에 못 닿는다: apex=%f" % apex)

# 잘 맞은 공의 상한만 시간에 따라 오른다. 초반부터 34 면 손댈 수 없다.
func _test_speed_cap_ramps_with_time() -> void:
	assert(is_equal_approx(Tuning.v_max_at(0.0), Tuning.V_MAX_START),
		"시작 상한이 V_MAX_START 가 아니다: %f" % Tuning.v_max_at(0.0))
	assert(is_equal_approx(Tuning.v_max_at(Tuning.V_MAX_RAMP_SEC), Tuning.V_MAX),
		"램프가 끝나도 V_MAX 에 안 닿는다: %f" % Tuning.v_max_at(Tuning.V_MAX_RAMP_SEC))
	assert(is_equal_approx(Tuning.v_max_at(Tuning.V_MAX_RAMP_SEC * 10.0), Tuning.V_MAX),
		"램프가 V_MAX 를 넘어간다: %f" % Tuning.v_max_at(Tuning.V_MAX_RAMP_SEC * 10.0))
	var prev := Tuning.v_max_at(0.0)
	for i in range(1, 10):
		var now := Tuning.v_max_at(Tuning.V_MAX_RAMP_SEC * float(i) / 10.0)
		assert(now > prev, "상한이 시간에 따라 안 오른다: %f -> %f" % [prev, now])
		prev = now
	assert(Tuning.V_MAX_START > Tuning.v_min(),
		"시작 상한이 발사 속도보다 낮다")
	# 초반에도 판 전체를 쓸 수 있어야 한다 — 안 그러면 위쪽 줄이 잠긴다.
	assert(_apex(Tuning.V_MAX_START) >= Tuning.BOARD_TOP_V,
		"시작 상한으로 상단 벽에 못 닿는다: apex=%f" % _apex(Tuning.V_MAX_START))

func _test_geometry_is_consistent() -> void:
	assert(Tuning.PADDLE_BAND_MAX_V < Tuning.BRICK_BOTTOM_V,
		"패들 밴드가 블럭 격자와 겹친다")
	assert(Tuning.BRICK_TOP_V < Tuning.BOARD_TOP_V, "블럭이 상단 벽을 넘는다")
	assert(is_equal_approx(Tuning.BRICK_TOP_V - Tuning.BRICK_BOTTOM_V,
		float(Tuning.BRICK_ROWS) * BrickGrid.CELL_H),
		"블럭 격자 세로 길이와 줄 수가 어긋난다")
	assert(is_equal_approx(2.0 * Tuning.BOARD_HALF_WIDTH,
		float(Tuning.BRICK_COLS) * BrickGrid.CELL_W), "판 폭과 열 수가 어긋난다")
	# 공이 셀보다 크면 격자 사이로 못 지나가고 반사가 이상해진다.
	assert(Tuning.BALL_RADIUS * 2.0 < BrickGrid.CELL_W,
		"공이 블럭 한 칸보다 넓다: %f vs %f" % [Tuning.BALL_RADIUS * 2.0, BrickGrid.CELL_W])
	assert(Tuning.PADDLE_HALF_WIDTH < Tuning.BOARD_HALF_WIDTH,
		"패들이 판보다 넓다")

# 기본 위치가 밴드 한가운데여야 위로도 아래로도 같은 만큼 움직인다.
# 홈이 한쪽에 붙어 있으면 그쪽 여유가 없어 스프링이 대칭으로 안 흔들린다.
func _test_home_is_the_middle_of_the_band() -> void:
	var down := Tuning.PADDLE_HOME_V - Tuning.PADDLE_BAND_MIN_V
	var up := Tuning.PADDLE_BAND_MAX_V - Tuning.PADDLE_HOME_V
	assert(is_equal_approx(down, up),
		"홈이 밴드 한가운데가 아니다: 아래 %f 위 %f" % [down, up])

# 스윗스팟. 정확히 가운데로 받으면 손해가 없고, 가장자리로 스치면 깎인다.
func _test_edge_hits_are_weaker_than_centered_ones() -> void:
	assert(Tuning.PADDLE_RESTITUTION_EDGE < Tuning.PADDLE_RESTITUTION,
		"가장자리 반발이 가운데보다 약하지 않다")
	# 1.0 을 넘으면 받을 때마다 에너지가 늘어 "손실원은 패들뿐"이 무너진다.
	assert(Tuning.PADDLE_RESTITUTION <= 1.0, "가운데 반발이 1.0 을 넘는다")
