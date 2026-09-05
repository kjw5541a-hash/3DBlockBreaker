class_name BoardView
extends Node3D

# 블럭 60개는 개별 MeshInstance3D 로 충분하다. MultiMesh 배칭은 이
# 규모에 과하고, 배칭하면 개별 파괴 연출이 즉시 번거로워진다.
var _bricks: Dictionary = {}   # index -> MeshInstance3D
# index -> 마지막으로 그린 칸 값. 이게 없으면 단단 블럭이 한 대 맞아도
# 화면이 그대로다.
var _brick_kinds: Dictionary = {}
var _ball: MeshInstance3D
var _paddle: MeshInstance3D
var _walls: Array[MeshInstance3D] = []

# 순수 시각값. 물리는 여전히 (u, v) 평면의 선분 하나로 튕긴다. 안쪽 면이
# 정확히 판 경계에 오도록 바깥으로만 두께를 준다 — 벽이 공을 먹는 것처럼
# 보이면 경계를 보여주려던 목적이 뒤집힌다.
const WALL_THICKNESS := 0.16
const WALL_HEIGHT := 0.5

# (u, v) 는 판 로컬 평면 좌표다. 판 노드가 25° 기울어져 있으므로 여기서는
# 기울기를 몰라도 된다 — 로컬 좌표만 만든다. 기울기를 바꿔도 이 함수는
# 그대로다.
#
# 이름에 board_ 를 붙인 것은 Node3D 에 이미 to_local(Vector3) 이 있어서다.
# 그냥 to_local 로 두면 상속받은 메서드를 가려 game.gd 의 좌표 역투영이
# 조용히 엉뚱한 것을 부른다.
static func board_to_local(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(p.x, height, -p.y)

# 높이는 순수 시각 값이다. 물리 충돌은 (u, v) 평면의 AABB 뿐이고 이
# 값은 메시 두께만 정한다. 기울어진 판에서 두께 차가 원근으로 드러난다.
#
# 두께는 종류를 뜻한다. 단단 블럭은 맞아서 값이 3 에서 2 로 줄어도 두께가
# 같다 — 남은 히트는 색으로 보여준다.
static func brick_height(kind: int) -> float:
	if kind == BrickGrid.INDESTRUCTIBLE:
		return 0.8
	if kind >= 2:
		return 0.6
	return 0.4

# 일반 블럭은 줄마다 색을 바꿔 어느 줄까지 닿았는지 눈으로 세게 한다.
# 단단 블럭은 은색이고 남은 히트가 줄수록 어두워진다. 불괴는 금색이다.
static func brick_color(kind: int, row: int) -> Color:
	if kind == BrickGrid.INDESTRUCTIBLE:
		return Color(0.85, 0.72, 0.25)
	if kind >= 2:
		# kind 3 -> 1.0, kind 2 -> 0.5. Color 에 float 을 곱하면 알파까지
		# 같이 어두워지므로 성분별로 곱한다.
		var t := float(kind - 1) / 2.0
		var k := lerpf(0.6, 1.0, t)
		return Color(0.55 * k, 0.58 * k, 0.62 * k)
	return Color.from_hsv(fmod(float(row) * 0.13, 1.0), 0.55, 0.9)

func brick_count() -> int:
	return _bricks.size()

func build(grid: BrickGrid) -> void:
	for key in _bricks.keys():
		(_bricks[key] as Node).free()
	_bricks.clear()
	_brick_kinds.clear()
	refresh_bricks(grid)
	if _ball == null:
		_ball = _make_ball()
		add_child(_ball)
	if _paddle == null:
		_paddle = _make_paddle()
		add_child(_paddle)
	if _walls.is_empty():
		for w in _make_walls():
			_walls.append(w)
			add_child(w)

func refresh_bricks(grid: BrickGrid) -> void:
	for row in Tuning.BRICK_ROWS:
		for col in Tuning.BRICK_COLS:
			var i := BrickGrid.index(col, row)
			var kind := grid.get_cell(col, row)
			if kind == 0:
				if _bricks.has(i):
					# 딕셔너리에서 지운 직후라 아무도 다시 참조하지 않는다.
					# queue_free 는 SceneTree 밖에서 처리 시점이 불확실하다.
					(_bricks[i] as Node).free()
					_bricks.erase(i)
					_brick_kinds.erase(i)
				continue
			if _bricks.has(i):
				if int(_brick_kinds[i]) == kind:
					continue
				# 단단 블럭이 한 대 맞아 색이 달라졌다. 재질만 갈아끼우지 않고
				# 지우고 다시 만드는 것은 종류가 바뀌면 두께도 따라와야 해서다.
				# 60 개짜리 격자에서 재생성은 부담이 아니다.
				(_bricks[i] as Node).free()
				_bricks.erase(i)
			var m := _make_brick(col, row, kind)
			_bricks[i] = m
			_brick_kinds[i] = kind
			add_child(m)

func sync(field: PlayField) -> void:
	refresh_bricks(field.grid)
	_ball.position = board_to_local(field.ball_pos, Tuning.BALL_RADIUS)
	_paddle.position = board_to_local(field.paddle.pos, Tuning.PADDLE_THICKNESS * 0.5)
	# 기울기를 눈에 보이게 한다. 법선과 같은 부호 규약을 쓴다.
	_paddle.rotation = Vector3(0.0, 0.0, -deg_to_rad(field.paddle.tilt_deg))

func _make_brick(col: int, row: int, kind: int) -> MeshInstance3D:
	var rect := BrickGrid.cell_rect(col, row)
	var h := brick_height(kind)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x * 0.94, h, rect.size.y * 0.94)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = board_to_local(rect.position + rect.size * 0.5, h * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = brick_color(kind, row)
	m.material_override = mat
	# 블럭은 그림자를 드리우지 않는다. 웹 빌드와 폰 성능 때문이다.
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func wall_count() -> int:
	return _walls.size()

# 좌·우·상 세 개. 이게 없으면 남은 공간이 그냥 빈 곳으로 보여서 어디까지가
# 판인지 눈으로 알 수 없다.
func _make_walls() -> Array[MeshInstance3D]:
	var t := WALL_THICKNESS
	var top := Tuning.BOARD_TOP_V
	var half := Tuning.BOARD_HALF_WIDTH
	var out: Array[MeshInstance3D] = []
	for side in [-1.0, 1.0]:
		out.append(_make_wall(
			Vector3(t, WALL_HEIGHT, top + t),
			Vector2(side * (half + t * 0.5), (top + t) * 0.5)))
	out.append(_make_wall(
		Vector3(half * 2.0 + t * 2.0, WALL_HEIGHT, t),
		Vector2(0.0, top + t * 0.5)))
	return out

func _make_wall(size: Vector3, center: Vector2) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = board_to_local(center, WALL_HEIGHT * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.32)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

func _make_ball() -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = Tuning.BALL_RADIUS
	mesh.height = Tuning.BALL_RADIUS * 2.0
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8)
	m.material_override = mat
	return m

func _make_paddle() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(Tuning.PADDLE_HALF_WIDTH * 2.0, Tuning.PADDLE_THICKNESS, 0.6)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0)
	m.material_override = mat
	return m
