class_name PlayField
extends RefCounted

var grid: BrickGrid
var paddle: PaddleState
var ball_pos: Vector2
var ball_vel: Vector2 = Vector2.ZERO
var attached: bool = true
# 손은 이미 뗐지만 공이 아직 패들 위에 얹혀 있다. 스프링이 밀어 올리는
# 동안은 붙은 채로 같이 가속하다가, 패들이 중력보다 세게 감속하기 시작하면
# (paddle.separating) 그때의 패들 속도를 그대로 안고 떠난다. attached 가
# 꺼지는 순간 이 값도 꺼진다.
var riding: bool = false
# 목숨을 잃은 직후, 새 공이 패들 위로 떨어져 내리는 중이다. attached 와
# 배타적이다 — 착지하면 _attach() 가 이 값을 끈다.
var dropping: bool = false
# 불타는 공. 블럭을 안 튕기고 뚫는다. 타이머가 없다 — 패들에 닿을 때마다
# 접촉 위치로 다시 판정하므로, 정확히 받으면 붙고 빗맞으면 그 자리에서
# 꺼진다. 그 밖에 꺼지는 자리는 목숨 상실과 Catch 로 붙잡을 때뿐이다.
var burning: bool = false
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

# 지금 떨어지는 중인 아이템들. 원소는 {"pos": Vector2, "kind": int} 다.
# 개수가 판당 3 개라 배열 순회로 충분하다.
var items: Array[Dictionary] = []
# 지금 켜져 있는 지속 효과(E/S/C/L). 한 번에 하나뿐이라 새로 먹으면 그냥
# 덮어쓴다 — 이전 효과를 끄는 별도 로직이 없다(같은 종류를 다시 먹어도
# 그냥 같은 값으로 덮어써 자연히 중복 획득이 된다). 목숨을 잃을 때와 판
# 클리어 때 둘 다 NONE 으로 되돌린다.
var active_item: int = Item.NONE
# Catch 로 붙었을 때 접촉점의 u 오프셋. 패들 중앙이 아니라 닿은 자리 그대로
# 따라가야 자연스럽다. 일반 부착(_attach)은 0 이라 같은 필드로 통일한다.
var _attach_offset_u: float = 0.0

# 날아가는 레이저 볼트들. 공과 달리 물리(중력·반사)가 없다 — 직선으로
# 올라가다 블럭을 맞히거나 판을 벗어나면 사라진다.
var lasers: Array[Vector2] = []
var _laser_cooldown: float = 0.0

# 목숨을 잃은 새 공이 떨어져 내리기 시작하는 높이. 패들 바로 위, 눈에
# 보일 만큼만 띄운다 — 너무 높으면 착지까지 기다리는 게 지루해진다.
const DROP_HEIGHT := 1.0

func _init() -> void:
	grid = StageGen.stage(stage_index)
	paddle = PaddleState.new(0.0)
	_attach()

func _attach() -> void:
	attached = true
	riding = false
	dropping = false
	burning = false
	ball_vel = Vector2.ZERO
	_attach_offset_u = 0.0
	ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
	_last_damaged = -1

# 목숨을 잃었을 때만 부른다. 공을 패들 바로 위에서 떨어뜨려 "새 공이
# 왔다"는 것을 보여준다 — 판이 넘어가거나(next_stage) 전멸 없이 이어질
# 때(_attach)는 그냥 즉시 붙는다, 그건 손실이 아니라서다.
func _spawn_dropping() -> void:
	attached = false
	riding = false
	dropping = true
	burning = false
	ball_vel = Vector2.ZERO
	ball_pos = Vector2(paddle.pos.x,
		paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS + DROP_HEIGHT)
	_last_damaged = -1

# 붙어 있는 공을 놓는다. 여기서 속도를 안 주는 것이 핵심이다 — 공은 아직
# 패들 위에 얹혀 있고, 튕겨 오르는 패들과 함께 가속하다가 저절로 떠난다.
# 그래서 파워는 당긴 깊이가, 각도는 공이 패들 위 어디에 얹혀 있었는지가
# 정한다(contact_normal 의 접촉점 오프셋).
func release_ball() -> void:
	if not attached:
		return
	riding = true
	ball_vel = Vector2.ZERO

