class_name PlayField
extends RefCounted

var grid: BrickGrid
var paddle: PaddleState
var ball_pos: Vector2
var ball_vel: Vector2 = Vector2.ZERO
var attached: bool = true
var lives: int = Tuning.LIVES
# 마지막으로 블럭을 깬 뒤 패들에 몇 번 튕겼는지. 속도 하한을 없앤 대신
# 이 값이 교착을 끝낸다.
var paddle_hits_since_brick: int = 0

func _init() -> void:
	grid = BrickGrid.new()
	grid.fill_all(1)
	paddle = PaddleState.new(0.0)
	_attach()

func _attach() -> void:
	attached = true
	paddle_hits_since_brick = 0
	ball_vel = Vector2.ZERO
	ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)

# 붙어 있는 공을 스윙 속도로 쏜다. 탭만 하면(스윙 0) 하한으로 수직
# 발사한다. 첫 입력부터 스윙 문법을 가르치므로 튜토리얼이 필요 없다.
func launch(swing: Vector2) -> void:
	if not attached:
		return
	attached = false
	ball_vel = BallPhysics.enforce_min_angle(
		BallPhysics.clamp_speed(
			Vector2(0.0, Tuning.v_min()) + swing * Tuning.PADDLE_SPEED_TRANSFER,
			Tuning.v_min(), Tuning.V_MAX),
		Tuning.MIN_ANGLE_DEG)

func step(target: Vector2, dt: float) -> Dictionary:
	paddle.update(target, dt)
	var out := {"paddle_hit": false, "bricks_hit": 0, "lost": false, "cleared": false}
	if attached:
		ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
		return out

	# 한 스텝 이동거리가 반지름을 넘지 않도록 쪼갠다. 안 쪼개면 빠른
	# 공이 얇은 블럭을 그냥 통과한다.
	var n := BallPhysics.substeps(ball_vel.length(), dt)
	var sub := dt / float(n)
	for s in n:
		ball_vel = BallPhysics.step_vel(ball_vel, sub)
		ball_pos = BallPhysics.step_pos(ball_pos, ball_vel, sub)

		var wall := BallPhysics.resolve_walls(ball_pos, ball_vel)
		ball_pos = wall[0]
		ball_vel = wall[1]

		var q := grid.query(ball_pos, Tuning.BALL_RADIUS)
		if q["hit"]:
			grid.hit(q["col"], q["row"])
			out["bricks_hit"] = int(out["bricks_hit"]) + 1
			paddle_hits_since_brick = 0
			# 블럭은 에너지를 잃지 않는다. 손실원은 패들뿐이다.
			ball_vel = BallPhysics.reflect(ball_vel, q["normal"])
			ball_pos += q["normal"] * q["depth"]

		if not out["paddle_hit"] and _touches_paddle():
			var n_p := paddle.contact_normal(ball_pos.x)
			var before := ball_vel
			ball_vel = BallPhysics.paddle_bounce(before, n_p, paddle.vel)
			if ball_vel != before:
				out["paddle_hit"] = true
				paddle_hits_since_brick += 1
				# 패들 표면 밖으로 꺼내 다음 스텝에 다시 물리지 않게 한다.
				ball_pos.y = paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS

		# 블럭을 못 깨고 패들에만 계속 튕기는 교착. 데드존과 똑같이 처리한다.
		if ball_pos.y < 0.0 or paddle_hits_since_brick >= Tuning.STALL_PADDLE_HITS:
			lives -= 1
			out["lost"] = true
			_attach()
			break

	if grid.remaining() == 0:
		out["cleared"] = true
	return out

# 공 원이 패들의 스윕 상자에 닿았는지. 상자가 축정렬이라 가장 가까운
# 점까지의 거리로 판정한다.
func _touches_paddle() -> bool:
	var r := paddle.swept_rect()
	var nearest := Vector2(
		clampf(ball_pos.x, r.position.x, r.position.x + r.size.x),
		clampf(ball_pos.y, r.position.y, r.position.y + r.size.y))
	return ball_pos.distance_to(nearest) < Tuning.BALL_RADIUS
