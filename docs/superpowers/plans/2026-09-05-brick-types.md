# 블럭 3종 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `BrickGrid` 한 칸이 일반·단단·불괴 세 종류를 표현하게 만들고, 그 값이 화면과 교착 규칙에 정확히 반영되게 한다.

**Architecture:** 새 클래스도 병렬 배열도 만들지 않는다. `BrickGrid.cells` 는 `PackedInt32Array` 그대로 두고 값의 의미만 넓힌다 — `0` 빈칸, `1~3` 남은 히트 수, `-1` 불괴. `hit()` 은 양수를 1 감소시키고 `-1` 은 건드리지 않는다. `BoardView` 는 그 값에서 높이와 색을 파생시키고, 값이 바뀐 칸만 메시를 다시 만든다. `PlayField` 는 블럭이 **깨졌을 때만** 교착 카운터를 리셋한다.

**Tech Stack:** Godot 4.7.2, GDScript. 테스트는 `extends SceneTree` + `assert`, 러너는 `./run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-04-3dblockbreaker-phase2-design.md`

## Global Constraints

- 이 청크는 **화면에 보이는 변화가 없다.** 판을 채우는 것은 여전히 `fill_all(1)` 이고, 단단·불괴 블럭을 배치하는 생성기는 다음 청크(`stage-progression`)다. 산출물은 구조와 테스트뿐이다.
- 물리 계약을 건드리지 않는다. 감쇠 원천은 `Tuning.PADDLE_RESTITUTION` 하나뿐이고, 벽과 블럭은 완전탄성이다. 블럭 반사에 `PADDLE_RESTITUTION` 이나 어떤 감쇠도 넣지 않는다.
- 블럭 높이는 **순수 시각 값**이다. 물리 충돌은 `(u, v)` 평면의 AABB 뿐이고 높이는 메시 두께만 정한다. `brick_height()` 의 반환값이 `BrickGrid` 나 `BallPhysics` 로 흘러들어가면 안 된다.
- 불괴 블럭은 공을 **정상적으로 튕긴다.** 안 깨질 뿐이다. `query()` 가 `-1` 칸을 빈칸으로 취급하면 공이 통과한다.
- 브랜치는 `brick-types`. `main` 에 직접 커밋하지 않는다.
- 값 상수는 `BrickGrid.INDESTRUCTIBLE` 하나만 새로 만든다. `-1` 리터럴을 코드에 흩뿌리지 않는다.
- 고친 뒤에는 변이 테스트로 검사가 실제로 잡는지 확인한다 — 구현을 일부러 되돌려 놓고 **어느 assert 가 어떤 메시지로 실패하는지** 확인한 다음 되돌린다. 이 프로젝트의 관행이다.
- 테스트에서 기하 리터럴을 쓰지 않는다. `Tuning.*` 과 `BrickGrid.CELL_W` / `CELL_H` 에서 파생시킨다. 상수를 조정했을 때 테스트가 조용히 무의미해지는 것을 막으려는 것이다.

---

## File Structure

| 파일 | 책임 | 이 계획에서 |
|---|---|---|
| `scripts/brick_grid.gd` | 격자 데이터와 원-AABB 충돌 | 값 의미 확장, `hit()`/`remaining()` 수정 |
| `scripts/board_view.gd` | 판 위 모든 3D 노드 | 값별 높이·색, 값이 바뀐 칸 재생성 |
| `scripts/play_field.gd` | 물리 루프와 게임 규칙 | 교착 리셋 조건을 "깨졌을 때"로 좁힘 |
| `tests/test_brick_grid.gd` | 격자 검사 | Task 1 |
| `tests/test_board_view.gd` | 시각 파생값 검사 | Task 2 |
| `tests/test_play_field.gd` | 규칙 검사 | Task 3 |

---

## Task 1: `BrickGrid` 값 의미 확장

**Files:**
- Modify: `scripts/brick_grid.gd`
- Test: `tests/test_brick_grid.gd`

