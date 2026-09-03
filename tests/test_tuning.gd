extends SceneTree

func _initialize() -> void:
	_test_v_min_reaches_bottom_row()
	_test_v_min_falls_short_of_second_row()
	_test_v_max_reaches_top()
	_test_geometry_is_consistent()
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

func _test_geometry_is_consistent() -> void:
	assert(Tuning.PADDLE_BAND_MAX_V < Tuning.BRICK_BOTTOM_V,
		"패들 밴드가 블럭 격자와 겹친다")
	assert(Tuning.BRICK_TOP_V < Tuning.BOARD_TOP_V, "블럭이 상단 벽을 넘는다")
	assert(is_equal_approx(Tuning.BRICK_TOP_V - Tuning.BRICK_BOTTOM_V,
		float(Tuning.BRICK_ROWS)), "블럭 격자 세로 길이와 줄 수가 어긋난다")
	assert(is_equal_approx(2.0 * Tuning.BOARD_HALF_WIDTH,
		float(Tuning.BRICK_COLS)), "판 폭과 열 수가 어긋난다")
	assert(Tuning.PADDLE_HALF_WIDTH < Tuning.BOARD_HALF_WIDTH,
		"패들이 판보다 넓다")
