extends SceneTree

func _initialize() -> void:
	_test_same_index_gives_same_stage()
	_test_stage_is_mirror_symmetric()
	_test_invariants_hold_for_first_hundred_stages()
	_test_no_gap_is_wider_than_the_curve_allows()
	_test_levers_arrive_on_schedule()
	print("test_stage_gen: OK")
	quit()

# 판 번호가 곧 시드다. 3판은 어느 기기에서 언제 시작해도 같은 3판이어야
# 테스트를 쓸 수 있고, 플레이어가 판을 기억할 수 있다.
func _test_same_index_gives_same_stage() -> void:
	for index in [0, 5, 17, 63]:
		var a := StageGen.stage(index)
		var b := StageGen.stage(index)
		assert(a.cells == b.cells, "같은 판 번호가 다른 배치를 냈다: %d" % index)
	assert(StageGen.stage(3).cells != StageGen.stage(4).cells,
		"판 번호가 달라도 배치가 같다 — 시드가 안 먹었다")

# 좌우 대칭이 없으면 난수가 그냥 잡음으로 보인다. 원작 판이 전부 대칭인 이유다.
func _test_stage_is_mirror_symmetric() -> void:
	for index in [0, 5, 12, 40]:
		var g := StageGen.stage(index)
		for row in Tuning.BRICK_ROWS:
			for col in Tuning.BRICK_COLS:
				var mirrored := Tuning.BRICK_COLS - 1 - col
				assert(g.get_cell(col, row) == g.get_cell(mirrored, row),
					"판 %d 의 (%d,%d) 가 거울짝과 다르다: %d vs %d" % [
						index, col, row,
						g.get_cell(col, row), g.get_cell(mirrored, row)])

# 클리어 가능성. 셋 다 구조로 보장되지만, 곡선을 손대면 조용히 깨진다.
func _test_invariants_hold_for_first_hundred_stages() -> void:
	for index in 101:
		var g := StageGen.stage(index)
		assert(g.remaining() >= 1, "판 %d 에 깰 수 있는 블럭이 없다" % index)
		for col in Tuning.BRICK_COLS:
			assert(g.get_cell(col, 0) != BrickGrid.INDESTRUCTIBLE,
				"판 %d 의 최하단 %d 열이 불괴다 — 위쪽이 봉인된다" % [index, col])
		var hard_walls := 0
		for c in g.cells:
			if c == BrickGrid.INDESTRUCTIBLE:
				hard_walls += 1
		assert(hard_walls <= StageGen.INDESTRUCTIBLE_MAX,
			"판 %d 의 불괴 블럭이 상한을 넘었다: %d" % [index, hard_walls])
		# 상한만 보면 0 개도 통과한다. 곡선이 약속한 수가 실제로 놓였는지 본다 —
		# 이 단언이 없으면 _place_indestructible 이 통째로 무동작이어도 초록불이다.
		assert(hard_walls == StageGen.indestructible_count(index),
			"판 %d 에 놓인 불괴 수가 곡선과 다르다: %d vs %d" % [
				index, hard_walls, StageGen.indestructible_count(index)])

# 레버 D. 빈칸이 좁아지지 않으면 밀도만 오르다가 어느 판부터 그냥 벽이 된다.
func _test_no_gap_is_wider_than_the_curve_allows() -> void:
	for index in 101:
		var g := StageGen.stage(index)
		var allowed := StageGen.max_gap(index)
		for row in Tuning.BRICK_ROWS:
			var run := 0
			for col in Tuning.BRICK_COLS:
				if g.get_cell(col, row) == 0:
					run += 1
					assert(run <= allowed,
						"판 %d 의 %d 줄에 빈칸이 %d 칸 이어졌다 (상한 %d)" % [
							index, row, run, allowed])
				else:
					run = 0

# 세 레버를 동시에 조이면 3판째에 벽에 부딪힌다. 순차로 들어와야 한다.
func _test_levers_arrive_on_schedule() -> void:
	assert(is_equal_approx(StageGen.density(0), 0.55),
		"첫 판 밀도가 55%% 가 아니다: %f" % StageGen.density(0))
	assert(is_equal_approx(StageGen.density(50), 0.90),
		"충분히 진행한 판의 밀도가 상한이 아니다: %f" % StageGen.density(50))
	assert(StageGen.density(50) > StageGen.density(0), "밀도가 안 오른다")

	for index in 3:
		var g := StageGen.stage(index)
		for c in g.cells:
			assert(c == 0 or c == 1, "판 %d(1~3판)에 단단 블럭이 나왔다: %d" % [index, c])
	assert(StageGen.hard_ratio(2) == 0.0, "판 3 에 단단 비율이 0 이 아니다")
	assert(StageGen.hard_ratio(50) > StageGen.hard_ratio(4),
		"단단 비율이 안 오른다")

	# 상한을 상수 자신과 비교하면 상수를 올려도 초록불이다. 설계 문서의 숫자를 못박는다.
	assert(StageGen.INDESTRUCTIBLE_MAX == 8,
		"설계가 정한 불괴 상한 8 이 바뀌었다: %d" % StageGen.INDESTRUCTIBLE_MAX)
	assert(StageGen.indestructible_count(6) == 0, "판 7 에 불괴 블럭이 나온다")
	assert(StageGen.indestructible_count(50) == StageGen.INDESTRUCTIBLE_MAX,
		"불괴 블럭이 상한에 안 닿는다: %d" % StageGen.indestructible_count(50))
	assert(StageGen.indestructible_count(50) % 2 == 0,
		"불괴 블럭 수가 홀수다 — 좌우 대칭으로 놓을 수 없다")

	assert(StageGen.max_gap(0) == 3, "첫 판 빈칸 상한이 3 이 아니다")
	assert(StageGen.max_gap(50) == 1, "빈칸 상한이 1 까지 안 좁아진다")