**Interfaces:**
- Consumes: 없음 (이 청크의 첫 작업)
- Produces:
  - `const BrickGrid.INDESTRUCTIBLE := -1`
  - `func BrickGrid.hit(col: int, row: int) -> void` — 양수면 1 감소, `-1` 이면 무변화, 범위 밖이면 무변화
  - `func BrickGrid.remaining() -> int` — `c > 0` 인 칸만 센다
  - 값 규약: `0` 빈칸 / `1` 일반 / `2`, `3` 단단(남은 히트) / `-1` 불괴

- [ ] **Step 1: 실패하는 테스트 넷을 쓴다**

`tests/test_brick_grid.gd` 의 `_initialize()` 목록에 네 줄을 추가한다. `_test_gap_between_bricks_does_not_thrash()` 다음, `print(...)` 앞이다.

```gdscript
	_test_hard_brick_takes_three_hits()
	_test_indestructible_never_breaks()
	_test_indestructible_is_not_counted_as_remaining()
	_test_indestructible_still_bounces()
```

파일 끝에 네 함수를 붙인다.

```gdscript
# 단단 블럭은 값이 곧 남은 히트 수다. 중간 상태가 remaining() 에서 사라지면
# 아직 안 깬 블럭을 두고 판이 클리어된다.
func _test_hard_brick_takes_three_hits() -> void:
	var g := BrickGrid.new()
	g.cells[BrickGrid.index(2, 1)] = 3
	assert(g.remaining() == 1, "단단 블럭이 안 세어진다: %d" % g.remaining())
	g.hit(2, 1)
	assert(g.get_cell(2, 1) == 2, "첫 히트에 값이 안 줄었다: %d" % g.get_cell(2, 1))
	g.hit(2, 1)
	assert(g.get_cell(2, 1) == 1, "둘째 히트에 값이 안 줄었다: %d" % g.get_cell(2, 1))
	assert(g.remaining() == 1, "덜 깨진 블럭이 이미 사라진 것으로 세어진다")
	g.hit(2, 1)
	assert(g.get_cell(2, 1) == 0, "셋째 히트에 안 깨졌다: %d" % g.get_cell(2, 1))
	assert(g.remaining() == 0, "다 깼는데 남은 수가 0 이 아니다: %d" % g.remaining())

func _test_indestructible_never_breaks() -> void:
	var g := BrickGrid.new()
	g.cells[BrickGrid.index(4, 3)] = BrickGrid.INDESTRUCTIBLE
	for i in 10:
		g.hit(4, 3)
	assert(g.get_cell(4, 3) == BrickGrid.INDESTRUCTIBLE,
		"불괴 블럭이 열 대에 변했다: %d" % g.get_cell(4, 3))

# 불괴만 남은 판은 클리어된 판이다. 안 그러면 영원히 안 끝난다.
func _test_indestructible_is_not_counted_as_remaining() -> void:
	var g := BrickGrid.new()
	g.cells[BrickGrid.index(4, 3)] = BrickGrid.INDESTRUCTIBLE
	g.cells[BrickGrid.index(5, 3)] = 1
	assert(g.remaining() == 1, "깰 수 있는 블럭이 하나인데 %d 로 세어진다" % g.remaining())
	g.hit(5, 3)
	assert(g.remaining() == 0, "불괴 블럭이 남아 클리어를 막는다: %d" % g.remaining())

# 안 깨질 뿐이지 공은 정상적으로 튕겨야 한다.
func _test_indestructible_still_bounces() -> void:
	var g := BrickGrid.new()
	g.cells[BrickGrid.index(5, 0)] = BrickGrid.INDESTRUCTIBLE
	var r := BrickGrid.cell_rect(5, 0)
	var center := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS * 0.8)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "불괴 블럭이 공을 안 튕긴다")
	assert(q["normal"].is_equal_approx(Vector2(0.0, -1.0)),
		"불괴 블럭의 아래 면 법선이 틀렸다: %s" % q["normal"])
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`
Expected: FAIL. `BrickGrid.INDESTRUCTIBLE` 이 아직 없으므로 파싱 단계에서 죽는다.

