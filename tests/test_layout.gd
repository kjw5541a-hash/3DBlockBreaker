extends SceneTree

# 폰 화면비는 16:9 부터 20:9 를 넘어간다. 프로젝트 기준 해상도는 720x1280(16:9)라
# 그보다 긴 화면에서는 위아래로 남는 자리가 생긴다. stretch 설정과 앵커가 없으면
# HUD 가 기준 해상도 좌표에 그대로 박혀, 빌드 버전 라벨이 화면 아래가 아니라
# 허공에 뜨고 아래쪽 UI 가 잘린다. 폰마다 다르게 깨지므로 눈으로는 못 잡는다.
#
# 각 라벨이 "붙어 있어야 할 가장자리"에서 떨어진 거리가 화면비가 바뀌어도
# 그대로인지 본다 — 화면 안에 있는지만 보면 허공에 뜬 것을 통과시킨다.
const SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),   # 기준 16:9
	Vector2i(1080, 1920),  # 같은 비율, 더 큰 화면
	Vector2i(1080, 2400),  # 20:9 요즘 폰
	Vector2i(1440, 3200),  # 20:9 고해상도
]

# 경로 -> 붙어 있어야 할 곳.
const PINNED := {
	"HUD/Lives": "top",
	"HUD/Stage": "top",
	"HUD/PauseButton": "top",
	"HUD/Version": "bottom",
	"HUD/TitleScreen/Prompt": "center",
	"HUD/PauseScreen/Prompt": "center",
	"HUD/GameOverScreen/Prompt": "center",
}

func _initialize() -> void:
	await _test_the_hud_holds_its_edges_on_any_phone()
	print("test_layout: OK")
	quit()

func _test_the_hud_holds_its_edges_on_any_phone() -> void:
	assert(str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled")) != "disabled",
		"stretch 모드가 꺼져 있다 — HUD 가 폰 해상도를 그대로 맞고 흩어진다")
	var packed := load("res://scenes/game.tscn") as PackedScene
	var g := packed.instantiate()
	root.add_child(g)
	var first := {}
	for size in SIZES:
		root.size = size
		# 창 크기 변경이 content scale 을 거쳐 Control 사각형까지 내려가는 데
		# 프레임이 필요하다.
		await process_frame
		await process_frame
		var view: Vector2 = root.get_visible_rect().size
		for path in PINNED:
			var c := g.get_node(path) as Control
			assert(c != null, "HUD 노드가 없다: %s" % path)
			var r := c.get_global_rect()
			var gap := _gap(r, view, str(PINNED[path]))
			if not first.has(path):
				first[path] = gap
				continue
			assert(absf(gap - float(first[path])) <= 1.0,
				"%s 가 %s 에서 떨어졌다: %s 기준 %f -> %f (화면 %s)"
					% [path, size, PINNED[path], first[path], gap, view])
		# 가로도 같이 본다 — 앵커 없이 offset 만 쓰면 넓은 화면에서 왼쪽에 몰린다.
		for path in PINNED:
			var r := (g.get_node(path) as Control).get_global_rect()
			assert(r.position.x >= -1.0 and r.end.x <= view.x + 1.0,
				"%s 가 좌우로 화면을 벗어났다: %s (화면 %s)" % [path, r, view])
	g.free()

static func _gap(r: Rect2, view: Vector2, edge: String) -> float:
	match edge:
		"top":
			return r.position.y
		"bottom":
			return view.y - r.end.y
		_:
			# 화면 세로 한가운데에서 라벨 한가운데까지.
			return r.get_center().y - view.y * 0.5
