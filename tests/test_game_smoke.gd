extends SceneTree

func _initialize() -> void:
	_run()

# 헤드리스 단발 스크립트는 _initialize() 안에서는 아직 트리가 "활성화"
# 되지 않는다 (is_inside_tree() 가 false, 카메라도 월드에 안 묶인다).
# 화면 좌표 역투영은 카메라가 월드에 들어가 있어야 하므로 process_frame
# 을 한 번 기다려 트리를 실제로 돌린다.
func _run() -> void:
	_test_scene_loads_and_runs()
	_test_life_loss_clears_trail()
	_test_last_life_restarts()
	_test_clear_and_run_over_in_one_frame_keeps_stage_zero()
	_test_clearing_a_stage_advances_the_board_and_hud()
	_test_stage_label_follows_the_stage_index()
	_test_title_screen_blocks_play_until_touched()
	_test_physics_gated_until_started()
	await _test_screen_point_maps_to_board()
	await _test_board_fits_in_camera()
	print("test_game_smoke: OK")
	quit()

func _test_scene_loads_and_runs() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	assert(packed != null, "게임 씬을 못 불러왔다")
	var g := packed.instantiate()
	root.add_child(g)
	# NOTIFICATION_READY가 아직 안 왔다(트리가 안 돌았다). @onready 필드를
	# 채우려고 손으로 부른다. 이 테스트는 카메라/월드가 필요 없어 이걸로
	# 충분하다.
	g._ready()
	# 쏘지 않으면 field.step() 이 attached 경로로 조기 반환해 240 프레임을
	# 돌려도 물리가 한 번도 안 돈다 — 단언이 자명 참이 된다. 새 조작대로
	# 끌어내렸다 놓아 올라오는 패들이 공을 치게 한다.
	g._target = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	for i in 40:
		g.step_once(1.0 / 120.0)
	g._target.y = Tuning.PADDLE_BAND_MAX_V
	g.field.paddle.start_spring()
	g.field.release_ball()
	# 물리 스텝을 손으로 돌린다. 헤드리스에는 _physics_process 가
	# 돌아갈 프레임 루프가 없다.
	for i in 240:
		g.step_once(1.0 / 120.0)
	assert(g.field.lives <= Tuning.LIVES, "목숨이 늘어났다")
	assert(g.field.ball_pos.y >= 0.0, "공이 데드존에 남아 있다")
	g.free()

# 목숨을 잃는 순간 트레일이 지워지는지. 안 지우면 죽은 자리의 리본이
# 남아 다음 발사 때 옛 점과 새 점이 이어진다.
func _test_life_loss_clears_trail() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	# 패들 x 범위 밖에서 떨어뜨린다 — 도중에 튕기면 목숨을 안 잃는다.
	g.field.attached = false
	g.field.ball_pos = Vector2(4.0, 2.5)
	g.field.ball_vel = Vector2(0.0, -5.0)
	var lost := false
	var seen := 0
	for i in 240:
		g.step_once(1.0 / 120.0)
		seen = maxi(seen, g._trail.point_count())
		if g.field.attached:
			lost = true
			break
	assert(lost, "공이 데드존까지 안 내려갔다")
	assert(seen > 0, "떨어지는 동안 트레일이 쌓이질 않았다 — 테스트가 헛돈다")
	assert(g._trail.point_count() == 0,
		"목숨을 잃은 뒤에도 트레일 점이 남아 있다: %d" % g._trail.point_count())
	g.free()

# 마지막 목숨을 잃으면 목숨과 블럭이 모두 초기 상태로 돌아가야 한다.
# 1단계에는 게임오버 화면이 없으므로 이게 유일한 종료 처리다.
func _test_last_life_restarts() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	g.field.lives = 1
	g.field.grid.hit(0, 0)
	g.field.attached = false
	g.field.ball_pos = Vector2(4.0, 2.5)
	g.field.ball_vel = Vector2(0.0, -5.0)
	var lost := false
	for i in 240:
		g.step_once(1.0 / 120.0)
		if g.field.attached:
			lost = true
			break
	assert(lost, "공이 데드존까지 안 내려갔다")
	assert(g.field.lives == Tuning.LIVES,
		"마지막 목숨을 잃었는데 목숨이 안 돌아왔다: %d" % g.field.lives)
	assert(g.field.grid.cells == StageGen.stage(0).cells,
		"재시작인데 0 판 배치가 아니다: 남은 블럭 %d" % g.field.grid.remaining())
	assert(g.field.stage_index == 0,
		"재시작인데 판 번호가 안 돌아갔다: %d" % g.field.stage_index)
	assert(g.lives_label.text == "목숨 %d" % Tuning.LIVES,
		"HUD 가 0 목숨을 그대로 보여준다: %s" % g.lives_label.text)
	g.free()

