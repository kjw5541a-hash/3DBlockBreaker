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
	_test_paddle_break_hides_then_restores_the_paddle()
	_test_brick_break_spawns_fragments()
	_test_item_meshes_follow_the_field()
	_test_paddle_mesh_widens_with_enlarge()
	_test_the_paddle_mesh_matches_the_hit_box()
	_test_the_bat_face_looks_at_the_bricks()
	_test_laser_meshes_follow_the_field()
	_test_warm_up_draws_every_item_letter()
	_test_warm_up_hands_the_pool_back_intact()
	_test_the_ball_looks_different_while_it_burns()
	_test_fire_costs_no_new_shader_variant()
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

# 목숨을 잃은 자리를 눈에 보이게 하려는 연출이다. 부서지는 순간 패들이
# 안 보여야 하고, 연출이 끝나면 새 패들처럼 다시 보여야 한다. Tween 은
# 엔진 프레임을 기다려야 진행되므로 custom_step 으로 직접 밀어붙인다.
func _test_paddle_break_hides_then_restores_the_paddle() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var g := BrickGrid.new()
	g.fill_all(0)
	view.build(g)
	assert(view._paddle.visible, "시작부터 패들이 안 보인다 — 테스트 전제가 깨졌다")
	var respawn_tween := view.play_paddle_break()
	assert(not view._paddle.visible, "부서지는 순간인데 패들이 그대로 보인다")
	respawn_tween.custom_step(BoardView._BREAK_DURATION + 0.01)
	assert(view._paddle.visible, "연출이 끝났는데 패들이 안 돌아왔다")
	view.free()

# 블럭이 깨진 자리를 눈에 보이게 하려는 연출이다. 실제 블럭 메시는 이미
# refresh_bricks() 로 지워졌을 자리이므로, 여기서는 조각이 실제로
# 생기는지만 본다.
func _test_brick_break_spawns_fragments() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var g := BrickGrid.new()
	g.fill_all(0)
	view.build(g)
	var before := view.get_child_count()
	view.play_brick_break(2, 1, 3)
	assert(view.get_child_count() > before, "블럭이 깨졌는데 조각이 안 생겼다")
	view.free()

# 아이템이 화면에 안 보이면 떨어지고 있다는 것을 알 방법이 없다. 개수가
# 줄었을 때 메시가 남으면 유령 아이템이 판에 박힌다.
func _test_item_meshes_follow_the_field() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	assert(view.item_count() == 0, "아이템이 없는데 메시가 있다: %d" % view.item_count())

	f.items.append({"pos": Vector2(1.0, 6.0), "kind": Item.P})
	f.items.append({"pos": Vector2(-2.0, 4.0), "kind": Item.E})
	view.sync_items(f)
	assert(view.item_count() == 2, "아이템 둘인데 메시가 %d 개다" % view.item_count())
	assert((view._items[0].get_node("Label") as Label3D).text == "P",
		"P 큐브에 글자 P 가 안 붙었다")
	assert((view._items[1].get_node("Label") as Label3D).text == "E",
		"E 큐브에 글자 E 가 안 붙었다")

	f.items.remove_at(0)
	view.sync_items(f)
	assert(view.item_count() == 1, "아이템이 하나로 줄었는데 메시가 %d 개다" % view.item_count())

	f.items.clear()
	view.sync_items(f)
	assert(view.item_count() == 0, "아이템이 다 사라졌는데 메시가 %d 개 남았다" % view.item_count())
	view.free()

# 눈에 보이는 폭은 메시 크기가 아니라 "메시 폭 x 스케일"이다. 메시가 상자에서
# 조각한 모델로 바뀌어도 이 계약은 그대로 남아야 해서 이렇게 잰다.
func _paddle_world_width(view: BoardView) -> float:
	return view._paddle.mesh.get_aabb().size.x * view._paddle.scale.x

func _test_paddle_mesh_widens_with_enlarge() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	view.sync(f)
	var base_size := _paddle_world_width(view)
	assert(is_equal_approx(base_size, Tuning.PADDLE_HALF_WIDTH * 2.0),
		"기본 상태에서 보이는 폭이 판정 반폭과 다르다: %f" % base_size)
	f.active_item = Item.E
	f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), 1.0 / 120.0)
	view.sync(f)
	var widened_size := _paddle_world_width(view)
	assert(is_equal_approx(widened_size, f.paddle.half_width * 2.0),
		"Enlarge 뒤 보이는 폭이 판정 반폭과 어긋난다: %f vs %f"
		% [widened_size, f.paddle.half_width * 2.0])
	assert(widened_size > base_size,
		"Enlarge 가 활성인데 패들이 그대로다: %f -> %f" % [base_size, widened_size])
	view.free()