- [ ] **Step 3: `brick_grid.gd` 를 고친다**

파일 상단, `var cells: PackedInt32Array = PackedInt32Array()` 바로 위에 상수와 주석을 넣는다.

```gdscript
# 한 칸의 값이 곧 종류다. 0 빈칸, 양수는 남은 히트 수(1 일반, 2~3 단단),
# -1 은 불괴다. 병렬 배열이나 별도 클래스를 두지 않는 이유는 hit() 이
# 그냥 뺄셈 하나로 끝나기 때문이다.
const INDESTRUCTIBLE := -1
```

`hit()` 을 통째로 바꾼다.

```gdscript
func hit(col: int, row: int) -> void:
	if col < 0 or col >= Tuning.BRICK_COLS or row < 0 or row >= Tuning.BRICK_ROWS:
		return
	var i := index(col, row)
	# 불괴(-1)와 빈칸(0)은 뺄셈 대상이 아니다.
	if cells[i] > 0:
		cells[i] -= 1
```

`remaining()` 을 통째로 바꾼다.

```gdscript
# 깰 수 있는 칸만 센다. 불괴는 남아 있어도 클리어를 막지 않는다.
func remaining() -> int:
	var n := 0
	for c in cells:
		if c > 0:
			n += 1
	return n
```

`query()` 와 `get_cell()` 은 건드리지 않는다. `get_cell()` 이 `-1` 을 그대로 돌려주므로 `query()` 의 `if get_cell(col, row) == 0: continue` 가 불괴 칸을 건너뛰지 않는다 — 이게 `_test_indestructible_still_bounces` 가 지키는 동작이다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./run_tests.sh`
Expected: 전체 통과. `test_brick_grid: OK` 포함.

- [ ] **Step 5: 변이 테스트**

세 군데를 하나씩 되돌려 놓고 각각 어느 assert 가 실패하는지 확인한 뒤 되돌린다.

1. `if cells[i] > 0:` 를 `if cells[i] != 0:` 로 → `_test_indestructible_never_breaks` 의 "불괴 블럭이 열 대에 변했다"
2. `if c > 0:` 를 `if c != 0:` 로 → `_test_indestructible_is_not_counted_as_remaining` 의 "불괴 블럭이 남아 클리어를 막는다"
3. `cells[i] -= 1` 을 `cells[i] = 0` 으로 → `_test_hard_brick_takes_three_hits` 의 "첫 히트에 값이 안 줄었다"

Run (각 변이마다): `./run_tests.sh`
Expected: 위에 적은 메시지로 실패. 다른 메시지로 실패하면 테스트가 의도한 것을 안 잡고 있는 것이므로 테스트를 고친다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/brick_grid.gd tests/test_brick_grid.gd
git commit -m "feat: 블럭 격자가 단단·불괴 블럭을 표현한다

칸 값의 의미를 넓혔다. 0 빈칸, 양수는 남은 히트 수, -1 은 불괴다.
새 클래스도 병렬 배열도 안 만든 것은 hit() 이 뺄셈 하나로 끝나서다.

remaining() 은 c > 0 인 칸만 센다 — 불괴만 남은 판은 클리어된 판이다.
안 그러면 판이 영원히 안 끝난다.

query() 는 안 건드렸다. get_cell() 이 -1 을 그대로 돌려주므로 불괴
칸도 충돌 대상으로 남는다. 안 깨질 뿐 공은 정상적으로 튕겨야 한다."
```

---

## Task 2: `BoardView` 가 종류별로 그리고 값이 바뀌면 다시 그린다

**Files:**
- Modify: `scripts/board_view.gd`
- Test: `tests/test_board_view.gd`

**Interfaces:**
- Consumes: `BrickGrid.INDESTRUCTIBLE`, 칸 값 규약 (Task 1)
- Produces:
  - `static func BoardView.brick_height(kind: int) -> float`
  - `static func BoardView.brick_color(kind: int, row: int) -> Color`
  - `refresh_bricks()` 가 값이 바뀐 칸의 메시를 다시 만든다

