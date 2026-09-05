extends SceneTree

func _initialize() -> void:
	_test_local_mapping()
	_test_tilted_board_lifts_far_end()
	_test_brick_heights_differ_by_kind()
	_test_hard_brick_darkens_when_hit()
	_test_indestructible_is_gold()
	_test_hard_brick_mesh_updates_on_hit()
	_test_build_and_remove_bricks()
	_test_walls_mark_the_boundary()
	print("test_board_view: OK")
	quit()

# (u, v) 는 판 로컬 평면 좌표다. 판 노드가 기울어져 있으므로 변환
# 자체는 기울기를 몰라야 한다.
func _test_local_mapping() -> void:
	var p := BoardView.board_to_local(Vector2(2.0, 7.0), 0.0)
	assert(is_equal_approx(p.x, 2.0), "u 가 x 로 안 갔다: %s" % p)
	assert(is_equal_approx(p.z, -7.0), "v 가 -z 로 안 갔다: %s" % p)
	assert(is_equal_approx(p.y, 0.0), "높이가 0 이 아니다: %s" % p)
	var h := BoardView.board_to_local(Vector2(0.0, 0.0), 0.5)
	assert(is_equal_approx(h.y, 0.5), "높이 인자가 무시됐다: %s" % h)

# 판을 기울여 놓으면 블럭 쪽 끝이 실제로 들려야 입체로 읽힌다.
func _test_tilted_board_lifts_far_end() -> void:
	var board := Node3D.new()
	board.rotation = Vector3(deg_to_rad(Tuning.BOARD_TILT_DEG), 0.0, 0.0)
	var near := board.transform * BoardView.board_to_local(Vector2(0.0, 0.0), 0.0)
	var far := board.transform * BoardView.board_to_local(Vector2(0.0, Tuning.BOARD_TOP_V), 0.0)
	assert(far.y > near.y + 1.0,
		"판을 기울였는데 먼 쪽이 안 들렸다: near=%f far=%f" % [near.y, far.y])
	board.free()

func _test_brick_heights_differ_by_kind() -> void:
	assert(BoardView.brick_height(1) > 0.0, "일반 블럭 높이가 0 이다")
	assert(BoardView.brick_height(3) > BoardView.brick_height(1),
		"단단한 블럭이 더 두꺼워야 한다")
	assert(is_equal_approx(BoardView.brick_height(2), BoardView.brick_height(3)),
		"단단 블럭은 남은 히트가 줄어도 두께가 같아야 한다 — 두께는 종류를 뜻한다")
	assert(BoardView.brick_height(BrickGrid.INDESTRUCTIBLE) > BoardView.brick_height(3),
		"불괴 블럭이 가장 두꺼워야 한다")

func _test_build_and_remove_bricks() -> void:
	var view := BoardView.new()
	var g := BrickGrid.new()
	g.fill_all(1)
	view.build(g)
	assert(view.brick_count() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS,
		"블럭 메시 수가 틀렸다: %d" % view.brick_count())
	g.hit(4, 2)
	view.refresh_bricks(g)
	assert(view.brick_count() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS - 1,
		"깬 블럭 메시가 안 사라졌다: %d" % view.brick_count())
	view.free()

# "공간은 남아 있는데 사실은 벽" 을 없애려는 것이다. 벽 세 개가 있고,
# 안쪽 면이 정확히 판 경계에 붙어 있어야 경계가 거짓말을 안 한다.
func _test_walls_mark_the_boundary() -> void:
	var view := BoardView.new()
	var g := BrickGrid.new()
	g.fill_all(1)
	view.build(g)
	assert(view.wall_count() == 3, "벽이 세 개가 아니다: %d" % view.wall_count())
	view.build(g)
	assert(view.wall_count() == 3, "다시 지을 때 벽이 늘었다: %d" % view.wall_count())
	assert(BoardView.WALL_THICKNESS > 0.0 and BoardView.WALL_HEIGHT > 0.0,
		"벽이 안 보이는 크기다")
	for w in view._walls:
		var size: Vector3 = (w.mesh as BoxMesh).size
		# 좌우 벽만 본다(상단 벽은 가로로 길다).
		if size.x > size.z:
			continue
		var inner := absf(w.position.x) - size.x * 0.5
		assert(is_equal_approx(inner, Tuning.BOARD_HALF_WIDTH),
			"벽 안쪽 면이 판 경계와 어긋난다: %f, 경계 %f"
			% [inner, Tuning.BOARD_HALF_WIDTH])
	view.free()

# 남은 히트 수가 눈에 보여야 한다. 안 그러면 은색 블럭이 몇 대 남았는지
# 세고 있어야 한다.
func _test_hard_brick_darkens_when_hit() -> void:
	var full := BoardView.brick_color(3, 0)
	var worn := BoardView.brick_color(2, 0)
	assert(worn.v < full.v,
		"단단 블럭이 맞아도 안 어두워진다: %f -> %f" % [full.v, worn.v])

func _test_indestructible_is_gold() -> void:
	var c := BoardView.brick_color(BrickGrid.INDESTRUCTIBLE, 0)
	assert(c.r > c.b and c.g > c.b, "불괴 블럭이 금색이 아니다: %s" % c)

# refresh_bricks() 는 원래 "메시가 이미 있으면 건너뛴다" 였다. 단단 블럭이
# 생기면 그 최적화가 곧 버그가 된다 — 한 대 맞아도 화면이 그대로다.
func _test_hard_brick_mesh_updates_on_hit() -> void:
	var view := BoardView.new()
	var g := BrickGrid.new()
	var i := BrickGrid.index(2, 1)
	g.cells[i] = 3
	view.build(g)
	assert(view.brick_count() == 1, "블럭 하나만 있어야 한다: %d" % view.brick_count())
	var before: Color = ((view._bricks[i] as MeshInstance3D)
		.material_override as StandardMaterial3D).albedo_color
	g.hit(2, 1)
	view.refresh_bricks(g)
	assert(view.brick_count() == 1, "덜 깨진 블럭의 메시가 사라졌다: %d" % view.brick_count())
	var after: Color = ((view._bricks[i] as MeshInstance3D)
		.material_override as StandardMaterial3D).albedo_color
	assert(after.v < before.v,
		"맞은 단단 블럭의 색이 안 바뀌었다: %f -> %f" % [before.v, after.v])
	view.free()
