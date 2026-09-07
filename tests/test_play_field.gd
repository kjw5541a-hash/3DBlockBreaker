extends SceneTree

func _initialize() -> void:
	_test_passive_bounce_loses_energy()
	_test_decay_sequence_never_stops()
	_test_stall_costs_a_life()
	_test_swing_accelerates_ball()
	_test_early_game_caps_swing_speed()
	_test_tilted_swing_changes_direction()
	_test_paddle_never_double_bounces()
	_test_ball_below_zero_costs_a_life()
	_test_clearing_all_bricks_reports_cleared()
	_test_hard_brick_only_resets_stall_when_broken()
	_test_resting_ball_does_not_chip_a_brick_every_frame()
	_test_broken_list_carries_kind_before_the_destroying_hit()
	_test_next_stage_advances_without_resetting_the_speed_ramp()
	_test_reset_run_returns_to_the_first_stage()
	print("test_play_field: OK")
	quit()

const DT := 1.0 / 120.0

# _bounce_once 가 패들에 닿기 직전 프레임의 속력을 여기 남긴다. 공이
# 낙하하며 가속하므로 넣은 속도와 실제 접촉 속도가 다르다.
var _v_in_at_hit := 0.0

# 패들을 가만히 둔 채 공을 한 번 받게 하고, 받은 직후 속도를 돌려준다.
func _bounce_once(v_in: Vector2) -> Vector2:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = v_in
	for i in 240:
		_v_in_at_hit = f.ball_vel.length()
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			return f.ball_vel
		if r["lost"]:
			break
	assert(false, "패들에 안 맞았다")
	return Vector2.ZERO

# 가만히 받으면 반발계수만큼만 잃는다. 하한도 보정도 없다.
func _test_passive_bounce_loses_energy() -> void:
	var out := _bounce_once(Vector2(0.0, -Tuning.v_min()))
	var expected := _v_in_at_hit * Tuning.PADDLE_RESTITUTION
	# 접촉은 프레임 중간에 일어나 중력 한 프레임분(0.1)만큼 더 빠르다.
	assert(absf(out.length() - expected) < 0.15,
		"가만히 받은 속도가 반발계수와 안 맞는다: %f, 기대 %f" % [out.length(), expected])
	assert(out.y > 0.0, "받은 공이 위로 안 간다: %s" % out)

# 세게 친 공을 계속 가만히 받으면 도달 높이가 계속 줄어든다. 멈추는
# 지점이 없다 — 하한을 없앤 것이 이 게임의 감쇠 설계 전부다. 교착은
# 속도가 아니라 STALL_PADDLE_HITS 가 끝낸다.
func _test_decay_sequence_never_stops() -> void:
	var speeds: Array[float] = []
	var v := 30.0
	for i in 6:
		var out := _bounce_once(Vector2(0.0, -v))
		v = out.length()
		speeds.append(v)
	for i in range(1, 6):
		assert(speeds[i] < speeds[i - 1] - 0.1,
			"%d번째에서 감쇠가 멈췄다: %s" % [i, str(speeds)])
	assert(speeds[5] < Tuning.v_min(),
		"옛 하한 아래로 안 내려갔다 — 하한이 아직 살아 있다: %s" % str(speeds))

# 블럭을 못 깨고 패들에만 STALL_PADDLE_HITS 번 튕기면 목숨을 잃는다.
func _test_stall_costs_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	var before := f.lives
	var hits := 0
	var lost := false
	for i in 1200:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			hits += 1
		if r["lost"]:
			lost = true
			break
	assert(lost, "블럭을 못 깨고 계속 받기만 했는데 목숨을 안 잃었다")
	assert(hits == Tuning.STALL_PADDLE_HITS,
		"교착 판정이 %d번째가 아니라 %d번째에 났다" % [Tuning.STALL_PADDLE_HITS, hits])
	assert(f.lives == before - 1, "목숨이 안 줄었다: %d -> %d" % [before, f.lives])
	assert(f.paddle_hits_since_brick == 0, "다시 붙었는데 교착 카운터가 안 지워졌다")