기존 `brick_height()` 는 1단계에서 아직 존재하지 않는 종류를 가정해 `2 -> 0.6`, `3 -> 0.8` 로 짜여 있다. Task 1 이 정한 값 규약에서 `3` 은 불괴가 아니라 단단 블럭의 만피 상태이므로, 이 함수와 그것을 검사하는 기존 테스트를 같이 고친다.

- [ ] **Step 1: 기존 테스트를 새 규약에 맞게 바꾸고 실패하는 테스트 셋을 더한다**

`tests/test_board_view.gd` 의 `_test_brick_heights_differ_by_kind()` 를 통째로 바꾼다.

```gdscript
func _test_brick_heights_differ_by_kind() -> void:
	assert(BoardView.brick_height(1) > 0.0, "일반 블럭 높이가 0 이다")
	assert(BoardView.brick_height(3) > BoardView.brick_height(1),
		"단단한 블럭이 더 두꺼워야 한다")
	assert(is_equal_approx(BoardView.brick_height(2), BoardView.brick_height(3)),
		"단단 블럭은 남은 히트가 줄어도 두께가 같아야 한다 — 두께는 종류를 뜻한다")
	assert(BoardView.brick_height(BrickGrid.INDESTRUCTIBLE) > BoardView.brick_height(3),
		"불괴 블럭이 가장 두꺼워야 한다")
```

`_initialize()` 목록에 세 줄을 더한다. `_test_brick_heights_differ_by_kind()` 다음이다.

```gdscript
	_test_hard_brick_darkens_when_hit()
	_test_indestructible_is_gold()
	_test_hard_brick_mesh_updates_on_hit()
```

파일 끝에 세 함수를 붙인다.

```gdscript
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`
Expected: FAIL. `BoardView.brick_color` 가 없어 파싱 단계에서 죽는다.

- [ ] **Step 3: `board_view.gd` 를 고친다**

`_bricks` 선언 아래에 값 기억용 딕셔너리를 더한다.

```gdscript
# index -> 마지막으로 그린 칸 값. 이게 없으면 단단 블럭이 한 대 맞아도
# 화면이 그대로다.
var _brick_kinds: Dictionary = {}
```

`brick_height()` 를 통째로 바꾼다.

```gdscript
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
```

바로 아래에 색 함수를 새로 넣는다.

```gdscript
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
```

`build()` 의 정리 구간에 한 줄을 더한다. `_bricks.clear()` 바로 다음이다.

```gdscript
	_brick_kinds.clear()
```

`refresh_bricks()` 를 통째로 바꾼다.

```gdscript
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
```

`_make_brick()` 의 색 지정 두 줄을 한 줄로 바꾼다. 아래 두 줄을

```gdscript
	# 줄마다 색을 바꿔 어느 줄까지 닿았는지 눈으로 세게 한다.
	mat.albedo_color = Color.from_hsv(fmod(float(row) * 0.13, 1.0), 0.55, 0.9)
```

이렇게 바꾼다.

```gdscript
	mat.albedo_color = brick_color(kind, row)
```

- [ ] **Step 4: 통과를 확인한다**

Run: `./run_tests.sh`
Expected: 전체 통과.

- [ ] **Step 5: 변이 테스트**

두 군데를 하나씩 되돌려 놓고 확인한 뒤 되돌린다.

1. `refresh_bricks()` 의 `if int(_brick_kinds[i]) == kind: continue` 를 `continue` 로 (조건 없이) → `_test_hard_brick_mesh_updates_on_hit` 의 "맞은 단단 블럭의 색이 안 바뀌었다"
2. `brick_height()` 의 `if kind >= 2: return 0.6` 을 `return 0.8` 로 → `_test_brick_heights_differ_by_kind` 의 "불괴 블럭이 가장 두꺼워야 한다"

