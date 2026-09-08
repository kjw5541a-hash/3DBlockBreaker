class_name BrickGrid
extends RefCounted

# 가로는 판 폭을 열 수로 나눈 값이고, 세로는 블럭 띠 높이를 줄 수로 나눈
# 값이다. 판을 좁히면 블럭도 같이 좁아져야 하므로 리터럴로 두지 않는다.
const CELL_W := 2.0 * Tuning.BOARD_HALF_WIDTH / float(Tuning.BRICK_COLS)
const CELL_H := (Tuning.BRICK_TOP_V - Tuning.BRICK_BOTTOM_V) / float(Tuning.BRICK_ROWS)

# 한 칸의 값이 곧 종류다. 0 빈칸, 양수는 남은 히트 수(1 일반, 2~3 단단),
# -1 은 불괴다. 병렬 배열이나 별도 클래스를 두지 않는 이유는 hit() 이
# 그냥 뺄셈 하나로 끝나기 때문이다.
const INDESTRUCTIBLE := -1

# 단단 블럭의 최대 히트 수. 생성기가 2~MAX_HARD 사이에서 고르고, 렌더링이
# 색을 이 범위로 정규화한다. 두 곳이 각자 3 을 박아 두면 한쪽만 올렸을 때
# 4히트 블럭이 색 없이 나온다.
const MAX_HARD := 3

var cells: PackedInt32Array = PackedInt32Array()

# 아이템이 든 칸. cells 와 정확히 같은 인덱스 규약을 쓰는 병렬 배열이고,
# 값은 Item 의 종류다(0 은 없음). 딕셔너리로 두면 index() 를 두 군데서
# 다르게 쓰게 되고, 60칸짜리 격자에서 아낄 메모리도 없다.
var item_cells: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	cells.resize(Tuning.BRICK_COLS * Tuning.BRICK_ROWS)
	cells.fill(0)
	item_cells.resize(Tuning.BRICK_COLS * Tuning.BRICK_ROWS)
	item_cells.fill(Item.NONE)

static func index(col: int, row: int) -> int:
	return row * Tuning.BRICK_COLS + col

# row 0 이 최하단 줄이다. v 가 커지는 방향과 row 가 커지는 방향을 같게
# 두면 좌표 변환이 사라진다.
static func cell_rect(col: int, row: int) -> Rect2:
	return Rect2(
		-Tuning.BOARD_HALF_WIDTH + float(col) * CELL_W,
		Tuning.BRICK_BOTTOM_V + float(row) * CELL_H,
		CELL_W, CELL_H)

func fill_all(kind: int) -> void:
	cells.fill(kind)

func get_cell(col: int, row: int) -> int:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return 0
	return cells[index(col, row)]

func hit(col: int, row: int) -> void:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return
	var i := index(col, row)
	# 불괴(-1)와 빈칸(0)은 뺄셈 대상이 아니다.
	if cells[i] > 0:
		cells[i] -= 1

# 아이템을 꺼내면서 칸을 비운다. 읽기와 지우기가 갈라지면 같은 블럭이 두 번
# 떨어뜨릴 여지가 생긴다.
func take_item(col: int, row: int) -> int:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return Item.NONE
	var i := index(col, row)
	var kind := item_cells[i]
	item_cells[i] = Item.NONE
	return kind

# 깰 수 있는 칸만 센다. 불괴는 남아 있어도 클리어를 막지 않는다.
func remaining() -> int:
	var n := 0
	for c in cells:
		if c > 0:
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
	var c0 := int(floor((center.x + Tuning.BOARD_HALF_WIDTH) / CELL_W))
	var r0 := int(floor((center.y - Tuning.BRICK_BOTTOM_V) / CELL_H))
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