func _test_swing_accelerates_ball() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	# 손가락을 앞으로 밀면서 받는다.
	for i in 240:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MAX_V), DT)
		if r["paddle_hit"]:
			break
	assert(f.ball_vel.length() > Tuning.v_min() + 1.0,
		"밀었는데 가속이 안 됐다: %f" % f.ball_vel.length())

func _test_tilted_swing_changes_direction() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	for i in 240:
		# 오른쪽으로 휘두르며 받는다. 목표를 계속 오른쪽으로 준다.
		var r := f.step(Vector2(f.paddle.pos.x + 1.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			break
	assert(f.ball_vel.x > 0.5,
		"오른쪽으로 휘둘렀는데 공이 오른쪽으로 안 간다: %s" % f.ball_vel)

func _test_paddle_never_double_bounces() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	f.ball_vel = Vector2(0.0, -1.0)
	var hits := 0
	# 하한이 없어진 뒤로는 느린 공이 0.13초쯤이면 진짜로 다시 떨어져 온다.
	# 창을 접촉이 이어지는 구간(0.067초)으로 좁혀야 이중 반사만 본다.
	for i in 8:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			hits += 1
	assert(hits == 1, "접촉이 이어지는 동안 여러 번 튕겼다: %d" % hits)

func _test_ball_below_zero_costs_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS, 0.2)
	f.ball_vel = Vector2(0.0, -20.0)
	var before := f.lives
	var lost := false
	for i in 60:
		if f.step(Vector2(-Tuning.BOARD_HALF_WIDTH, Tuning.PADDLE_BAND_MIN_V), DT)["lost"]:
			lost = true
			break
	assert(lost, "공이 데드존으로 나갔는데 lost 가 아니다")
	assert(f.lives == before - 1, "목숨이 안 줄었다: %d -> %d" % [before, f.lives])
	assert(f.attached, "공을 잃으면 패들에 다시 붙어야 한다")

func _test_clearing_all_bricks_reports_cleared() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.grid.cells[BrickGrid.index(5, 0)] = 1
	f.attached = false
	var r := BrickGrid.cell_rect(5, 0)
	f.ball_pos = Vector2(r.position.x + BrickGrid.CELL_W * 0.5, r.position.y - 0.3)
	f.ball_vel = Vector2(0.0, 8.0)
	var cleared := false
	for i in 60:
		if f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)["cleared"]:
			cleared = true
			break
	assert(cleared, "마지막 블럭을 깼는데 cleared 가 안 나온다")
	assert(f.grid.remaining() == 0, "블럭이 남아 있다")

# 초반에는 아무리 세게 밀어도 V_MAX_START 를 못 넘는다. 램프가 다 오른
# 뒤에는 그보다 빨라진다 — 같은 스윙, 다른 시각.
func _test_early_game_caps_swing_speed() -> void:
	var early := _max_swing_speed(0.0)
	var late := _max_swing_speed(Tuning.V_MAX_RAMP_SEC)
	# 공이 패들까지 떨어지는 몇 프레임 동안 램프도 조금 오른다.
	assert(early <= Tuning.V_MAX_START + 0.1,
		"초반인데 시작 상한을 넘었다: %f > %f" % [early, Tuning.V_MAX_START])
	assert(late > early + 1.0,
		"시간이 지나도 상한이 안 올랐다: %f -> %f" % [early, late])

# 경과 시간을 넣고, 최대 속도로 밀며 받은 직후 속력을 돌려준다.
func _max_swing_speed(elapsed: float) -> float:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.elapsed = elapsed
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MAX_V + 1.0)
	f.ball_vel = Vector2(0.0, -Tuning.V_MAX)
	for i in 240:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MAX_V), DT)
		if r["paddle_hit"]:
			return f.ball_vel.length()
	assert(false, "패들에 안 맞았다")
	return 0.0