# step() 은 한 프레임에 lost 와 cleared 를 함께 낼 수 있다 — 서브스텝 루프가 lost 로
# 빠져나와도 remaining() 검사는 그대로 돌기 때문이다. 그때 전멸 복구가 되돌린 판을
# 같은 프레임의 클리어가 덮어쓰면, 플레이어는 0 판이 아니라 1 판에서 다시 시작한다.
func _test_clear_and_run_over_in_one_frame_keeps_stage_zero() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	g.field.stage_index = 4
	g.field.lives = 1
	# 빈 격자 + 데드존 아래의 공. 이 한 프레임이 lost 와 cleared 를 동시에 낸다.
	g.field.grid.fill_all(0)
	g.field.attached = false
	g.field.dropping = false
	g.field.ball_pos = Vector2(0.0, -0.5)
	g.field.ball_vel = Vector2(0.0, -1.0)
	# g 의 정적 타입이 Node 라 g.field 는 Variant 로 잡힌다 — := 추론이 안 먹어
	# 타입을 명시한다(위 screen_to_board 테스트와 같은 이유).
	var r: Dictionary = g.field.step(g.field.paddle.pos, 1.0 / 120.0)
	assert(bool(r["lost"]) and bool(r["cleared"]),
		"이 테스트의 전제가 깨졌다 — 한 프레임에 두 깃발이 같이 안 섰다: %s" % r)

	# 전제를 확인했으니 같은 상황을 step_once() 로 다시 태운다. 위 호출이 이미
	# dropping 을 켜 놨으므로 다시 꺼야 한다 — 안 그러면 field.step() 이 낙하
	# 분기로 조기 반환해 lost/cleared 가 둘 다 안 서고 이 테스트가 헛돈다.
	g.field.stage_index = 4
	g.field.lives = 1
	g.field.grid.fill_all(0)
	g.field.attached = false
	g.field.dropping = false
	g.field.ball_pos = Vector2(0.0, -0.5)
	g.field.ball_vel = Vector2(0.0, -1.0)
	g.step_once(1.0 / 120.0)
	assert(g.field.stage_index == 0,
		"전멸로 되돌린 판을 같은 프레임의 클리어가 덮어썼다: %d" % g.field.stage_index)
	assert(g.field.lives == Tuning.LIVES,
		"전멸 복구가 안 됐다: %d" % g.field.lives)
	assert(g.field.grid.cells == StageGen.stage(0).cells,
		"되돌린 뒤 배치가 0 판이 아니다")
	g.free()

# 클리어 분기 전체가 game.gd 에서 사라져도 지금은 아무 테스트도 안 터진다.
# PlayField.next_stage() 는 단위로만 검사되고, 스모크는 lost+cleared 가드만 탄다.
func _test_clearing_a_stage_advances_the_board_and_hud() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	# 데드존에서 먼 곳에서 마지막 블럭이 사라진 상황.
	g.field.grid.fill_all(0)
	g.field.attached = false
	g.field.ball_pos = Vector2(0.0, 5.0)
	g.field.ball_vel = Vector2(0.0, 4.0)
	g.step_once(1.0 / 120.0)
	assert(g.field.stage_index == 1,
		"클리어했는데 판이 안 넘어갔다: %d" % g.field.stage_index)
	assert(g.field.grid.cells == StageGen.stage(1).cells, "1 판 배치가 아니다")
	assert(g.field.attached, "새 판인데 공이 안 붙었다")
	assert(g.board.brick_count() > 0, "새 판 블럭이 화면에 안 올라왔다")
	assert(g.stage_label.text == "판 2",
		"판이 넘어갔는데 라벨이 안 따라왔다: %s" % g.stage_label.text)
	g.free()

# 게임 이름과 "Touch to Start" 화면이 첫 터치 전까지 입력을 막아야 한다 —
# 안 그러면 손가락이 화면에 닿는 순간 타이틀도 못 보고 패들이 움직인다.
func _test_title_screen_blocks_play_until_touched() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	assert(not g._started, "시작 전인데 이미 시작 상태다")
	assert(g.title_screen.visible, "시작 전인데 타이틀 화면이 안 보인다")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	g._unhandled_input(touch)
	assert(g._started, "터치했는데 시작 상태로 안 바뀌었다")
	assert(not g.title_screen.visible, "시작했는데 타이틀 화면이 안 사라졌다")
	g.free()

# _physics_process 자체가 타이틀 화면 동안 물리를 돌리면 안 된다. step_once
# 를 직접 부르는 다른 테스트들은 이 가드를 우회하므로 여기서 따로 본다.
func _test_physics_gated_until_started() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	g.field.attached = false
	g.field.ball_pos = Vector2(0.0, 5.0)
	g.field.ball_vel = Vector2(0.0, 3.0)
	var before: Vector2 = g.field.ball_pos
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos == before, "타이틀 화면인데 공이 움직였다")
	g._started = true
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos != before, "시작했는데 물리가 안 돈다")
	g.free()