# 패들은 이제 Blender 에서 조각한 메시다. 두께와 깊이가 판정 상자와 어긋나면
# 눈으로 받은 자리와 실제로 맞는 자리가 달라진다. 축 변환(Blender Z-up ->
# Godot Y-up)이 틀어지면 바로 여기서 걸린다.
func _test_the_paddle_mesh_matches_the_hit_box() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	var aabb := view._paddle.mesh.get_aabb()
	assert(is_equal_approx(aabb.size.x, Tuning.PADDLE_HALF_WIDTH * 2.0),
		"메시 폭이 판정 폭과 다르다: %f" % aabb.size.x)
	# 판정 상자의 세로 두께는 판 위 높이가 아니라 판을 따라가는 깊이(v)다.
	# board_to_local 이 v 를 -z 로 보내므로 메시의 z 범위가 그 두께여야 한다.
	assert(is_equal_approx(aabb.size.z, Tuning.PADDLE_THICKNESS),
		"메시 깊이가 PADDLE_THICKNESS 와 다르다: %f" % aabb.size.z)
	assert(is_equal_approx(aabb.position.y + aabb.size.y * 0.5, 0.0),
		"메시가 원점 기준으로 안 맞춰져 있다: %f" % aabb.position.y)
	# 프레임과 러버 두 면. 하나로 합쳐지면 러버 색을 따로 못 준다.
	assert(view._paddle.mesh.get_surface_count() == 2,
		"패들 메시 면이 %d 개다 — 프레임/러버 두 면이어야 한다"
		% view._paddle.mesh.get_surface_count())

	# 러버 면은 공이 닿는 윗면이고, 지금까지의 패들 색(0.6, 0.85, 1.0)을 그대로
	# 물려받는다. 파괴 조각도 같은 색이라 둘이 어긋나면 부서질 때 색이 튄다.
	for i in view._paddle.mesh.get_surface_count():
		var is_rubber := view._paddle.mesh.surface_get_material(i).resource_name == "ice"
		var shown := (view._paddle.get_surface_override_material(i) as StandardMaterial3D).albedo_color
		assert(is_rubber == (shown == Color(0.6, 0.85, 1.0)),
			"면 %d 의 색이 뒤바뀌었다 — 러버=%s 인데 색은 %s" % [i, is_rubber, shown])
	view.free()

# 공은 판 평면을 따라 올라왔다 내려온다. 그래서 공이 실제로 때리는 면은
# 카메라를 보는 윗면이 아니라 벽돌 쪽(+v)을 보는 면이다. 배트 면(러버)이
# 거기 붙어 있지 않으면 "넓은 면으로 받는다"는 형태의 의미가 사라진다.
# board_to_local 이 v 를 -z 로 보내므로 러버는 -z 쪽에 있어야 한다.
func _test_the_bat_face_looks_at_the_bricks() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	var mesh := view._paddle.mesh
	var checked := 0
	for i in mesh.get_surface_count():
		if mesh.surface_get_material(i).resource_name != "ice":
			continue
		checked += 1
		var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		var min_z := INF
		for v in verts:
			min_z = minf(min_z, v.z)
		assert(min_z <= mesh.get_aabb().position.z + 0.001,
			"때리는 면이 프레임이다 — 러버가 %f 까지밖에 안 오는데 앞면은 %f 다"
			% [min_z, mesh.get_aabb().position.z])
	# 러버 면이 아예 없으면 위 루프가 한 번도 안 돌아 테스트가 헛통과한다.
	assert(checked == 1, "러버 면이 %d 개다 — 하나여야 한다" % checked)
	view.free()

func _test_laser_meshes_follow_the_field() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	assert(view.laser_count() == 0, "레이저가 없는데 메시가 있다: %d" % view.laser_count())

	f.lasers.append(Vector2(1.0, 6.0))
	f.lasers.append(Vector2(-2.0, 4.0))
	view.sync_lasers(f)
	assert(view.laser_count() == 2, "레이저 둘인데 메시가 %d 개다" % view.laser_count())

	f.lasers.clear()
	view.sync_lasers(f)
	assert(view.laser_count() == 0, "레이저가 다 사라졌는데 메시가 %d 개 남았다" % view.laser_count())
	view.free()

# 웹 빌드는 GL Compatibility 로 떨어져 재질 조합마다 셰이더를 첫 드로우 때
# 컴파일하고, Label3D 는 글자를 처음 그릴 때 64px 로 래스터화한다. 그 비용이
# 아이템이 처음 떨어지는 순간에 몰리면 프레임이 멎는다. 미리 굽는 것이므로
# 글자 하나라도 빠지면 그 아이템에서 끊김이 그대로 남는다 — 전부 확인한다.
func _test_warm_up_draws_every_item_letter() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var g := BrickGrid.new()
	g.fill_all(0)
	view.build(g)
	view.warm_up()
	var label := view._items[0].get_node("Label") as Label3D
	for kind in [Item.P, Item.E, Item.S, Item.C, Item.L]:
		assert(label.text.contains(Item.letter(kind)),
			"워밍업 글자에 %s 가 빠졌다: %s" % [Item.letter(kind), label.text])
	# 실제로 그려져야 컴파일이 걸린다. 숨겨 두면 워밍업이 아무 일도 안 한다.
	assert(view._items[0].visible, "워밍업 아이템이 안 보이면 셰이더가 안 구워진다")
	assert(view._lasers[0].visible, "워밍업 레이저가 안 보이면 셰이더가 안 구워진다")
	# 눈에 띄면 타이틀 화면에 유령 아이템이 떠 있는 꼴이 된다.
	assert(view._items[0].scale.x < 0.1,
		"워밍업 아이템이 실제 크기라 화면에 보인다: %s" % view._items[0].scale)
	assert(view.item_count() == 0,
		"워밍업 메시가 진짜 아이템으로 세어졌다: %d" % view.item_count())
	view.free()