# 단단 블럭을 툭툭 건드리는 것으로 교착 규칙을 피할 수 있으면 규칙이
# 아니라 요령이 된다. 리셋은 블럭이 실제로 깨졌을 때만이다.
func _test_hard_brick_only_resets_stall_when_broken() -> void:
	var f := PlayField.new()
	var r := BrickGrid.cell_rect(5, 0)
	var below := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS - 0.01)
	f.grid.cells[BrickGrid.index(5, 0)] = 2
	f.attached = false
	f.paddle_hits_since_brick = 2

	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	f.step(f.paddle.pos, 1.0 / 120.0)
	assert(f.grid.get_cell(5, 0) == 1,
		"단단 블럭이 한 대에 사라졌다: %d" % f.grid.get_cell(5, 0))
	assert(f.paddle_hits_since_brick == 2,
		"안 깨진 블럭이 교착 카운터를 리셋했다: %d" % f.paddle_hits_since_brick)

	# 실제 플레이라면 첫 히트 후 반사로 공이 멀어져 한동안 안 닿는 프레임이
	# 있었을 것이다 — 여기선 위치를 손으로 되돌리므로 그 "떠난 프레임"이
	# 없다. 디바운스가 이걸 "같은 접촉이 계속됨"으로 오인해 두 번째 히트를
	# 건너뛰지 않도록 직접 리셋해 별개의 타격임을 알린다.
	f._last_damaged = -1
	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	var out := f.step(f.paddle.pos, 1.0 / 120.0)
	assert(f.grid.get_cell(5, 0) == 0,
		"두 번째 히트에 안 깨졌다: %d" % f.grid.get_cell(5, 0))
	assert(f.paddle_hits_since_brick == 0,
		"깨졌는데 교착 카운터가 안 리셋됐다: %d" % f.paddle_hits_since_brick)
	assert(int(out["bricks_hit"]) == 1,
		"bricks_hit 이 깨진 개수를 안 센다: %d" % int(out["bricks_hit"]))

# out["bricks_hit"] 은 개수만 셀 뿐 무엇이 깨졌는지 말해주지 않는다.
# broken 은 col/row/kind 를 실어 나른다 — kind 는 hit() 이 칸 값을 깎기
# *직전*의 값이어야 한다. 마지막 히트는 이미 kind == 1 (남은 히트 1)인
# 상태에서 맞아 0 이 되므로, broken 에 기록될 값은 1 이다 — 3 이 아니다.
# 나중에 "원래 몇 히트짜리였는지 궁금하니 3으로 바꾸자"고 오해하지 말 것.
func _test_broken_list_carries_kind_before_the_destroying_hit() -> void:
	var f := PlayField.new()
	var r := BrickGrid.cell_rect(5, 0)
	var below := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS - 0.01)
	f.grid.fill_all(0)
	f.grid.cells[BrickGrid.index(5, 0)] = 1
	f.attached = false
	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	var out := f.step(f.paddle.pos, DT)
	assert(f.grid.get_cell(5, 0) == 0, "블럭이 안 깨졌다: %d" % f.grid.get_cell(5, 0))
	var broken: Array = out["broken"]
	assert(broken.size() == 1, "broken 항목 수가 틀렸다: %d" % broken.size())
	assert(int(broken[0]["col"]) == 5 and int(broken[0]["row"]) == 0,
		"broken 의 col/row 가 틀렸다: %s" % broken[0])
	assert(int(broken[0]["kind"]) == 1,
		"broken 의 kind 는 깎이기 직전 값(1)이어야 한다 — 원래 히트 수가 아니다: %d"
		% int(broken[0]["kind"]))

