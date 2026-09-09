class_name BallPhysics
extends RefCounted

static func reflect(v: Vector2, n: Vector2) -> Vector2:
	return v - 2.0 * v.dot(n) * n

# 방향은 그대로 두고 속력만 범위 안으로 넣는다. 0 벡터는 방향이 없어
# 그대로 두면 공이 죽으므로 위로 세운다.
static func clamp_speed(v: Vector2, lo: float, hi: float) -> Vector2:
	var s := v.length()
	if s < 0.0001:
		return Vector2(0.0, lo)
	return v * (clampf(s, lo, hi) / s)

# 공이 수평에 너무 가까우면 좌우 벽만 튕기며 영영 안 내려온다.
# 속력은 보존하고 각도만 최소각 밖으로 밀어낸다.
static func enforce_min_angle(v: Vector2, min_deg: float) -> Vector2:
	var s := v.length()
	if s < 0.0001:
		return v
	var min_sin := sin(deg_to_rad(min_deg))
	if absf(v.y) >= s * min_sin:
		return v
	var sign_y := 1.0 if v.y >= 0.0 else -1.0
	var sign_x := 1.0 if v.x >= 0.0 else -1.0
	return Vector2(sign_x * s * cos(deg_to_rad(min_deg)), sign_y * s * min_sin)

# 세미암시적 오일러. 속도를 먼저 갱신하고 그 속도로 위치를 옮긴다.
# 순서를 바꾸면 에너지가 조금씩 늘어 감쇠 설계가 무너진다.
static func step_vel(vel: Vector2, dt: float) -> Vector2:
	return vel + Vector2(0.0, -Tuning.GRAVITY) * dt

static func step_pos(pos: Vector2, vel: Vector2, dt: float) -> Vector2:
	return pos + vel * dt

# 한 스텝 이동거리가 공 반지름을 넘으면 얇은 블럭을 그냥 통과한다.
static func substeps(speed: float, dt: float) -> int:
	return maxi(1, int(ceil(speed * dt / Tuning.BALL_RADIUS)))

# 좌우 벽과 상단 벽. 반발계수 1.0 — 에너지를 잃는 곳은 패들뿐이다.
# 파고든 만큼 위치를 되밀고 속도 부호를 안쪽으로 강제한다. 부호를
# 뒤집는 대신 강제하는 것은, 한 프레임에 두 번 처리돼도 벽에 들러붙지
# 않게 하려는 것이다.
static func resolve_walls(pos: Vector2, vel: Vector2) -> Array[Vector2]:
	var p := pos
	var v := vel
	var lim := Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS
	if p.x < -lim:
		p.x = -lim
		v.x = absf(v.x)
	elif p.x > lim:
		p.x = lim
		v.x = -absf(v.x)
	var top := Tuning.BOARD_TOP_V - Tuning.BALL_RADIUS
	if p.y > top:
		p.y = top
		v.y = -absf(v.y)
	var out: Array[Vector2] = [p, v]
	return out

# 이 게임의 전부인 식. 네 줄이 감쇠, 가속, 조준, 교착 방지를 만든다.
#
# 이미 패들에서 멀어지는 중이면 손대지 않는다. 접촉이 두 프레임 이어질 때
# 두 번 튕겨 공이 패들 안에서 진동하는 것을 막는다.
static func paddle_bounce(v_in: Vector2, normal: Vector2, paddle_vel: Vector2,
		v_max: float) -> Vector2:
	if v_in.dot(normal) >= 0.0:
		return v_in
	var out := reflect(v_in, normal) * Tuning.PADDLE_RESTITUTION
	out += paddle_vel * Tuning.PADDLE_SPEED_TRANSFER
	# 공은 자기를 친 패들보다 느리게 떠나지 않는다. 스프링 복귀가 정지한
	# 공을 칠 때 transfer(0.6)만으로는 공이 반드시 패들보다 느려지고, 그러면
	# 패들이 곧바로 공을 추월해 메시를 뚫고 지나간다. 일반 랠리에서는 반사
	# 성분이 훨씬 커서 이 하한이 걸리지 않는다 — 가만히 받으면 반발계수만큼
	# 계속 느려지고 결국 공이 패들 위로 가라앉는다는 성질은 그대로다.
	out = clamp_speed(out, maxf(paddle_vel.y, 0.0), v_max)
	return enforce_min_angle(out, Tuning.MIN_ANGLE_DEG)
