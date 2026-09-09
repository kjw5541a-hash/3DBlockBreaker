extends SceneTree

func _initialize() -> void:
	_test_passive_bounce_loses_energy()
	_test_decay_sequence_never_stops()
	_test_passive_rally_no_longer_costs_a_life()
	_test_swing_accelerates_ball()
	_test_early_game_caps_swing_speed()
	_test_tilted_swing_changes_direction()
	_test_paddle_never_double_bounces()
	_test_ball_below_zero_costs_a_life()
	_test_clearing_all_bricks_reports_cleared()
	_test_hard_brick_survives_the_first_hit()
	_test_resting_ball_does_not_chip_a_brick_every_frame()
	_test_broken_list_carries_kind_before_the_destroying_hit()
	_test_next_stage_advances_without_resetting_the_speed_ramp()
	_test_reset_run_returns_to_the_first_stage()
	_test_losing_a_life_drops_a_fresh_ball_onto_the_paddle()
	_test_dropping_ball_tracks_the_paddle_sideways()
	_test_wall_bounce_is_reported()
	_test_marked_brick_drops_an_item_once()
	_test_item_falls_at_a_constant_speed()
	_test_paddle_catches_an_item_and_gains_a_life()
	_test_missed_item_disappears_without_costing_a_life()
	_test_items_keep_falling_while_the_ball_is_attached()
	_test_enlarge_widens_the_paddle_and_release_restores_it()
	_test_slow_scales_ball_physics_but_not_elapsed()
	_test_catch_attaches_the_ball_at_the_contact_point()
	_test_caught_ball_launches_normally()
	_test_new_active_item_replaces_the_previous_one()
	_test_losing_a_life_clears_the_active_item()
	_test_next_stage_clears_the_active_item()
	_test_firing_a_laser_requires_the_active_item()
	_test_laser_respects_its_cooldown()
	_test_laser_travels_at_a_constant_speed()
	_test_laser_breaks_a_brick_and_is_consumed()
	_test_laser_disappears_past_the_top_wall()
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
# 지점이 없다 — 하한을 없앤 것이 이 게임의 감쇠 설계 전부다.
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

# 블럭을 못 깨고 계속 받기만 하는 것은 더 이상 벌하지 않는다. 예전에는 세 번
# 튕기면 목숨을 가져갔는데, 플레이해 보니 너무 가혹했다. 지금 목숨을 잃는
# 조건은 데드존 하나뿐이다.
#
# 규칙이 없어도 뭉개는 것은 손해다: 반발계수가 도달 높이를 계속 깎아 공이
# 패들 위로 가라앉으므로 블럭에 닿으려면 결국 스윙해야 하고, 그동안 elapsed 는
# 계속 흘러 속도 램프만 오른다.
func _test_passive_rally_no_longer_costs_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	var before := f.lives
	var hits := 0
	for i in 1200:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			hits += 1
		assert(not bool(r["lost"]),
			"가만히 받기만 했는데 %d 프레임에서 목숨을 잃었다 (패들 접촉 %d회)" % [i, hits])
	assert(f.lives == before, "목숨이 줄었다: %d -> %d" % [before, f.lives])
	# 공이 붙어 버렸거나 어딘가에 끼면 위 단언이 자명 참이 된다. 실제로 계속
	# 주고받았는지 확인한다.
	assert(hits > 10, "패들에 거의 안 닿았다 — 이 테스트가 아무것도 안 하고 있다: %d" % hits)
	assert(not f.attached, "공이 도중에 다시 붙었다 — 목숨을 잃었다는 뜻이다")

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
	assert(not f.attached and f.dropping,
		"공을 잃은 직후에는 바로 붙지 않고 떨어지는 중이어야 한다")

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

