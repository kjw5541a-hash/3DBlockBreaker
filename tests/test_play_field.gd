extends SceneTree

func _initialize() -> void:
	_test_passive_bounce_lands_on_v_min()
	_test_decay_sequence_shrinks_then_stops()
	_test_swing_accelerates_ball()
	_test_tilted_swing_changes_direction()
	_test_paddle_never_double_bounces()
	_test_ball_below_zero_costs_a_life()
	_test_clearing_all_bricks_reports_cleared()
	print("test_play_field: OK")
	quit()

const DT := 1.0 / 120.0

# 패들을 가만히 둔 채 공을 한 번 받게 하고, 받은 직후 속도를 돌려준다.
func _bounce_once(v_in: Vector2) -> Vector2:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = v_in
	for i in 240:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			return f.ball_vel
		if r["lost"]:
			break
	assert(false, "패들에 안 맞았다")
	return Vector2.ZERO

func _test_passive_bounce_lands_on_v_min() -> void:
	var out := _bounce_once(Vector2(0.0, -Tuning.v_min()))
	assert(absf(out.length() - Tuning.v_min()) < 0.001,
		"가만히 받았는데 하한이 안 나온다: %f" % out.length())
	assert(out.y > 0.0, "받은 공이 위로 안 간다: %s" % out)

# 세게 친 공을 계속 가만히 받으면 도달 높이가 눈에 띄게 줄다가
# 하한에서 멈춘다. 이게 이 게임의 감쇠 설계 전부다.
func _test_decay_sequence_shrinks_then_stops() -> void:
	var speeds: Array[float] = []
	var v := 30.0
	for i in 6:
		var out := _bounce_once(Vector2(0.0, -v))
		v = out.length()
		speeds.append(v)
	for i in range(1, 4):
		assert(speeds[i] < speeds[i - 1] - 0.5,
			"%d번째에서 감쇠가 멈췄다: %s" % [i, str(speeds)])
	assert(absf(speeds[5] - Tuning.v_min()) < 0.001,
		"하한에 안 내려앉았다: %s" % str(speeds))

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
	for i in 20:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			hits += 1
	assert(hits == 1, "접촉이 이어지는 동안 여러 번 튕겼다: %d" % hits)

func _test_ball_below_zero_costs_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(4.5, 0.2)
	f.ball_vel = Vector2(0.0, -20.0)
	var before := f.lives
	var lost := false
	for i in 60:
		if f.step(Vector2(-4.0, Tuning.PADDLE_BAND_MIN_V), DT)["lost"]:
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
	f.ball_pos = Vector2(r.position.x + 0.5, r.position.y - 0.3)
	f.ball_vel = Vector2(0.0, 8.0)
	var cleared := false
	for i in 60:
		if f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)["cleared"]:
			cleared = true
			break
	assert(cleared, "마지막 블럭을 깼는데 cleared 가 안 나온다")
	assert(f.grid.remaining() == 0, "블럭이 남아 있다")
