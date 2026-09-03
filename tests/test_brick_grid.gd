extends SceneTree

func _initialize() -> void:
	_test_index_is_unique()
	_test_cell_rects_tile_the_zone()
	_test_fill_and_hit()
	_test_query_face_normal()
	_test_query_corner_normal()
	_test_query_misses_empty_cell()
	_test_no_tunneling_at_max_speed()
	_test_gap_between_bricks_does_not_thrash()
	print("test_brick_grid: OK")
	quit()

func _test_index_is_unique() -> void:
	var seen := {}
	for row in Tuning.BRICK_ROWS:
		for col in Tuning.BRICK_COLS:
			var i := BrickGrid.index(col, row)
			assert(i >= 0 and i < Tuning.BRICK_COLS * Tuning.BRICK_ROWS,
				"인덱스 범위 밖: %d" % i)
			assert(not seen.has(i), "인덱스 충돌: %d" % i)
			seen[i] = true
	assert(seen.size() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS, "칸 수가 안 맞는다")

func _test_cell_rects_tile_the_zone() -> void:
	var first := BrickGrid.cell_rect(0, 0)
	assert(is_equal_approx(first.position.x, -Tuning.BOARD_HALF_WIDTH),
		"첫 열이 판 왼쪽 끝에서 시작하지 않는다: %s" % first)
	assert(is_equal_approx(first.position.y, Tuning.BRICK_BOTTOM_V),
		"첫 줄이 격자 아래끝에서 시작하지 않는다: %s" % first)
	var last := BrickGrid.cell_rect(Tuning.BRICK_COLS - 1, Tuning.BRICK_ROWS - 1)
	assert(is_equal_approx(last.position.x + last.size.x, Tuning.BOARD_HALF_WIDTH),
		"마지막 열이 판 오른쪽 끝과 안 맞는다: %s" % last)
	assert(is_equal_approx(last.position.y + last.size.y, Tuning.BRICK_TOP_V),
		"마지막 줄이 격자 위끝과 안 맞는다: %s" % last)

func _test_fill_and_hit() -> void:
	var g := BrickGrid.new()
	assert(g.remaining() == 0, "새 격자는 비어 있어야 한다")
	g.fill_all(1)
	assert(g.remaining() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS, "다 안 찼다")
	g.hit(3, 2)
	assert(g.get_cell(3, 2) == 0, "맞은 칸이 안 비었다")
	assert(g.get_cell(4, 2) == 1, "옆 칸이 같이 지워졌다")
	assert(g.remaining() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS - 1, "남은 수가 틀렸다")
	assert(g.get_cell(-1, 0) == 0 and g.get_cell(0, 999) == 0, "범위 밖은 0이어야 한다")

func _test_query_face_normal() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var r := BrickGrid.cell_rect(5, 0)
	# 최하단 줄의 아래 면에 아래쪽에서 닿는다.
	var center := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS * 0.8)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "면에 닿았는데 못 잡았다")
	assert(q["normal"].is_equal_approx(Vector2(0.0, -1.0)),
		"아래 면 법선이 틀렸다: %s" % q["normal"])
	assert(q["row"] == 0, "줄 번호가 틀렸다: %d" % q["row"])

func _test_query_corner_normal() -> void:
	var g := BrickGrid.new()
	# 블럭 하나만 남기고 그 꼭짓점에 비스듬히 닿는다.
	g.fill_all(0)
	g.cells[BrickGrid.index(5, 0)] = 1
	var r := BrickGrid.cell_rect(5, 0)
	var corner := Vector2(r.position.x, r.position.y)
	var center := corner + Vector2(-0.12, -0.12)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "꼭짓점에 닿았는데 못 잡았다")
	# 면 법선이 아니라 중심-꼭짓점 방향이어야 한다.
	assert(q["normal"].x < -0.5 and q["normal"].y < -0.5,
		"꼭짓점 법선이 면 법선으로 나왔다: %s" % q["normal"])

func _test_query_misses_empty_cell() -> void:
	var g := BrickGrid.new()
	var r := BrickGrid.cell_rect(5, 0)
	var q := g.query(Vector2(r.position.x + 0.5, r.position.y + 0.5), Tuning.BALL_RADIUS)
	assert(not q["hit"], "빈 격자에서 충돌이 나왔다")

# 최대 속도 공을 서브스텝으로 쪼개 격자에 던진다. 한 번은 잡혀야 한다.
func _test_no_tunneling_at_max_speed() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var dt := 1.0 / 120.0
	var pos := Vector2(0.1, Tuning.BRICK_BOTTOM_V - 2.0)
	var vel := Vector2(0.0, Tuning.V_MAX)
	var hit_count := 0
	for frame in 60:
		var n := BallPhysics.substeps(vel.length(), dt)
		var sub := dt / float(n)
		for s in n:
			vel = BallPhysics.step_vel(vel, sub)
			pos = BallPhysics.step_pos(pos, vel, sub)
			var q := g.query(pos, Tuning.BALL_RADIUS)
			if q["hit"]:
				hit_count += 1
				g.hit(q["col"], q["row"])
				vel = BallPhysics.reflect(vel, q["normal"])
				pos += q["normal"] * q["depth"]
		if pos.y > Tuning.BRICK_TOP_V + 1.0:
			break
	assert(hit_count > 0, "최대 속도 공이 격자를 통과했다 — 터널링")

# 인접한 두 블럭 사이의 이음매를 스쳐도 법선이 튀지 않아야 한다.
func _test_gap_between_bricks_does_not_thrash() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var seam_u := BrickGrid.cell_rect(5, 0).position.x
	var center := Vector2(seam_u, Tuning.BRICK_BOTTOM_V - Tuning.BALL_RADIUS * 0.8)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "이음매 아래에서 못 잡았다")
	assert(q["normal"].y < -0.3,
		"이음매에서 법선이 아래를 안 가리킨다 — 공이 격자 안으로 빨려든다: %s" % q["normal"])
	assert(is_equal_approx(q["normal"].length(), 1.0),
		"법선이 단위벡터가 아니다: %f" % q["normal"].length())