# 단단 블럭은 한 대에 안 죽는다. 값이 곧 남은 히트 수이므로 첫 히트에서는
# 2 에서 1 로 줄기만 하고, 두 번째 히트에서 사라진다.
func _test_hard_brick_survives_the_first_hit() -> void:
	var f := PlayField.new()
	var r := BrickGrid.cell_rect(5, 0)
	var below := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS - 0.01)
	f.grid.cells[BrickGrid.index(5, 0)] = 2
	f.attached = false

	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	f.step(f.paddle.pos, 1.0 / 120.0)
	assert(f.grid.get_cell(5, 0) == 1,
		"단단 블럭이 한 대에 사라졌다: %d" % f.grid.get_cell(5, 0))

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
	# 공을 블럭 띠 한가운데로 날려 보낸다. 새 판이 이 상태를 그대로 물려받으면
	# 공이 블럭 안에 박힌 채 시작한다 — next_stage() 가 _attach() 를 부르는 이유가
	# 그것이고, 띄워 두지 않으면 아래 단언이 자명 참이 되어 아무것도 검사하지 않는다.
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.BRICK_BOTTOM_V + 1.0)
	f.ball_vel = Vector2(3.0, 7.0)
	f.next_stage()
	assert(f.stage_index == 1, "판 번호가 안 올랐다: %d" % f.stage_index)
	assert(is_equal_approx(f.elapsed, 42.0),
		"판이 넘어가며 속도 램프가 초기화됐다: %f" % f.elapsed)
	assert(f.grid.cells != before, "다음 판인데 배치가 그대로다")
	assert(f.grid.cells == StageGen.stage(1).cells, "1 판의 배치가 아니다")
	# 새 판 블럭 안에 공이 박힌 채로 시작하면 안 된다.
	assert(f.attached, "판이 넘어갔는데 공이 안 붙었다")
	assert(f.ball_vel == Vector2.ZERO,
		"판이 넘어갔는데 공이 이전 판의 속도를 그대로 들고 있다: %s" % f.ball_vel)

# 전멸하면 처음부터다. 판 번호가 안 돌아가면 마지막 판을 무한 반복한다.
func _test_reset_run_returns_to_the_first_stage() -> void:
	var f := PlayField.new()
	f.next_stage()
	f.next_stage()
	f.lives = 0
	f.elapsed = 99.0
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.BRICK_BOTTOM_V + 1.0)
	f.ball_vel = Vector2(3.0, 7.0)
	f.reset_run()
	assert(f.stage_index == 0, "판 번호가 0 으로 안 돌아갔다: %d" % f.stage_index)
	assert(f.lives == Tuning.LIVES, "목숨이 안 채워졌다: %d" % f.lives)
	assert(is_equal_approx(f.elapsed, 0.0), "속도 램프가 안 돌아갔다: %f" % f.elapsed)
	assert(f.grid.cells == StageGen.stage(0).cells, "0 판의 배치가 아니다")
	assert(not f.attached and f.dropping,
		"전멸도 공을 잃은 것이다 — 즉시 붙지 않고 떨어지는 중이어야 한다")
	assert(f.ball_vel == Vector2.ZERO,
		"처음부터 다시인데 공이 이전 속도를 들고 있다: %s" % f.ball_vel)

# 목숨을 잃으면 즉시 붙지 않고 패들 위로 떨어져 내린다 — 그동안 화면에서는
# 패들이 부서졌다 다시 생기는 연출이 돈다. 착지하면 보통 때처럼 붙는다.
func _test_losing_a_life_drops_a_fresh_ball_onto_the_paddle() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	# 패들을 반대쪽으로 보내 둔다 — 안 그러면 떨어지는 공이 데드존 전에
	# 패들에 먼저 맞아 목숨을 안 잃는다.
	f.ball_pos = Vector2(Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS, 0.2)
	f.ball_vel = Vector2(0.0, -20.0)
	var before_lives := f.lives
	var r: Dictionary
	for i in 60:
		r = f.step(Vector2(-Tuning.BOARD_HALF_WIDTH, Tuning.PADDLE_BAND_MIN_V), DT)
		if bool(r["lost"]):
			break
	assert(bool(r["lost"]), "공이 데드존까지 안 내려갔다 — 테스트 전제가 깨졌다")
	assert(f.lives == before_lives - 1, "목숨이 하나 안 줄었다: %d -> %d" % [before_lives, f.lives])
	assert(not f.attached and f.dropping,
		"목숨을 잃은 직후 바로 붙어 버렸다 — 떨어지는 연출이 없다")
	assert(f.ball_pos.y > f.paddle.pos.y, "떨어지는 공이 패들보다 낮은 곳에서 시작한다")

	var landed := false
	for i in 120:
		f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if f.attached:
			landed = true
			break
	assert(landed, "공이 패들에 안 내려앉았다")
	assert(not f.dropping, "붙었는데 dropping 이 아직 켜져 있다")
	assert(f.lives == before_lives - 1, "착지하는 동안 목숨이 더 줄었다: %d" % f.lives)