Run (각 변이마다): `./run_tests.sh`

- [ ] **Step 6: 커밋**

```bash
git add scripts/board_view.gd tests/test_board_view.gd
git commit -m "feat: 블럭 종류별 높이와 색, 값이 바뀐 칸만 다시 그린다

두께가 종류를 뜻한다 - 일반 0.4, 단단 0.6, 불괴 0.8. 단단 블럭은 맞아서
값이 3 에서 2 로 줄어도 두께가 같고, 남은 히트는 색이 어두워지는 것으로
보여준다. 높이는 여전히 순수 시각 값이라 물리로 안 흘러간다.

refresh_bricks() 가 '메시가 이미 있으면 건너뛴다' 였는데, 단단 블럭이
생기는 순간 그 최적화가 버그가 된다 - 한 대 맞아도 화면이 그대로다.
마지막으로 그린 값을 기억해 두고 달라진 칸만 다시 만든다.

기존 brick_height() 는 1단계에서 종류 3 을 불괴로 가정하고 있었다.
Task 1 이 정한 규약에서 3 은 단단 블럭의 만피 상태다. 그 테스트도
같이 고쳤다."
```

---

## Task 3: 교착 카운터는 블럭이 깨졌을 때만 리셋한다

**Files:**
- Modify: `scripts/play_field.gd`
- Test: `tests/test_play_field.gd`

**Interfaces:**
- Consumes: `BrickGrid.hit()` 의 감소 동작, 칸 값 규약 (Task 1)
- Produces: `PlayField.step()` 이 돌려주는 `bricks_hit` 의 의미가 "맞은 횟수"에서 **"깨진 개수"**로 바뀐다. 반환 키 이름과 타입은 그대로다.

단단 블럭이 생기면 기존 규칙에 구멍이 난다. 지금은 블럭에 닿기만 하면 교착 카운터가 0 으로 돌아가므로, 단단 블럭을 툭툭 건드리는 것만으로 교착 규칙을 무한정 피할 수 있다. 리셋 조건을 "깨졌을 때"로 좁힌다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/test_play_field.gd` 의 `_initialize()` 목록 끝에, `print(...)` 앞에 한 줄을 더한다.

```gdscript
	_test_hard_brick_only_resets_stall_when_broken()
```

파일 끝에 함수를 붙인다.

```gdscript
# 단단 블럭을 툭툭 건드리는 것으로 교착 규칙을 피할 수 있으면 규칙이
# 아니라 요령이 된다. 리셋은 블럭이 실제로 깨졌을 때만이다.
func _test_hard_brick_only_resets_stall_when_broken() -> void:
	var f := PlayField.new()
	var r := BrickGrid.cell_rect(5, 0)
	var below := Vector2(r.position.x + BrickGrid.CELL_W * 0.5,
		r.position.y - Tuning.BALL_RADIUS - 0.01)
	f.grid.cells[BrickGrid.index(5, 0)] = 2
	f.attached = false
	f.paddle_hits_since_brick = 2

	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	f.step(f.paddle.pos, 1.0 / 120.0)
	assert(f.grid.get_cell(5, 0) == 1,
		"단단 블럭이 한 대에 사라졌다: %d" % f.grid.get_cell(5, 0))
	assert(f.paddle_hits_since_brick == 2,
		"안 깨진 블럭이 교착 카운터를 리셋했다: %d" % f.paddle_hits_since_brick)

	f.ball_pos = below
	f.ball_vel = Vector2(0.0, 8.0)
	var out := f.step(f.paddle.pos, 1.0 / 120.0)
	assert(f.grid.get_cell(5, 0) == 0,
		"두 번째 히트에 안 깨졌다: %d" % f.grid.get_cell(5, 0))
	assert(f.paddle_hits_since_brick == 0,
		"깨졌는데 교착 카운터가 안 리셋됐다: %d" % f.paddle_hits_since_brick)
	assert(int(out["bricks_hit"]) == 1,
		"bricks_hit 이 깨진 개수를 안 센다: %d" % int(out["bricks_hit"]))