# 반지름보다 빠른 공은 한 스텝이 서브스텝 여러 개로 쪼개진다(57번째 줄
# substeps 참고). 수평 속도를 충분히 올리면 서브스텝이 2개가 되고, 수직
# 속도를 중력 한 킥의 절반보다 작게 주면 첫 서브스텝에서 맞고 튕긴 뒤
# 두 번째 서브스텝에서 또 같은 칸에 박힌다 — 두 서브스텝 사이엔 한
# 프레임치 반사-낙하 시간이 없어 진짜로 미스 없이 연속 히트가 난다.
# (0.4, 0.2) 처럼 느린 공은 서브스텝이 1개뿐이라 반사가 항상 다음
# "프레임"에 가서야 재충돌하고, 그 사이 최소 한 번은 미스가 끼어들어
# 디바운스가 있으나 없으나 결과가 같다 — 그래서 이 시나리오를 쓴다.
func _test_resting_ball_does_not_chip_a_brick_every_frame() -> void:
	var f := PlayField.new()
	var r := BrickGrid.cell_rect(5, 0)
	# 위 줄을 비워야 한다 — 안 비우면 공이 실제로는 row 1 블럭 위에 얹혀
	# 이 테스트가 겨냥한 블럭과 다른 블럭을 때린다.
	f.grid.fill_all(0)
	f.grid.cells[BrickGrid.index(5, 0)] = 3
	f.attached = false
	# 윗면 바로 위, 닿을 듯 말 듯한 높이에서 시작한다.
	f.ball_pos = Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y + r.size.y + Tuning.BALL_RADIUS)
	# 반지름/dt 의 1.2배 = 서브스텝 2개를 확실히 보장하는 수평 속도.
	# 수직 속도는 중력 한 킥(서브스텝 기준)의 1/4 — 0 과 킥의 절반 사이라
	# 두 서브스텝 다 파고들게 만드는 범위 한가운데다.
	f.ball_vel = Vector2(Tuning.BALL_RADIUS / DT * 1.2, Tuning.GRAVITY * DT / 4.0)
	for i in 6:
		f.step(f.paddle.pos, DT)
	assert(f.grid.get_cell(5, 0) >= 2,
		"같은 프레임 안에서 같은 칸을 두 번 이상 깎았다: %d" % f.grid.get_cell(5, 0))

# 판이 넘어가도 elapsed 는 이어진다. 판마다 0 으로 되돌리면 램프가 영원히
# 초반값에 머물러 난이도가 누적되지 않는다 — 100 판을 깨도 첫 판 속도다.
func _test_next_stage_advances_without_resetting_the_speed_ramp() -> void:
	var f := PlayField.new()
	f.elapsed = 42.0
	var before := f.grid.cells
	assert(f.stage_index == 0, "새 판이 0 판이 아니다: %d" % f.stage_index)
	f.next_stage()
	assert(f.stage_index == 1, "판 번호가 안 올랐다: %d" % f.stage_index)
	assert(is_equal_approx(f.elapsed, 42.0),
		"판이 넘어가며 속도 램프가 초기화됐다: %f" % f.elapsed)
	assert(f.grid.cells != before, "다음 판인데 배치가 그대로다")
	assert(f.grid.cells == StageGen.stage(1).cells, "1 판의 배치가 아니다")
	# 새 판 블럭 안에 공이 박힌 채로 시작하면 안 된다.
	assert(f.attached, "판이 넘어갔는데 공이 안 붙었다")

# 전멸하면 처음부터다. 판 번호가 안 돌아가면 마지막 판을 무한 반복한다.
func _test_reset_run_returns_to_the_first_stage() -> void:
	var f := PlayField.new()
	f.next_stage()
	f.next_stage()
	f.lives = 0
	f.elapsed = 99.0
	f.reset_run()
	assert(f.stage_index == 0, "판 번호가 0 으로 안 돌아갔다: %d" % f.stage_index)
	assert(f.lives == Tuning.LIVES, "목숨이 안 채워졌다: %d" % f.lives)
	assert(is_equal_approx(f.elapsed, 0.0), "속도 램프가 안 돌아갔다: %f" % f.elapsed)
	assert(f.grid.cells == StageGen.stage(0).cells, "0 판의 배치가 아니다")