# 떨어지는 중에 손가락이 움직이면 새 패들이 그 밑에 와 있어야 한다 —
# 낙하 지점이 스폰 당시 x 에 고정돼 있으면 손가락을 옮긴 순간 헛착지가
# 난다.
func _test_dropping_ball_tracks_the_paddle_sideways() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	# 목숨을 잃는 경로 자체는 위 테스트가 이미 본다. 여기서는 낙하 중
	# x 추종만 보면 되므로 낙하 상태를 직접 만든다.
	f._spawn_dropping()
	assert(f.dropping, "테스트 전제가 깨졌다 — 낙하 중이 아니다")
	var target_x := 1.5
	for i in 60:
		f.step(Vector2(target_x, Tuning.PADDLE_BAND_MIN_V), DT)
		if f.attached:
			break
	assert(f.attached, "옆으로 옮긴 패들에 안 내려앉았다")
	assert(is_equal_approx(f.ball_pos.x, f.paddle.pos.x),
		"붙은 공이 패들 x 와 다르다: %f vs %f" % [f.ball_pos.x, f.paddle.pos.x])
	assert(absf(f.paddle.pos.x) > 0.5,
		"패들이 스폰 지점(x=0)에서 실제로는 안 옮겨졌다 — 이 테스트가 헛돈다: %f" % f.paddle.pos.x)

# 옆벽 충돌 사운드를 붙이려면 out 딕셔너리에 신호가 있어야 한다. 패들
# 밴드에서 먼 높이에서 옆벽을 향해 쏴 패들에 먼저 닿을 여지를 없앤다.
func _test_wall_bounce_is_reported() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS - 0.05,
		Tuning.BOARD_TOP_V * 0.5)
	f.ball_vel = Vector2(20.0, 0.0)
	var hit := false
	for i in 30:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if bool(r["wall_hit"]):
			hit = true
			break
	assert(hit, "옆벽에 닿았는데 wall_hit 이 안 켜졌다")

