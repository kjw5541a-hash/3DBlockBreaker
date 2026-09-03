extends SceneTree

func _initialize() -> void:
	_run()

# 헤드리스 단발 스크립트는 _initialize() 안에서는 아직 트리가 "활성화"
# 되지 않는다 (is_inside_tree() 가 false, 카메라도 월드에 안 묶인다).
# 화면 좌표 역투영은 카메라가 월드에 들어가 있어야 하므로 process_frame
# 을 한 번 기다려 트리를 실제로 돌린다.
func _run() -> void:
	_test_scene_loads_and_runs()
	await _test_screen_point_maps_to_board()
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
	# 물리 스텝을 손으로 돌린다. 헤드리스에는 _physics_process 가
	# 돌아갈 프레임 루프가 없다.
	for i in 240:
		g.step_once(1.0 / 120.0)
	assert(g.field.lives <= Tuning.LIVES, "목숨이 늘어났다")
	assert(g.field.ball_pos.y >= 0.0, "공이 데드존에 남아 있다")
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
