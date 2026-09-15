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
	_test_last_life_shows_game_over()
	_test_touching_the_game_over_screen_restarts()
	_test_clear_and_run_over_in_one_frame_keeps_stage_zero()
	_test_clearing_a_stage_advances_the_board_and_hud()
	_test_stage_label_follows_the_stage_index()
	_test_title_screen_blocks_play_until_touched()
	_test_physics_gated_until_started()
	_test_warm_up_primes_the_trail_then_clears_it()
	_test_ignition_flashes_the_screen()
	await _test_the_pause_button_freezes_and_resumes()
	await _test_resuming_does_not_launch_the_ball()
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
	# 끌어내렸다 놓아 튕겨 오르는 패들이 공을 실어 보내게 한다.
	g._target = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	for i in 40:
		g.step_once(1.0 / 120.0)
	g._target.y = Tuning.PADDLE_HOME_V
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

# 마지막 목숨을 잃으면 게임오버 화면이 뜨고 거기서 멈춘다. 예전에는 말없이
# 처음부터 다시 시작해서, 플레이어는 자기가 진 것인지 화면이 튄 것인지
# 구별할 수 없었다.
func _test_last_life_shows_game_over() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	g._state = g.State.PLAYING
	assert(not g.game_over_screen.visible, "시작부터 게임오버 화면이 떠 있다")
	g.field.stage_index = 2
	g.field.lives = 1
	g.field.attached = false
	g.field.ball_pos = Vector2(4.0, 2.5)
	g.field.ball_vel = Vector2(0.0, -5.0)
	for i in 240:
		g.step_once(1.0 / 120.0)
		if g.field.lives <= 0:
			break
	assert(g.field.lives == 0, "공이 데드존까지 안 내려갔다: 목숨 %d" % g.field.lives)
	assert(g._state == g.State.OVER, "목숨이 다 됐는데 게임오버 상태가 아니다")
	assert(g.game_over_screen.visible, "게임오버인데 화면이 안 떴다")
	# 어디까지 갔는지가 이 화면의 유일한 성적표다. HUD 와 같은 1 기반 번호를 쓴다.
	assert(g.game_over_stage.text == "판 3 까지",
		"게임오버 화면의 판 번호가 틀렸다: %s" % g.game_over_stage.text)
	# 게임오버인데 물리가 계속 돌면 뒤에서 공이 혼자 튀어 다닌다.
	var before: Vector2 = g.field.ball_pos
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos == before, "게임오버인데 공이 움직였다")
	g.free()

# 게임오버 화면은 터치를 기다렸다가 처음부터 다시 시작한다.
func _test_touching_the_game_over_screen_restarts() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	g._state = g.State.PLAYING
	g.field.stage_index = 2
	g.field.grid.hit(0, 0)
	g.field.lives = 1
	g.field.attached = false
	g.field.ball_pos = Vector2(4.0, 2.5)
	g.field.ball_vel = Vector2(0.0, -5.0)
	for i in 240:
		g.step_once(1.0 / 120.0)
		if g._state == g.State.OVER:
			break
	assert(g._state == g.State.OVER, "게임오버까지 안 갔다")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	g._unhandled_input(touch)
	assert(g._state == g.State.PLAYING, "터치했는데 다시 시작 안 했다")
	assert(not g.game_over_screen.visible, "다시 시작했는데 게임오버 화면이 남았다")
	assert(g.field.lives == Tuning.LIVES,
		"다시 시작했는데 목숨이 안 돌아왔다: %d" % g.field.lives)
	assert(g.field.stage_index == 0,
		"다시 시작했는데 판 번호가 안 돌아갔다: %d" % g.field.stage_index)
	assert(g.field.grid.cells == StageGen.stage(0).cells,
		"다시 시작인데 0 판 배치가 아니다: 남은 블럭 %d" % g.field.grid.remaining())
	assert(g.lives_label.text == "목숨 %d" % Tuning.LIVES,
		"HUD 가 0 목숨을 그대로 보여준다: %s" % g.lives_label.text)
	g.free()

# step() 은 한 프레임에 lost 와 cleared 를 함께 낼 수 있다 — 서브스텝 루프가 lost 로
# 빠져나와도 remaining() 검사는 그대로 돌기 때문이다. 그때 게임오버로 멈춘 판을
# 같은 프레임의 클리어가 넘겨 버리면, 화면은 게임오버인데 뒤에서 다음 판이 깔린다.
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
	assert(g._state == g.State.OVER, "목숨이 다 됐는데 게임오버가 아니다")
	assert(g.field.stage_index == 4,
		"게임오버로 멈춘 판을 같은 프레임의 클리어가 넘겨 버렸다: %d" % g.field.stage_index)
	# 다시 시작하면 그때 0 판으로 돌아간다.
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	g._unhandled_input(touch)
	assert(g.field.stage_index == 0,
		"다시 시작했는데 0 판이 아니다: %d" % g.field.stage_index)
	assert(g.field.lives == Tuning.LIVES,
		"다시 시작했는데 목숨이 안 돌아왔다: %d" % g.field.lives)
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
	assert(g._state == g.State.TITLE, "시작 전인데 이미 시작 상태다")
	assert(g.title_screen.visible, "시작 전인데 타이틀 화면이 안 보인다")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	g._unhandled_input(touch)
	assert(g._state == g.State.PLAYING, "터치했는데 시작 상태로 안 바뀌었다")
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
	g._state = g.State.PLAYING
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos != before, "시작했는데 물리가 안 돈다")
	g.free()