func _test_screen_point_maps_to_board() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	# Camera3D.project_ray_origin/normal 은 카메라가 월드에 들어가 있어야
	# 한다 — 프레임을 하나 흘려보내 트리를 활성화한다(이 과정에서 진짜
	# NOTIFICATION_READY도 함께 온다).
	await process_frame
	# root(Window) 자체가 뷰포트다. get_viewport() 는 부모 뷰포트를 찾는
	# 메서드라 루트에서 부르면 null 이 나온다.
	var vp := root.get_visible_rect().size
	# g 의 정적 타입이 instantiate() 의 선언 반환형인 Node 라 GDScript
	# 정적 분석기가 screen_to_board 를 못 찾아 := 추론이 막힌다. 타입을
	# 명시해 우회한다.
	var center: Vector2 = g.screen_to_board(vp * 0.5)
	var right: Vector2 = g.screen_to_board(Vector2(vp.x * 0.9, vp.y * 0.5))
	assert(right.x > center.x, "화면 오른쪽이 판 오른쪽으로 안 간다: %f vs %f" % [right.x, center.x])
	var low: Vector2 = g.screen_to_board(Vector2(vp.x * 0.5, vp.y * 0.9))
	var high: Vector2 = g.screen_to_board(Vector2(vp.x * 0.5, vp.y * 0.1))
	assert(high.y > low.y, "화면 위쪽이 판 안쪽(v 큰 쪽)으로 안 간다: %f vs %f" % [high.y, low.y])
	g.free()

# 판 네 귀퉁이가 화면 안에 들어오는지. Camera3D 의 keep_aspect 기본값은
# KEEP_HEIGHT 라 fov 가 세로각이고, 720x1280 세로 화면에서는 가로 화각이
# 절반 이하로 좁아진다 — 눈으로 안 보면 좌우 벽과 위쪽 블럭 줄이 조용히
# 화면 밖으로 나간다. 기울기·카메라·fov 중 뭘 건드려도 여기서 걸린다.
#
# is_position_in_frustum() 을 쓰지 않는 이유: 헤드리스 창은 64x64 라
# 종횡비가 1.0 이다. 실제로 출하되는 해상도로 판정해야 의미가 있어서
# 프로젝트 설정의 해상도로 화각을 직접 계산한다.
func _test_board_fits_in_camera() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	await process_frame
	var board: Node3D = g.board
	var cam: Camera3D = g.camera
	assert(is_equal_approx(board.rotation.x, deg_to_rad(Tuning.BOARD_TILT_DEG)),
		"씬의 판 기울기가 Tuning.BOARD_TILT_DEG 와 다르다: %f vs %f"
		% [rad_to_deg(board.rotation.x), Tuning.BOARD_TILT_DEG])

	var aspect := (
		float(ProjectSettings.get_setting("display/window/size/viewport_width"))
		/ float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var half_h: float
	var half_v: float
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		half_h = deg_to_rad(cam.fov * 0.5)
		half_v = atan(tan(half_h) / aspect)
	else:
		half_v = deg_to_rad(cam.fov * 0.5)
		half_h = atan(tan(half_v) * aspect)

	var inv := cam.global_transform.affine_inverse()
	# 벽 메시가 판 경계 바깥으로 두께만큼 더 나간다 — 그것까지 보여야 한다.
	var edge := Tuning.BOARD_HALF_WIDTH + BoardView.WALL_THICKNESS
	for u in [-edge, edge]:
		for v in [0.0, Tuning.BOARD_TOP_V]:
			var world: Vector3 = board.global_transform * BoardView.board_to_local(Vector2(u, v))
			var l: Vector3 = inv * world
			assert(l.z < 0.0, "판 귀퉁이 (%f, %f) 가 카메라 뒤에 있다" % [u, v])
			var av := atan2(l.y, -l.z)
			var ah := atan2(absf(l.x), -l.z)
			assert(av < half_v, "판 귀퉁이 (%f, %f) 가 위아래로 화면 밖이다: %f도 > %f도"
				% [u, v, rad_to_deg(av), rad_to_deg(half_v)])
			assert(ah < half_h, "판 귀퉁이 (%f, %f) 가 좌우로 화면 밖이다: %f도 > %f도"
				% [u, v, rad_to_deg(ah), rad_to_deg(half_h)])
	g.free()

# 판 번호가 안 보이면 절차 생성이 진행되고 있다는 유일한 단서가 없다.
# 배치가 매번 달라 보이는 것만으로는 "다음 판"인지 "같은 판 다시"인지
# 구별할 수 없다.
func _test_stage_label_follows_the_stage_index() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	assert(g.stage_label.text == "판 1",
		"첫 판 표시가 틀렸다: %s" % g.stage_label.text)
	# 판을 깼다고 치고 HUD 갱신 경로를 그대로 태운다.
	g.field.next_stage()
	g.board.build(g.field.grid)
	g._update_hud()
	assert(g.stage_label.text == "판 2",
		"판이 넘어갔는데 표시가 안 따라왔다: %s" % g.stage_label.text)
	g.field.reset_run()
	g._update_hud()
	assert(g.stage_label.text == "판 1",
		"처음부터 다시인데 판 번호가 안 돌아왔다: %s" % g.stage_label.text)
	g.free()