# 워밍업은 풀에 그대로 남아 첫 아이템이 재사용한다 — 그게 컴파일을 한 번만
# 치르는 방법이다. 대신 크기와 글자를 원상복구 못 하면 첫 아이템이 점으로
# 나오거나 글자가 "PESCL" 인 채로 떨어진다.
func _test_warm_up_hands_the_pool_back_intact() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	f.grid.fill_all(0)
	view.build(f.grid)
	view.warm_up()
	view.end_warm_up()
	assert(not view._items[0].visible, "워밍업이 끝났는데 아이템이 화면에 남아 있다")
	assert(not view._lasers[0].visible, "워밍업이 끝났는데 레이저가 화면에 남아 있다")

	f.items.append({"pos": Vector2(1.0, 6.0), "kind": Item.S})
	f.lasers.append(Vector2(0.0, 5.0))
	view.sync_items(f)
	view.sync_lasers(f)
	assert(view._items.size() == 1,
		"워밍업 메시를 안 쓰고 새로 만들었다 — 컴파일을 두 번 친다: %d" % view._items.size())
	assert(view._lasers.size() == 1,
		"워밍업 레이저를 안 쓰고 새로 만들었다: %d" % view._lasers.size())
	assert(view._items[0].visible and view._lasers[0].visible,
		"진짜 아이템/레이저인데 워밍업 상태로 숨겨져 있다")
	assert(is_equal_approx(view._items[0].scale.x, 1.0),
		"진짜 아이템이 워밍업 크기 그대로다: %s" % view._items[0].scale)
	assert(is_equal_approx(view._lasers[0].scale.x, 1.0),
		"진짜 레이저가 워밍업 크기 그대로다: %s" % view._lasers[0].scale)
	assert((view._items[0].get_node("Label") as Label3D).text == "S",
		"워밍업 글자가 진짜 아이템에 그대로 남았다: %s"
		% (view._items[0].get_node("Label") as Label3D).text)
	view.free()

# 불이 붙었다는 것은 블럭을 뚫는다는 뜻이라, 화면 번쩍임이 지나간 뒤에도
# 공만 보고 지금 상태를 알 수 있어야 한다.
func _test_the_ball_looks_different_while_it_burns() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	view.build(f.grid)
	view.sync(f)
	var normal := (view._ball.material_override as StandardMaterial3D).albedo_color
	f.burning = true
	view.sync(f)
	var fire := (view._ball.material_override as StandardMaterial3D).albedo_color
	assert(fire.is_equal_approx(Tuning.FIRE_COLOR), "불타는 공이 불 색이 아니다: %s" % fire)
	assert(not fire.is_equal_approx(normal), "불이 붙었는데 공 색이 그대로다: %s" % fire)
	f.burning = false
	view.sync(f)
	var back := (view._ball.material_override as StandardMaterial3D).albedo_color
	assert(back.is_equal_approx(normal), "불이 꺼졌는데 공이 계속 탄다: %s" % back)
	view.free()

# 두 재질의 기능 조합이 같아야 한다. 다르면 첫 점화에서 셰이더 변종이 새로
# 컴파일돼, 하필 화면이 번쩍이고 블럭이 뚫리는 순간에 프레임이 멎는다.
# 아이템처럼 미리 그려 굽는 방법도 있지만, 색만 다르게 두면 구울 것 자체가
# 안 생긴다 — 타이틀 화면에서 이미 그려지는 공 하나로 끝난다.
func _test_fire_costs_no_new_shader_variant() -> void:
	var view := BoardView.new()
	root.add_child(view)
	var f := PlayField.new()
	view.build(f.grid)
	view.sync(f)
	var normal := view._ball.material_override as StandardMaterial3D
	f.burning = true
	view.sync(f)
	var fire := view._ball.material_override as StandardMaterial3D
	assert(fire != normal, "테스트가 같은 재질을 두 번 보고 있다")
	assert(fire.emission_enabled == normal.emission_enabled,
		"emission 여부가 달라 셰이더 변종이 갈린다")
	assert(fire.shading_mode == normal.shading_mode, "셰이딩 모드가 달라 변종이 갈린다")
	assert(fire.transparency == normal.transparency, "투명도 모드가 달라 변종이 갈린다")
	assert(fire.cull_mode == normal.cull_mode, "컬 모드가 달라 변종이 갈린다")
	view.free()