# 아이템은 표시된 블럭이 깨지는 순간에만 떨어져야 한다. 단단 블럭이 맞을
# 때마다 떨어지면 한 칸에서 셋이 쏟아진다.
func _test_marked_brick_drops_an_item_once() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	# 단단 블럭 하나에 아이템을 실어 둔다. 두 번 맞아야 깨지는 칸이라
	# "맞을 때마다"와 "깨질 때만"이 구별된다.
	f.grid.cells[BrickGrid.index(5, 0)] = 2
	f.grid.item_cells[BrickGrid.index(5, 0)] = Item.P
	var rect := BrickGrid.cell_rect(5, 0)
	var center := rect.position + rect.size * 0.5
	f.attached = false
	# 첫 히트. 칸 바로 아래에서 위로 쏴 한 대 때린다.
	# 블럭과 안 겹치는 자리에서 쏜다. 겹친 채로 시작하면 _last_damaged
	# 디바운스에 걸려 깎지 않고 튕기기만 한다.
	f.ball_pos = Vector2(center.x, rect.position.y - Tuning.BALL_RADIUS - 0.1)
	f.ball_vel = Vector2(0.0, 8.0)
	var first_hit := false
	for i in 20:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if int(r["bricks_hit"]) > 0 or f.grid.get_cell(5, 0) != 2:
			first_hit = true
			break
	assert(first_hit, "첫 히트가 안 났다 — 테스트가 헛돈다")
	assert(f.grid.get_cell(5, 0) == 1, "단단 블럭이 한 대에 깨졌다: %d" % f.grid.get_cell(5, 0))
	assert(f.items.is_empty(), "아직 안 깨졌는데 아이템이 떨어졌다: %d" % f.items.size())

	# 두 번째 히트로 깬다.
	# 블럭과 안 겹치는 자리에서 쏜다. 겹친 채로 시작하면 _last_damaged
	# 디바운스에 걸려 깎지 않고 튕기기만 한다.
	f.ball_pos = Vector2(center.x, rect.position.y - Tuning.BALL_RADIUS - 0.1)
	f.ball_vel = Vector2(0.0, 8.0)
	var broke := false
	for i in 20:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if (r["broken"] as Array).size() > 0:
			broke = true
			break
	assert(broke, "두 번째 히트로도 안 깨졌다")
	assert(f.items.size() == 1, "깨졌는데 아이템이 하나가 아니다: %d" % f.items.size())
	assert(int(f.items[0]["kind"]) == Item.P, "떨어진 종류가 P 가 아니다")
	assert(f.grid.item_cells[BrickGrid.index(5, 0)] == Item.NONE,
		"떨어뜨린 뒤에도 칸에 아이템이 남아 있다")

# 등속이어야 한다. 중력으로 가속하면 잡을 수 있는지를 순간 판단할 수 없다.
func _test_item_falls_at_a_constant_speed() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.items.append({"pos": Vector2(2.5, 8.0), "kind": Item.P})
	var start: float = (f.items[0]["pos"] as Vector2).y
	for i in 60:
		f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var dropped: float = start - (f.items[0]["pos"] as Vector2).y
	var expected := Tuning.ITEM_FALL_SPEED * 60.0 * DT
	assert(is_equal_approx(dropped, expected),
		"등속이 아니다 — 0.5초에 %f 내려왔다 (기대 %f)" % [dropped, expected])
	assert(is_equal_approx((f.items[0]["pos"] as Vector2).x, 2.5),
		"아이템이 옆으로 흘렀다: %f" % (f.items[0]["pos"] as Vector2).x)

func _test_paddle_catches_an_item_and_gains_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	var before := f.lives
	# 패들 바로 위에 놓고 패들을 그 x 로 보낸다.
	f.items.append({"pos": Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6), "kind": Item.P})
	var taken := false
	for i in 60:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if (r["items_taken"] as Array).size() > 0:
			assert(int((r["items_taken"] as Array)[0]) == Item.P, "받은 종류가 P 가 아니다")
			taken = true
			break
	assert(taken, "패들 바로 위로 떨어뜨렸는데 못 받았다")
	assert(f.lives == before + 1, "P 를 받았는데 목숨이 안 늘었다: %d -> %d" % [before, f.lives])
	assert(f.items.is_empty(), "받은 아이템이 목록에 남아 있다")

# 놓친 것을 벌하면 아이템이 보상이 아니라 위험이 된다.
func _test_missed_item_disappears_without_costing_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	var before := f.lives
	# 패들에서 먼 x. 패들은 반대쪽 끝에 세워 둔다.
	f.items.append({"pos": Vector2(2.8, 3.0), "kind": Item.P})
	for i in 240:
		var r := f.step(Vector2(-2.8, Tuning.PADDLE_BAND_MIN_V), DT)
		assert((r["items_taken"] as Array).is_empty(), "안 닿았는데 받았다")
		if f.items.is_empty():
			break
	assert(f.items.is_empty(), "판 아래로 지나간 아이템이 안 사라졌다")
	assert(f.lives == before, "아이템을 놓쳤는데 목숨이 깎였다: %d -> %d" % [before, f.lives])