# L 이 활성이고 쿨다운이 끝났을 때만 한 발 나간다. 연타로 화면을 볼트로
# 도배하는 것을 쿨다운이 막는다.
func fire_laser() -> void:
	if active_item != Item.L or _laser_cooldown > 0.0:
		return
	lasers.append(paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5))
	_laser_cooldown = Tuning.LASER_COOLDOWN

func step(target: Vector2, dt: float) -> Dictionary:
	# Enlarge 는 상태를 저장하지 않고 매 프레임 다시 계산한다 — 해제될 때
	# 되돌리는 로직이 따로 필요 없다.
	paddle.half_width = Tuning.PADDLE_HALF_WIDTH * \
		(Tuning.ITEM_ENLARGE_MULT if active_item == Item.E else 1.0)
	paddle.update(target, dt)
	var out := {"paddle_hit": false, "wall_hit": false, "bricks_hit": 0, "broken": [],
		"items_taken": [], "lost": false, "cleared": false, "ignited": false}
	# 아이템은 공과 독립이다. 공이 발사 전에 붙어 있든 목숨을 잃어 새 공이
	# 낙하 중이든 화면의 아이템은 계속 내려와야 한다 — 그래서 아래 조기
	# 반환들보다 앞이다. 레이저와 쿨다운도 같은 이유로 여기 있다.
	_update_items(dt, out)
	_laser_cooldown = maxf(0.0, _laser_cooldown - dt)
	_update_lasers(dt, out)
	if attached:
		ball_pos = paddle.pos + Vector2(_attach_offset_u,
			Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
		# 손을 뗀 공은 패들에 얹힌 채 같이 밀려 올라가다가, 용수철이 중력보다
		# 세게 잡아당기기 시작하는 지점에서 접촉을 잃는다. 그때가 패들이 가장
		# 빠른 순간이라 그 속도가 그대로 발사 속도가 된다.
		if riding and paddle.separating():
			attached = false
			riding = false
			# 패들 속도를 그대로 안고 간다. 손가락을 옆으로 흘리면서 놓으면
			# 그 가로 성분도 실린다 — 상한과 최소각은 공 물리 쪽 규칙을
			# 그대로 따른다.
			ball_vel = BallPhysics.enforce_min_angle(
				BallPhysics.clamp_speed(paddle.vel, 0.0, Tuning.v_max_at(elapsed)),
				Tuning.MIN_ANGLE_DEG)
		return out
	if dropping:
		# x 는 패들을 그대로 따라간다 — 낙하 중에 손가락이 움직여도 헛착지가
		# 안 나야 해서다. y 만 중력으로 떨어뜨린다. 벽·블럭과는 부딪히지
		# 않는다 — 패들 바로 위 짧은 낙하라 부딪힐 것이 없다.
		ball_pos.x = paddle.pos.x
		ball_vel.y -= Tuning.GRAVITY * dt
		ball_pos.y += ball_vel.y * dt
		var land_y := paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS
		if ball_pos.y <= land_y:
			_attach()
		return out
	elapsed += dt

	# Slow 는 공 물리에만 건다. elapsed 는 위에서 이미 실시간으로 더했다 —
	# 여기서 또 줄이면 속도 램프까지 얼어 이중으로 느려진다. 패들 추종과
	# 아이템 낙하도 대상이 아니다.
	var phys_dt := dt * (Tuning.ITEM_SLOW_TIMESCALE if active_item == Item.S else 1.0)
	# 한 스텝 이동거리가 반지름을 넘지 않도록 쪼갠다. 안 쪼개면 빠른
	# 공이 얇은 블럭을 그냥 통과한다.
	var n := BallPhysics.substeps(ball_vel.length(), phys_dt)
	var sub := phys_dt / float(n)
	for s in n:
		ball_vel = BallPhysics.step_vel(ball_vel, sub)
		ball_pos = BallPhysics.step_pos(ball_pos, ball_vel, sub)

		var pre_wall_pos := ball_pos
		var wall := BallPhysics.resolve_walls(ball_pos, ball_vel)
		ball_pos = wall[0]
		ball_vel = wall[1]
		if ball_pos != pre_wall_pos:
			out["wall_hit"] = true

		var q := grid.query(ball_pos, Tuning.BALL_RADIUS)
		if q["hit"] and burning \
				and grid.get_cell(q["col"], q["row"]) != BrickGrid.INDESTRUCTIBLE:
			# 뚫는다. 반사도 위치 보정도 없어 방향과 속력이 그대로다 — 손실원은
			# 여전히 패들뿐이다. 칸이 즉시 0 이 되므로 다음 서브스텝의 query 가
			# 같은 칸을 다시 잡지 않는다. _last_damaged 디바운스가 필요 없는 것도
			# 그래서다.
			var kind := grid.get_cell(q["col"], q["row"])
			grid.destroy(q["col"], q["row"])
			(out["broken"] as Array).append(
				{"col": q["col"], "row": q["row"], "kind": kind})
			out["bricks_hit"] = (out["broken"] as Array).size()
			_spawn_item(q["col"], q["row"])
			_last_damaged = -1
		elif q["hit"]:
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
					_spawn_item(q["col"], q["row"])
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
			# 스프링으로 올라오는 중에는 안 잡는다. 놓은 공은 아직 패들 위에
			# 얹혀 있어서, 여기서 다시 잡으면 C 를 든 동안 영영 발사가 안 된다.
			if active_item == Item.C and not paddle.springing():
				# 튕기는 대신 그 자리에 붙는다. attach() 를 안 쓰는 것은 offset 을
				# 접촉점으로 잡아야 해서다 — 중앙으로 스냅하면 손맛이 부자연스럽다.
				out["paddle_hit"] = true
				attached = true
				riding = false
				# 붙잡은 공은 튕긴 것이 아니라 정확도를 매길 근거가 없다.
				burning = false
				_attach_offset_u = clampf(ball_pos.x - paddle.pos.x,
					-paddle.half_width, paddle.half_width)
				ball_vel = Vector2.ZERO
				ball_pos = paddle.pos + Vector2(_attach_offset_u,
					Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
				break
			var n_p := paddle.contact_normal(ball_pos.x)
			var before := ball_vel
			ball_vel = BallPhysics.paddle_bounce(before, n_p, paddle.vel,
				Tuning.v_max_at(elapsed), paddle.restitution(ball_pos.x))
			if ball_vel != before:
				out["paddle_hit"] = true
				# 불은 접촉마다 다시 판정한다. 지속 시간도 남은 횟수도 없다 —
				# "정확히 받으면 붙고 빗맞으면 꺼진다"가 규칙의 전부다.
				burning = paddle.sweet_spot(ball_pos.x)
				# 이미 타는 중에 또 정확히 받아도 신호를 낸다. 같은 성취에
				# 같은 피드백이 나와야 한다 — 연속으로 잘 받았을 때만 화면이
				# 조용하면 플레이어는 그걸 버그로 읽는다.
				out["ignited"] = burning
				# 패들 표면 밖으로 꺼내 다음 스텝에 다시 물리지 않게 한다.
				ball_pos.y = paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS

		# 데드존. 목숨을 잃는 유일한 조건이다 — 블럭을 못 깨고 계속 받기만
		# 하는 것은 벌하지 않는다. 반발계수가 도달 높이를 깎아 공이 패들 위로
		# 가라앉고, 그동안 elapsed 는 계속 흘러 속도 램프만 오른다.
		if ball_pos.y < 0.0:
			lives -= 1
			out["lost"] = true
			active_item = Item.NONE
			_spawn_dropping()
			break

	if grid.remaining() == 0:
		out["cleared"] = true
	return out

# 표시된 블럭이 파괴되는 순간 떨어진다. 부르는 자리가 이미 "칸이 0 이 됐을
# 때"라 단단 블럭의 마지막 히트에서만 온다 — 여기서 따로 볼 것이 없다.
func _spawn_item(col: int, row: int) -> void:
	var kind := grid.take_item(col, row)
	if kind == Item.NONE:
		return
	var rect := BrickGrid.cell_rect(col, row)
	items.append({"pos": rect.position + rect.size * 0.5, "kind": kind})

# 등속 낙하 + 패들 스윕 상자와의 겹침 판정. 스윕을 쓰는 이유는 공과 같다 —
# 빠르게 지나가는 패들이 아이템을 그냥 통과하면 안 된다.
func _update_items(dt: float, out: Dictionary) -> void:
	var kept: Array[Dictionary] = []
	var sweep := paddle.swept_rect()
	for it in items:
		var p := (it["pos"] as Vector2) - Vector2(0.0, Tuning.ITEM_FALL_SPEED * dt)
		it["pos"] = p
		if sweep.intersects(_item_rect(p)):
			var kind := int(it["kind"])
			(out["items_taken"] as Array).append(kind)
			_apply_item(kind)
			continue
		# 판 아래로 지나간 것은 그냥 사라진다. 놓친 것을 벌하면 아이템이
		# 보상이 아니라 위험이 된다.
		if p.y < -Tuning.ITEM_HALF_SIZE:
			continue
		kept.append(it)
	items = kept

static func _item_rect(p: Vector2) -> Rect2:
	var h := Tuning.ITEM_HALF_SIZE
	return Rect2(p.x - h, p.y - h, h * 2.0, h * 2.0)

# 물리(반사·감쇠)가 없는 직선 볼트. 블럭에 닿으면 한 대 깎고(살아남아도)
# 소모돼 사라진다 — 공처럼 튕기며 남지 않는다. 판 위로 나가도 사라진다.
func _update_lasers(dt: float, out: Dictionary) -> void:
	var kept: Array[Vector2] = []
	for p0 in lasers:
		var p := p0 + Vector2(0.0, Tuning.LASER_SPEED * dt)
		if p.y > Tuning.BOARD_TOP_V:
			continue
		var q := grid.query(p, Tuning.LASER_HALF_SIZE)
		if q["hit"]:
			var kind := grid.get_cell(q["col"], q["row"])
			grid.hit(q["col"], q["row"])
			if grid.get_cell(q["col"], q["row"]) == 0:
				(out["broken"] as Array).append(
					{"col": q["col"], "row": q["row"], "kind": kind})
				out["bricks_hit"] = (out["broken"] as Array).size()
				_spawn_item(q["col"], q["row"])
			continue
		kept.append(p)
	lasers = kept

# P 는 즉발이라 활성 슬롯을 안 거친다. E/S/C/L 은 슬롯에 그대로 덮어쓴다 —
# 이전 것을 끄는 코드가 따로 없는 것은 슬롯이 정수 하나라 새 값이 곧 교체라서다.
# B 는 스코프에서 뺐고, D 는 별도 설계에서 붙는다.
func _apply_item(kind: int) -> void:
	if kind == Item.P:
		lives += 1
	elif kind == Item.E or kind == Item.S or kind == Item.C or kind == Item.L:
		active_item = kind

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
	# 지난 판의 아이템이 새 판 하늘에서 계속 떨어지면 어느 판의 것인지 알 수 없다.
	items.clear()
	lasers.clear()
	# 결정: 지속 효과는 판 클리어 때 풀린다(목숨을 잃어도 안 풀림).
	active_item = Item.NONE
	_attach()

# 전멸. 여기서만 램프가 0 으로 돌아간다. 이것도 공을 잃은 것이므로
# _attach() 대신 낙하로 시작한다.
func reset_run() -> void:
	lives = Tuning.LIVES
	elapsed = 0.0
	stage_index = 0
	grid = StageGen.stage(stage_index)
	items.clear()
	lasers.clear()
	active_item = Item.NONE
	_spawn_dropping()