# 트레일 재질도 첫 그리기에 셰이더 컴파일이 걸린다. 그 순간이 첫 발사
# 직후라 공이 막 빨라지는 시점에 프레임이 멎는다. 타이틀 화면에서 미리
# 치르되, 시작할 때는 옛 점이 남아 첫 궤적과 한 줄로 이어지면 안 된다.
func _test_warm_up_primes_the_trail_then_clears_it() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	# 리본은 점이 둘은 있어야 삼각형이 생긴다 — 하나면 그려지지도 않는다.
	assert(g._trail.point_count() >= 2,
		"타이틀 화면에서 트레일이 안 구워졌다: %d" % g._trail.point_count())
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	g._unhandled_input(touch)
	assert(g._trail.point_count() == 0,
		"시작했는데 워밍업 점이 남았다 — 첫 궤적이 옛 자리와 이어진다: %d"
		% g._trail.point_count())
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

# 점화는 몇 프레임 만에 지나가는 사건이라 공 색만으로는 놓치기 쉽다. 화면이
# 한 번 번쩍여야 "방금 내가 잘 받았다"가 손가락과 연결된다.
func _test_ignition_flashes_the_screen() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	g._ready()
	assert(is_zero_approx(g.fire_flash.color.a),
		"시작부터 화면이 덮여 있다: %f" % g.fire_flash.color.a)
	# 패들 정중앙 바로 위로 떨어뜨린다 — 스윗스팟 판정이 붙는 자리다.
	g.field.attached = false
	g.field.ball_pos = Vector2(g.field.paddle.pos.x,
		g.field.paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS + 0.05)
	g.field.ball_vel = Vector2(0.0, -6.0)
	var flashed := false
	for i in 60:
		g.step_once(1.0 / 120.0)
		if g.fire_flash.color.a > 0.0:
			flashed = true
			break
	assert(flashed, "정중앙으로 받았는데 화면이 안 번쩍였다")
	assert(g.field.burning, "번쩍였는데 공에 불이 안 붙었다")
	g.free()

# 일시정지 버튼은 Button 이 아니라 그냥 라벨이고, 판정은 _unhandled_input 안에서
# 사각형으로 한다. 터치 하나가 GUI 와 게임 조작 두 곳으로 갈라지지 않게 하려는
# 것이다 — 갈라지면 어느 쪽이 먼저 먹었는지에 따라 패들이 튄다.
#
# get_global_rect() 는 레이아웃이 한 번 돌아야 값이 선다. process_frame 을
# 기다리는 이유다.
func _test_the_pause_button_freezes_and_resumes() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	await process_frame
	g._state = g.State.PLAYING
	g.field.attached = false
	g.field.ball_pos = Vector2(0.0, 5.0)
	g.field.ball_vel = Vector2(0.0, 3.0)
	assert(not g.pause_screen.visible, "시작부터 일시정지 화면이 떠 있다")
	var rect: Rect2 = g.pause_button.get_global_rect()
	assert(rect.size.x > 0.0 and rect.size.y > 0.0,
		"일시정지 버튼에 크기가 없다 — 손가락이 닿을 자리가 없다: %s" % rect)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = rect.get_center()
	g._unhandled_input(tap)
	assert(g._state == g.State.PAUSED, "일시정지 버튼을 눌렀는데 안 멈췄다")
	assert(g.pause_screen.visible, "멈췄는데 일시정지 화면이 안 떴다")
	var before: Vector2 = g.field.ball_pos
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos == before, "일시정지인데 공이 움직였다")
	# 멈춘 동안의 드래그가 패들 타깃을 옮기면, 재개하는 순간 패들이 순간이동한다.
	var target_before: Vector2 = g._target
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(10.0, 10.0)
	g._unhandled_input(drag)
	assert(g._target == target_before,
		"일시정지인데 드래그가 패들 타깃을 옮겼다: %s" % g._target)
	g._unhandled_input(tap)
	assert(g._state == g.State.PLAYING, "다시 눌렀는데 재개가 안 됐다")
	assert(not g.pause_screen.visible, "재개했는데 일시정지 화면이 남았다")
	g._physics_process(1.0 / 120.0)
	assert(g.field.ball_pos != before, "재개했는데 물리가 안 돈다")
	g.free()

# 재개시킨 그 손가락의 뗌이 게임 조작으로 새면 스프링 발사가 걸려 공이
# 제멋대로 나간다. 버튼 자리의 터치는 누름도 뗌도 전부 여기서 끝나야 한다.
func _test_resuming_does_not_launch_the_ball() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	await process_frame
	g._state = g.State.PLAYING
	var center: Vector2 = g.pause_button.get_global_rect().get_center()
	var target_before: Vector2 = g._target
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = center
	g._unhandled_input(press)
	g._unhandled_input(press)
	assert(g._state == g.State.PLAYING, "두 번 눌러 재개한 상태가 아니다")
	assert(g.field.attached and not g.field.riding,
		"이 테스트의 전제가 깨졌다 — 공이 이미 떠났다")
	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.position = center
	g._unhandled_input(release)
	# riding 을 본다 — release_ball() 은 attached 를 끄지 않고 공을 패들에 얹은
	# 채로 놓기 때문에, attached 만 보면 발사된 것을 못 잡는다.
	assert(not g.field.riding, "버튼에서 손을 뗐는데 공이 발사됐다")
	# 뗌으로도 토글되면 누를 때마다 정지/재개가 두 번씩 뒤집혀 버튼이 안 먹는 것처럼 보인다.
	assert(g._state == g.State.PLAYING, "버튼에서 손을 뗐는데 다시 멈췄다")
	# 버튼 자리는 판 꼭대기 구석이다. 여기가 패들 타깃이 되면 패들이 판 밖으로 뛴다.
	assert(g._target == target_before,
		"일시정지 버튼을 누른 자리가 패들 타깃이 됐다: %s" % g._target)
	g.free()