# 공이 붙어 있거나 낙하 중일 때 step() 은 조기 반환한다. 아이템 갱신이 그
# 뒤에 있으면 공을 놓친 순간 화면의 아이템이 공중에 얼어붙는다.
func _test_items_keep_falling_while_the_ball_is_attached() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	assert(f.attached, "새 PlayField 의 공이 안 붙어 있다 — 테스트가 헛돈다")
	f.items.append({"pos": Vector2(2.5, 8.0), "kind": Item.P})
	var start: float = (f.items[0]["pos"] as Vector2).y
	for i in 30:
		f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert((f.items[0]["pos"] as Vector2).y < start,
		"공이 붙어 있는 동안 아이템이 안 내려왔다")

	# 낙하 중(dropping)에도 마찬가지다.
	f._spawn_dropping()
	var mid: float = (f.items[0]["pos"] as Vector2).y
	for i in 30:
		f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert((f.items[0]["pos"] as Vector2).y < mid,
		"새 공이 낙하하는 동안 아이템이 안 내려왔다")

func _test_enlarge_widens_the_paddle_and_release_restores_it() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	var base := Tuning.PADDLE_HALF_WIDTH
	f.active_item = Item.E
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(is_equal_approx(f.paddle.half_width, base * Tuning.ITEM_ENLARGE_MULT),
		"Enlarge 가 활성인데 반폭이 안 늘었다: %f" % f.paddle.half_width)
	f.active_item = Item.NONE
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(is_equal_approx(f.paddle.half_width, base),
		"Enlarge 가 풀렸는데 반폭이 안 돌아왔다: %f" % f.paddle.half_width)

# 벽·블럭·패들과 안 부딪히는 자리에서 공을 자유비행시켜 물리 스케일만 본다.
func _test_slow_scales_ball_physics_but_not_elapsed() -> void:
	var slow := PlayField.new()
	slow.grid.fill_all(0)
	slow.attached = false
	slow.ball_pos = Vector2(0.0, 8.0)
	slow.ball_vel = Vector2(0.0, 10.0)
	slow.active_item = Item.S
	slow.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)

	var normal := PlayField.new()
	normal.grid.fill_all(0)
	normal.attached = false
	normal.ball_pos = Vector2(0.0, 8.0)
	normal.ball_vel = Vector2(0.0, 10.0)
	normal.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)

	assert(slow.ball_pos.y < normal.ball_pos.y,
		"Slow 가 걸렸는데 공이 평소만큼 움직였다: %f vs %f" % [slow.ball_pos.y, normal.ball_pos.y])
	var expected_sub := DT * Tuning.ITEM_SLOW_TIMESCALE
	var expected_vel_y := 10.0 - Tuning.GRAVITY * expected_sub
	var expected_pos_y := 8.0 + expected_vel_y * expected_sub
	assert(is_equal_approx(slow.ball_pos.y, expected_pos_y),
		"Slow 물리 계산이 기대와 다르다: %f vs %f" % [slow.ball_pos.y, expected_pos_y])
	assert(is_equal_approx(slow.elapsed, DT),
		"Slow 가 elapsed 까지 늦췄다 — 속도 램프가 함께 얼면 안 된다: %f" % slow.elapsed)

func _test_catch_attaches_the_ball_at_the_contact_point() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.active_item = Item.C
	var target := Vector2(0.3, Tuning.PADDLE_BAND_MIN_V)
	f.ball_pos = Vector2(0.5, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -8.0)
	var caught := false
	for i in 60:
		var r := f.step(target, DT)
		if bool(r["paddle_hit"]):
			caught = true
			break
	assert(caught, "Catch 가 활성인데 패들에 안 닿았다 — 테스트가 헛돈다")
	assert(f.attached, "Catch 인데 패들에 안 붙었다")
	assert(not is_equal_approx(f._attach_offset_u, 0.0),
		"접촉점 오프셋이 0 이다 — 중앙으로 스냅한 것 같다")

	# 패들이 움직여도 잡힌 자리(오프셋)를 유지하며 따라가야 한다.
	var offset := f._attach_offset_u
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(is_equal_approx(f.ball_pos.x, f.paddle.pos.x + offset),
		"패들이 움직였는데 공이 오프셋을 안 지켰다")