```

`PlayField.new()` 는 `_init()` 에서 `grid.fill_all(1)` 을 부르므로 격자가 이미 일반 블럭으로 가득하다. 위 테스트는 `(5, 0)` 칸만 `2` 로 덮어쓰고 그 칸만 건드리므로 나머지는 상관없다.

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`
Expected: FAIL. `test_play_field` 가 "안 깨진 블럭이 교착 카운터를 리셋했다: 0" 으로 죽는다.

- [ ] **Step 3: `play_field.gd` 를 고친다**

`step()` 안의 블럭 충돌 처리 블럭을 바꾼다. 아래 다섯 줄을

```gdscript
		if q["hit"]:
			grid.hit(q["col"], q["row"])
			out["bricks_hit"] = int(out["bricks_hit"]) + 1
			paddle_hits_since_brick = 0
```

이렇게 바꾼다.

```gdscript
		if q["hit"]:
			grid.hit(q["col"], q["row"])
			# 깨졌을 때만 센다. 단단 블럭을 툭툭 건드리는 것으로 교착 규칙을
			# 피할 수 있으면 규칙이 아니라 요령이 된다. 불괴 블럭은 영원히
			# 안 깨지므로 영원히 리셋하지 않는다 — 그게 맞다.
			if grid.get_cell(q["col"], q["row"]) == 0:
				out["bricks_hit"] = int(out["bricks_hit"]) + 1
				paddle_hits_since_brick = 0
```

그 아래 두 줄(`ball_vel = BallPhysics.reflect(...)`, `ball_pos += ...`)은 `if q["hit"]:` 안에 그대로 둔다. 반사는 깨졌든 안 깨졌든 일어난다.

- [ ] **Step 4: 통과를 확인한다**

Run: `./run_tests.sh`
Expected: 전체 통과. 특히 `test_game_smoke` 와 `test_ball_integration` 이 계속 통과해야 한다 — 일반 블럭은 1히트에 깨지므로 기존 동작이 그대로여야 한다.

- [ ] **Step 5: 변이 테스트**

`if grid.get_cell(q["col"], q["row"]) == 0:` 를 `if true:` 로 바꾼다.

Run: `./run_tests.sh`
Expected: `_test_hard_brick_only_resets_stall_when_broken` 의 "안 깨진 블럭이 교착 카운터를 리셋했다" 로 실패. 확인 후 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/play_field.gd tests/test_play_field.gd
git commit -m "fix: 교착 카운터는 블럭이 깨졌을 때만 리셋한다

단단 블럭이 생기면 기존 규칙에 구멍이 난다. 닿기만 하면 리셋이라
단단 블럭을 툭툭 건드리는 것만으로 교착 규칙을 무한정 피할 수 있다.
불괴 블럭이면 영원히 그럴 수 있다.

bricks_hit 의 의미도 '맞은 횟수'에서 '깨진 개수'로 바뀐다. 아이템
드랍이 파괴 순간에 걸리므로 이쪽이 앞으로 필요한 값이다.

반사는 깨졌든 안 깨졌든 일어난다 - 블럭은 여전히 완전탄성이다."
```

---

## 마무리

세 작업이 끝나면 브랜치를 밀고 배포를 확인한다.

```bash
git push -u origin brick-types
```

화면에 보이는 변화는 없다. 확인할 것은 **없던 회귀가 안 생겼는가** 하나다 — 배포된 빌드에서 공이 평소처럼 블럭을 깨고, 교착 3회 규칙이 그대로 목숨을 가져가는지. HUD 버전 문구가 `brick-types` 로 바뀌어 있어야 그 빌드를 보고 있는 것이다.

병합은 `--no-ff` 로 한다. fast-forward 로 병합하면 커밋 SHA 가 브랜치와 같아 GitHub Pages 가 같은 배포로 보고 무시하고, 라이브 화면의 버전 문구에 이미 지운 브랜치 이름이 남는다.
