class_name PlayField
extends RefCounted

var grid: BrickGrid
var paddle: PaddleState
var ball_pos: Vector2
var ball_vel: Vector2 = Vector2.ZERO
var attached: bool = true
var lives: int = Tuning.LIVES
# 공이 살아 있던 누적 시간. 잘 맞은 공의 상한이 이 값으로 오른다.
var elapsed: float = 0.0
# 지금 몇 판인지. 0 기반이다 — HUD 만 +1 해서 보여준다. 시드가 이 값이라
# 이 숫자 하나가 배치 전체를 결정한다.
var stage_index: int = 0
# 직전 서브스텝에 상처를 준 칸. 정지에 가까운 공은 블럭 위에 얹힌 채 매
# 프레임 다시 파고들고, 그때마다 hit() 을 부르면 3히트 블럭이 0.05초에
# 죽는다. 같은 칸을 연속으로 두 번 깎지 않는다 — 공이 한 번이라도 떨어지면
# 다음 접촉은 새 타격이다. -1 은 "직전에 깎은 칸 없음" 이지 브릭 종류가
# 아니다 — BrickGrid.INDESTRUCTIBLE 의 -1 과는 다른 뜻이다.
var _last_damaged: int = -1

func _init() -> void:
	grid = StageGen.stage(stage_index)
	paddle = PaddleState.new(0.0)
	_attach()

func _attach() -> void:
	attached = true
	ball_vel = Vector2.ZERO
	ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
	_last_damaged = -1

# 붙어 있는 공을 스윙 속도로 쏜다. 탭만 하면(스윙 0) 하한으로 수직
# 발사한다. 첫 입력부터 스윙 문법을 가르치므로 튜토리얼이 필요 없다.
func launch(swing: Vector2) -> void:
	if not attached:
		return
	attached = false
	ball_vel = BallPhysics.enforce_min_angle(
		BallPhysics.clamp_speed(
			Vector2(0.0, Tuning.v_min()) + swing * Tuning.PADDLE_SPEED_TRANSFER,
			Tuning.v_min(), Tuning.v_max_at(elapsed)),
		Tuning.MIN_ANGLE_DEG)

func step(target: Vector2, dt: float) -> Dictionary:
	paddle.update(target, dt)
	var out := {"paddle_hit": false, "bricks_hit": 0, "broken": [], "lost": false, "cleared": false}
	if attached:
		ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
		return out
	elapsed += dt

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
			var i := BrickGrid.index(q["col"], q["row"])
			# 정지에 가까운 공은 블럭 위에 얹힌 채 중력에 매 프레임 다시
			# 파고든다 — 그때마다 hit() 을 부르면 여러 히트짜리 블럭이 몇
			# 프레임 만에 죽는다. 같은 칸이면 깎지 않는다.
			if i != _last_damaged:
				# hit() 이 칸 값을 깎아 버리므로 먼저 읽어 둔다 — 안 그러면 마지막
				# 히트에서는 종류가 이미 0 이 되어 무엇이 깨졌는지 알 수 없다.
				var kind := grid.get_cell(q["col"], q["row"])
				grid.hit(q["col"], q["row"])
				# 깨졌을 때만 센다. 단단 블럭은 마지막 히트에서만 목록에 오르고,
				# 불괴 블럭은 영원히 안 오른다.
				if grid.get_cell(q["col"], q["row"]) == 0:
					(out["broken"] as Array).append(
						{"col": q["col"], "row": q["row"], "kind": kind})
					out["bricks_hit"] = (out["broken"] as Array).size()
			_last_damaged = i
			# 블럭은 에너지를 잃지 않는다. 손실원은 패들뿐이다. 반사는
			# 디바운스와 무관하게 항상 일어난다 — 그렇지 않으면 공이 블럭
			# 안으로 파고들며 멈춘다.
			ball_vel = BallPhysics.reflect(ball_vel, q["normal"])
			ball_pos += q["normal"] * q["depth"]
		else:
			# 공이 블럭을 떠났다 — 다음 접촉은 새 타격이다.
			_last_damaged = -1

		if not out["paddle_hit"] and _touches_paddle():
			var n_p := paddle.contact_normal(ball_pos.x)
			var before := ball_vel
			ball_vel = BallPhysics.paddle_bounce(before, n_p, paddle.vel,
				Tuning.v_max_at(elapsed))
			if ball_vel != before:
				out["paddle_hit"] = true
				# 패들 표면 밖으로 꺼내 다음 스텝에 다시 물리지 않게 한다.
				ball_pos.y = paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS

		# 데드존. 목숨을 잃는 유일한 조건이다 — 블럭을 못 깨고 계속 받기만
		# 하는 것은 벌하지 않는다. 반발계수가 도달 높이를 깎아 공이 패들 위로
		# 가라앉고, 그동안 elapsed 는 계속 흘러 속도 램프만 오른다.
		if ball_pos.y < 0.0:
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

# 클리어. elapsed 는 일부러 안 건드린다 — 속도 램프는 판을 가로질러 이어져야
# 난이도가 누적된다. 공을 다시 붙이는 것은 새 판 블럭 한가운데에 공이 박힌
# 채로 시작하는 것을 막으려는 것이다.
func next_stage() -> void:
	stage_index += 1
	grid = StageGen.stage(stage_index)
	_attach()

# 전멸. 여기서만 램프가 0 으로 돌아간다.
func reset_run() -> void:
	lives = Tuning.LIVES
	elapsed = 0.0
	stage_index = 0
	grid = StageGen.stage(stage_index)
	_attach()
