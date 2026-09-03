extends SceneTree

func _initialize() -> void:
	_test_passive_bounce_loses_energy()
	_test_decay_sequence_never_stops()
	_test_stall_costs_a_life()
	_test_swing_accelerates_ball()
	_test_tilted_swing_changes_direction()
	_test_paddle_never_double_bounces()
	_test_ball_below_zero_costs_a_life()
	_test_clearing_all_bricks_reports_cleared()
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