func _test_caught_ball_launches_normally() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.active_item = Item.C
	f.attached = true
	f._attach_offset_u = 0.2
	f.launch(Vector2(3.0, 0.0))
	assert(not f.attached, "발사했는데 여전히 붙어 있다")
	assert(f.ball_vel.length() > 0.0, "발사했는데 속도가 0 이다")

func _test_new_active_item_replaces_the_previous_one() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f._apply_item(Item.E)
	assert(f.active_item == Item.E, "E 를 먹었는데 활성 아이템이 아니다")
	f._apply_item(Item.S)
	assert(f.active_item == Item.S, "새 아이템을 먹었는데 이전 것이 안 풀렸다: %d" % f.active_item)

func _test_losing_a_life_clears_the_active_item() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.active_item = Item.E
	f.ball_pos = Vector2(Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS, 0.2)
	f.ball_vel = Vector2(0.0, -20.0)
	var lost := false
	for i in 60:
		if f.step(Vector2(-Tuning.BOARD_HALF_WIDTH, Tuning.PADDLE_BAND_MIN_V), DT)["lost"]:
			lost = true
			break
	assert(lost, "공이 데드존으로 나갔는데 lost 가 아니다 — 테스트가 헛돈다")
	assert(f.active_item == Item.NONE,
		"목숨을 잃었는데 활성 아이템이 안 풀렸다: %d" % f.active_item)

func _test_next_stage_clears_the_active_item() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.active_item = Item.E
	f.next_stage()
	assert(f.active_item == Item.NONE,
		"판을 클리어했는데 활성 아이템이 안 풀렸다: %d" % f.active_item)

func _test_firing_a_laser_requires_the_active_item() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.fire_laser()
	assert(f.lasers.is_empty(), "L 이 없는데 발사됐다")
	f.active_item = Item.L
	f.fire_laser()
	assert(f.lasers.size() == 1, "L 이 활성인데 발사가 안 됐다")

func _test_laser_respects_its_cooldown() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.active_item = Item.L
	f.fire_laser()
	f.fire_laser()
	assert(f.lasers.size() == 1, "쿨다운 중인데 연달아 발사됐다: %d" % f.lasers.size())
	for i in 60:
		f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	f.fire_laser()
	assert(f.lasers.size() == 2, "쿨다운이 지났는데도 두 번째 발사가 안 됐다")

func _test_laser_travels_at_a_constant_speed() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.lasers.append(Vector2(0.0, 5.0))
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var expected := 5.0 + Tuning.LASER_SPEED * DT
	assert(is_equal_approx(f.lasers[0].y, expected),
		"레이저 속도가 기대와 다르다: %f vs %f" % [f.lasers[0].y, expected])

func _test_laser_breaks_a_brick_and_is_consumed() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.grid.cells[BrickGrid.index(5, 2)] = 1
	var rect := BrickGrid.cell_rect(5, 2)
	var center := rect.position + rect.size * 0.5
	f.lasers.append(Vector2(center.x, rect.position.y - 0.1))
	var broke := false
	for i in 30:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if (r["broken"] as Array).size() > 0:
			broke = true
			break
	assert(broke, "레이저가 블럭을 안 깼다")
	assert(f.lasers.is_empty(), "블럭을 맞힌 레이저가 안 사라졌다")

func _test_laser_disappears_past_the_top_wall() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.lasers.append(Vector2(0.0, Tuning.BOARD_TOP_V - 0.05))
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(f.lasers.is_empty(), "판 위로 나간 레이저가 안 사라졌다")
