class_name BrickGrid
extends RefCounted

const CELL := 1.0

var cells: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	cells.resize(Tuning.BRICK_COLS * Tuning.BRICK_ROWS)
	cells.fill(0)

static func index(col: int, row: int) -> int:
	return row * Tuning.BRICK_COLS + col

# row 0 이 최하단 줄이다. v 가 커지는 방향과 row 가 커지는 방향을 같게
# 두면 좌표 변환이 사라진다.
static func cell_rect(col: int, row: int) -> Rect2:
	return Rect2(
		-Tuning.BOARD_HALF_WIDTH + float(col) * CELL,
		Tuning.BRICK_BOTTOM_V + float(row) * CELL,
		CELL, CELL)

func fill_all(kind: int) -> void:
	cells.fill(kind)

func get_cell(col: int, row: int) -> int:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return 0
	return cells[index(col, row)]

func hit(col: int, row: int) -> void:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return
	cells[index(col, row)] = 0

func remaining() -> int:
	var n := 0
	for c in cells:
		if c != 0:
			n += 1
	return n

# 원-AABB. 상자 위의 가장 가까운 점을 찾아 거리로 판정한다. 모서리에
# 맞으면 그 점이 꼭짓점이 되므로 법선이 중심-꼭짓점 방향으로 자동으로
# 나온다 — 면 법선을 쓰면 두 블럭 이음매에 닿은 공이 격자 안으로
# 빨려들며 발작한다.
#
# 브로드페이즈는 배열 인덱싱이다. 공 위치를 셀 좌표로 바꿔 주변 3×3 만
# 본다. 공간 분할 자료구조는 60칸짜리 격자에 과하다.
func query(center: Vector2, radius: float) -> Dictionary:
	var result := {"hit": false, "normal": Vector2.ZERO, "col": -1, "row": -1, "depth": 0.0}
	var c0 := int(floor((center.x + Tuning.BOARD_HALF_WIDTH) / CELL))
	var r0 := int(floor((center.y - Tuning.BRICK_BOTTOM_V) / CELL))
	var best_depth := 0.0
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			var col: int = c0 + dc
			var row: int = r0 + dr
			if get_cell(col, row) == 0:
				continue
			var rect := cell_rect(col, row)
			var nearest := Vector2(
				clampf(center.x, rect.position.x, rect.position.x + rect.size.x),
				clampf(center.y, rect.position.y, rect.position.y + rect.size.y))
			var away := center - nearest
			var dist := away.length()
			if dist >= radius:
				continue
			var n: Vector2
			if dist > 0.0001:
				n = away / dist
			else:
				n = _push_out_normal(center, rect)
			var depth := radius - dist
			if depth > best_depth:
				best_depth = depth
				result = {"hit": true, "normal": n, "col": col, "row": row, "depth": depth}
	return result

# 공 중심이 상자 안까지 들어와 버린 경우. 방향을 잃었으므로 가장 얕게
# 파고든 축으로 밀어낸다. Vector2.UP/DOWN 은 화면 좌표계라 이 (u,v)
# 좌표계와 부호가 반대다 — 쓰지 않는다.
static func _push_out_normal(center: Vector2, rect: Rect2) -> Vector2:
	var to_left := center.x - rect.position.x
	var to_right := rect.position.x + rect.size.x - center.x
	var to_below := center.y - rect.position.y
	var to_above := rect.position.y + rect.size.y - center.y
	var m := minf(minf(to_left, to_right), minf(to_below, to_above))
	if is_equal_approx(m, to_left):
		return Vector2(-1.0, 0.0)
	if is_equal_approx(m, to_right):
		return Vector2(1.0, 0.0)
	if is_equal_approx(m, to_below):
		return Vector2(0.0, -1.0)
	return Vector2(0.0, 1.0)
