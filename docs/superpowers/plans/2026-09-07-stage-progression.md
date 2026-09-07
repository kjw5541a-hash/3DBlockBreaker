# 스테이지 진행 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 판 번호 하나로 배치가 정해지는 절차 생성기를 넣고, 클리어하면 다음 판으로 넘어가게 한다.

**Architecture:** `StageGen.stage(index) -> BrickGrid` 이음매 하나를 새로 만든다. 난이도는 밀도·경도·빈칸폭 세 레버를 판 번호 함수로 계산해 배치에만 반영한다 — 물리 상수(`Tuning`)는 한 줄도 안 건드린다. 배치는 좌우 대칭이고 시드는 판 번호라, 같은 판은 언제 어디서 시작해도 같은 판이다. `PlayField` 는 `stage_index` 를 들고 `next_stage()` / `reset_run()` 두 메서드로 판을 갈아끼운다.

**Tech Stack:** Godot 4.7.2, GDScript. 테스트는 `extends SceneTree` 헤드리스 스크립트, 실행은 `./run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-04-3dblockbreaker-phase2-design.md` (§1 난이도, §3 스테이지 생성, §6 HUD)

## Global Constraints

이 계약들은 모든 태스크에 암묵적으로 포함된다. 하나라도 깨면 그 태스크는 반려다.

- 감쇠 원천은 `Tuning.PADDLE_RESTITUTION` 하나뿐이다. 벽과 블럭은 완전탄성.
- 패들 반사에 속도 하한이 없다. 교착은 `Tuning.STALL_PADDLE_HITS` 가 끊는다.
- 물리는 판 좌표계 `(u, v)` 의 2D다. 블럭 높이는 시각 값일 뿐 충돌에 안 들어간다.
- **스테이지는 `Tuning` 을 수정하지 않는다.** 속도 상한 `Tuning.v_max_at(elapsed)` 는 전역 램프이고, 난이도는 배치로만 올린다.
- `elapsed` 는 판이 넘어가도 이어진다. 목숨을 전부 잃고 처음부터 다시 시작할 때만 0 이다.
- 프로젝트를 **Godot 에디터나 `godot --script` 로 열지 않는다.** `project.godot` 을 다시 써서 주석을 날린다. 테스트는 오직 `./run_tests.sh`.
- 실패한 `assert` 는 헤드리스 Godot 을 무한 정지시킨다. `run_tests.sh` 가 20초 타임아웃으로 잡으므로 `TIMEOUT` 출력은 곧 실패다.
- 고친 뒤에는 **변이 테스트**로 검사가 실제로 잡는지 확인한다. 구현을 일부러 망가뜨려 이름 붙인 단언이 이름 붙인 메시지로 실패하는지 보고, 원복한다.
- 병합은 `--no-ff`. fast-forward 로 병합하면 커밋 SHA 가 브랜치와 같아 GitHub Pages 가 같은 배포로 보고 무시한다.

## 범위에서 뺀 것

- **`BrickGrid.item_cells`** (설계 §3). 아이템 드랍은 4a `item-core` 의 일이고 지금 소비자가 없다. 붙일 때는 `StageGen` 에 같은 시드로 칸을 고르는 함수 하나가 늘 뿐, 격자 구조는 그대로다.
- **`out["broken"]` 소비자 전환.** 이번 청크는 깨진 블럭 목록을 읽는 코드를 만들지 않는다. 파티클(3 `brick-effects`)과 아이템(4a)이 첫 소비자다.
- **점수.** 요청된 적이 없다.

## 파일 구조

| 파일 | 책임 |
|---|---|
| `scripts/stage_gen.gd` (신규) | 판 번호 → `BrickGrid`. 난이도 곡선 상수와 생성 규칙이 전부 여기 산다. |
| `scripts/brick_grid.gd` (수정) | `MAX_HARD` 상수 하나 추가. 값 규약이 사는 자리라서. |
| `scripts/play_field.gd` (수정) | `stage_index`, `next_stage()`, `reset_run()`. |
| `scripts/game.gd` (수정) | 클리어·전멸 처리를 `PlayField` 메서드로 위임. HUD 판 번호. |
| `scenes/game.tscn` (수정) | `HUD/Stage` 라벨. |
| `tests/test_stage_gen.gd` (신규) | 결정성, 대칭, 세 불변식, 곡선 일정. |
| `tests/test_play_field.gd` (수정) | 판 진행이 `elapsed` 를 안 건드리는지. |
| `tests/test_game_smoke.gd` (수정) | HUD 판 번호가 `stage_index` 를 따라가는지. |

난이도 곡선 상수를 `Tuning` 이 아니라 `StageGen` 에 두는 이유는 계약이다. `Tuning` 은 물리 계약이 사는 곳이고, "스테이지가 물리를 안 건드린다"는 규칙이 파일 경계로 보이는 편이 주석 한 줄보다 세다.

---

### Task 1: StageGen — 판 번호에서 배치를 만든다

**Files:**
- Create: `scripts/stage_gen.gd`
- Modify: `scripts/brick_grid.gd` (`INDESTRUCTIBLE` 상수 옆)
- Test: `tests/test_stage_gen.gd` (신규)

**Interfaces:**
- Consumes: `BrickGrid`(`cells`, `index()`, `INDESTRUCTIBLE`, `remaining()`), `Tuning.BRICK_COLS`, `Tuning.BRICK_ROWS`
- Produces:
  - `BrickGrid.MAX_HARD: int` == 3
  - `StageGen.stage(index: int) -> BrickGrid`
  - `StageGen.density(index: int) -> float`
  - `StageGen.hard_ratio(index: int) -> float`
  - `StageGen.indestructible_count(index: int) -> int`
  - `StageGen.max_gap(index: int) -> int`

`index` 는 **0 기반**이다. 설계 문서의 "판 N" 은 `index == N - 1` 이다. HUD 만 `index + 1` 을 보여준다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/test_stage_gen.gd` 를 새로 만든다.

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_same_index_gives_same_stage()
	_test_stage_is_mirror_symmetric()
	_test_invariants_hold_for_first_hundred_stages()
	_test_no_gap_is_wider_than_the_curve_allows()
	_test_levers_arrive_on_schedule()
	print("test_stage_gen: OK")
	quit()

# 판 번호가 곧 시드다. 3판은 어느 기기에서 언제 시작해도 같은 3판이어야
# 테스트를 쓸 수 있고, 플레이어가 판을 기억할 수 있다.
func _test_same_index_gives_same_stage() -> void:
	for index in [0, 5, 17, 63]:
		var a := StageGen.stage(index)
		var b := StageGen.stage(index)
		assert(a.cells == b.cells, "같은 판 번호가 다른 배치를 냈다: %d" % index)
	assert(StageGen.stage(3).cells != StageGen.stage(4).cells,
		"판 번호가 달라도 배치가 같다 — 시드가 안 먹었다")

# 좌우 대칭이 없으면 난수가 그냥 잡음으로 보인다. 원작 판이 전부 대칭인 이유다.
func _test_stage_is_mirror_symmetric() -> void:
	for index in [0, 5, 12, 40]:
		var g := StageGen.stage(index)
		for row in Tuning.BRICK_ROWS:
			for col in Tuning.BRICK_COLS:
				var mirrored := Tuning.BRICK_COLS - 1 - col
				assert(g.get_cell(col, row) == g.get_cell(mirrored, row),
					"판 %d 의 (%d,%d) 가 거울짝과 다르다: %d vs %d" % [
						index, col, row,
						g.get_cell(col, row), g.get_cell(mirrored, row)])

# 클리어 가능성. 셋 다 구조로 보장되지만, 곡선을 손대면 조용히 깨진다.
func _test_invariants_hold_for_first_hundred_stages() -> void:
	for index in 101:
		var g := StageGen.stage(index)
		assert(g.remaining() >= 1, "판 %d 에 깰 수 있는 블럭이 없다" % index)
		for col in Tuning.BRICK_COLS:
			assert(g.get_cell(col, 0) != BrickGrid.INDESTRUCTIBLE,
				"판 %d 의 최하단 %d 열이 불괴다 — 위쪽이 봉인된다" % [index, col])
		var hard_walls := 0
		for c in g.cells:
			if c == BrickGrid.INDESTRUCTIBLE:
				hard_walls += 1
		assert(hard_walls <= StageGen.INDESTRUCTIBLE_MAX,
			"판 %d 의 불괴 블럭이 상한을 넘었다: %d" % [index, hard_walls])

# 레버 D. 빈칸이 좁아지지 않으면 밀도만 오르다가 어느 판부터 그냥 벽이 된다.
func _test_no_gap_is_wider_than_the_curve_allows() -> void:
	for index in 101:
		var g := StageGen.stage(index)
		var allowed := StageGen.max_gap(index)
		for row in Tuning.BRICK_ROWS:
			var run := 0
			for col in Tuning.BRICK_COLS:
				if g.get_cell(col, row) == 0:
					run += 1
					assert(run <= allowed,
						"판 %d 의 %d 줄에 빈칸이 %d 칸 이어졌다 (상한 %d)" % [
							index, row, run, allowed])
				else:
					run = 0

# 세 레버를 동시에 조이면 3판째에 벽에 부딪힌다. 순차로 들어와야 한다.
func _test_levers_arrive_on_schedule() -> void:
	assert(is_equal_approx(StageGen.density(0), 0.55),
		"첫 판 밀도가 55%% 가 아니다: %f" % StageGen.density(0))
	assert(is_equal_approx(StageGen.density(50), 0.90),
		"충분히 진행한 판의 밀도가 상한이 아니다: %f" % StageGen.density(50))
	assert(StageGen.density(50) > StageGen.density(0), "밀도가 안 오른다")

	for index in 3:
		var g := StageGen.stage(index)
		for c in g.cells:
			assert(c <= 1, "판 %d(1~3판)에 단단 블럭이 나왔다: %d" % [index, c])
	assert(StageGen.hard_ratio(2) == 0.0, "판 3 에 단단 비율이 0 이 아니다")
	assert(StageGen.hard_ratio(50) > StageGen.hard_ratio(4),
		"단단 비율이 안 오른다")

	assert(StageGen.indestructible_count(6) == 0, "판 7 에 불괴 블럭이 나온다")
	assert(StageGen.indestructible_count(50) == StageGen.INDESTRUCTIBLE_MAX,
		"불괴 블럭이 상한에 안 닿는다: %d" % StageGen.indestructible_count(50))
	assert(StageGen.indestructible_count(50) % 2 == 0,
		"불괴 블럭 수가 홀수다 — 좌우 대칭으로 놓을 수 없다")

	assert(StageGen.max_gap(0) == 3, "첫 판 빈칸 상한이 3 이 아니다")
	assert(StageGen.max_gap(50) == 1, "빈칸 상한이 1 까지 안 좁아진다")
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`

Expected: FAIL. `test_stage_gen.gd` 에서 `Identifier "StageGen" not declared` 파스 에러, 그리고 `성공 표식 'test_stage_gen: OK'가 출력에 없음`.

- [ ] **Step 3: `BrickGrid.MAX_HARD` 를 넣는다**

`scripts/brick_grid.gd` 의 `const INDESTRUCTIBLE := -1` **바로 아래**에 붙인다.

```gdscript
# 단단 블럭의 최대 히트 수. 생성기가 2~MAX_HARD 사이에서 고르고, 렌더링이
# 색을 이 범위로 정규화한다. 두 곳이 각자 3 을 박아 두면 한쪽만 올렸을 때
# 4히트 블럭이 색 없이 나온다.
const MAX_HARD := 3
```

- [ ] **Step 4: `StageGen` 을 쓴다**

`scripts/stage_gen.gd` 를 새로 만든다.

```gdscript
class_name StageGen
extends RefCounted

# 판 번호 하나로 배치가 완전히 정해진다. 시드가 판 번호라 3판은 어느 기기에서
# 언제 시작해도 같은 3판이다 — 테스트가 가능해지고 플레이어가 판을 기억한다.
#
# 난이도는 여기서만 만든다. 물리 상수는 레버가 아니다 — 이 파일은 Tuning 을
# 읽기만 하고 절대 쓰지 않는다. 판이 빨라지는 것은 오직 Tuning.v_max_at()
# 전역 램프 때문이고, 여기가 하는 일은 배치뿐이다.
#
# index 는 0 기반이다. 설계 문서의 "판 N" 은 index N-1 이다.

# 곡선의 마디. 설계 §1 의 표를 그대로 옮긴 것이다.
const RAMP_A_END := 2    # 판 3 — 여기까지 밀도만
const RAMP_B_END := 6    # 판 7 — 여기까지 밀도 + 경도
const RAMP_C_END := 13   # 판 14 — 여기서 모든 레버가 상한

const DENSITY_START := 0.55
const DENSITY_MID := 0.70
const DENSITY_MAX := 0.90

const HARD_MID := 0.20
const HARD_MAX := 0.35

# 상한을 두는 이유는 판이 끝나야 하기 때문이다. 상한이 없으면 언젠가 반드시
# 클리어 불가능한 판이 나온다. 10 열짜리 줄을 다 막으려면 10 개가 필요하므로
# 이 값이 8 인 한 어떤 줄도 통째로 봉인되지 않는다.
const INDESTRUCTIBLE_MAX := 8

const GAP_START := 3
const GAP_MIN := 1

static func stage(index: int) -> BrickGrid:
	var g := BrickGrid.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = index
	var d := density(index)
	var hard := hard_ratio(index)
	var gap := max_gap(index)
	for row in Tuning.BRICK_ROWS:
		_fill_row(g, rng, row, d, hard, gap)
	_place_indestructible(g, rng, indestructible_count(index))
	return g

# 레버 A. 판 1–3 에서 55%→70%, 그 뒤 판 14 까지 90% 로 간다.
static func density(index: int) -> float:
	if index <= RAMP_A_END:
		return lerpf(DENSITY_START, DENSITY_MID, float(index) / float(RAMP_A_END))
	return lerpf(DENSITY_MID, DENSITY_MAX, _ramp(index, RAMP_A_END, RAMP_C_END))

# 레버 B 앞쪽. 단단 블럭은 판 4 부터 등장한다.
static func hard_ratio(index: int) -> float:
	if index <= RAMP_A_END:
		return 0.0
	if index <= RAMP_B_END:
		return lerpf(0.0, HARD_MID, _ramp(index, RAMP_A_END, RAMP_B_END))
	return lerpf(HARD_MID, HARD_MAX, _ramp(index, RAMP_B_END, RAMP_C_END))

# 레버 B 뒤쪽. 불괴 블럭은 판 8 부터. 짝수로 맞추는 것은 좌우 대칭으로 쌍을
# 놓기 때문이다 — 홀수면 마지막 하나가 짝을 못 찾아 대칭이 깨진다.
static func indestructible_count(index: int) -> int:
	if index <= RAMP_B_END:
		return 0
	var n := int(round(lerpf(0.0, float(INDESTRUCTIBLE_MAX),
		_ramp(index, RAMP_B_END, RAMP_C_END))))
	return n - (n % 2)

# 레버 D. 연속 빈칸의 최대 폭. 판 8 부터 3칸에서 1칸으로 좁아진다.
static func max_gap(index: int) -> int:
	if index <= RAMP_B_END:
		return GAP_START
	return int(round(lerpf(float(GAP_START), float(GAP_MIN),
		_ramp(index, RAMP_B_END, RAMP_C_END))))

static func _ramp(index: int, from_index: int, to_index: int) -> float:
	return clampf(float(index - from_index) / float(to_index - from_index), 0.0, 1.0)

# 절반만 만들고 거울로 접는다.
#
# 안쪽 열부터 바깥으로 훑는 이유는 빈칸 길이 때문이다. 가운데를 가로지르는
# 빈칸 구간은 왼쪽 절반에서 한 칸 비울 때마다 오른쪽 거울짝도 같이 비어
# 실제로는 두 칸씩 길어진다. 그 구간이 끊기기 전까지 weight 가 2 인 이유다.
# 한 번 막히고 나면 왼쪽의 빈칸 구간과 오른쪽의 빈칸 구간이 따로 놀므로
# 그 뒤로는 한 칸에 1 이다. 바깥에서 안으로 세면 이 이음매를 놓쳐 판
# 한가운데에 상한의 두 배짜리 구멍이 뚫린다.
static func _fill_row(g: BrickGrid, rng: RandomNumberGenerator, row: int,
		density_v: float, hard: float, gap: int) -> void:
	var half := Tuning.BRICK_COLS / 2
	var run := 0
	# 지금 세고 있는 빈칸 구간이 아직 판 가운데와 이어져 있는가.
	var spans_center := true
	for k in half:
		var col := half - 1 - k
		var weight := 2 if spans_center else 1
		var kind := 0
		# 빈칸 상한에 걸리면 밀도와 무관하게 채운다. 레버 D 가 레버 A 를
		# 이기는 쪽이 맞다 — 둘 다 어려워지는 방향이라 충돌이 아니다.
		if run + weight > gap or rng.randf() < density_v:
			kind = rng.randi_range(2, BrickGrid.MAX_HARD) if rng.randf() < hard else 1
			run = 0
			spans_center = false
		else:
			run += weight
		g.cells[BrickGrid.index(col, row)] = kind
		g.cells[BrickGrid.index(Tuning.BRICK_COLS - 1 - col, row)] = kind

# 쌍으로 놓는다. 최하단 줄(row 0)은 건너뛴다 — 최하단 줄이 통째로 막히면
# 위쪽 전부가 봉인된다. 줄 하나를 빼는 편이 "다 막혔는지" 검사하고 되돌리는
# 것보다 짧고, 되돌릴 일이 없으니 항상 끝난다.
static func _place_indestructible(g: BrickGrid, rng: RandomNumberGenerator,
		count: int) -> void:
	var half := Tuning.BRICK_COLS / 2
	var spots: Array[int] = []
	for row in range(1, Tuning.BRICK_ROWS):
		for col in half:
			if g.cells[BrickGrid.index(col, row)] > 0:
				spots.append(BrickGrid.index(col, row))
	# Array.shuffle() 은 전역 RNG 를 쓴다 — 시드가 안 먹어 판이 매번 달라진다.
	# 시드 붙은 rng 로 직접 섞는다.
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := spots[i]
		spots[i] = spots[j]
		spots[j] = t
	for i in mini(count / 2, spots.size()):
		var idx := spots[i]
		var row := idx / Tuning.BRICK_COLS
		var col := idx % Tuning.BRICK_COLS
		g.cells[idx] = BrickGrid.INDESTRUCTIBLE
		g.cells[BrickGrid.index(Tuning.BRICK_COLS - 1 - col, row)] = BrickGrid.INDESTRUCTIBLE
```

- [ ] **Step 5: 통과를 확인한다**

Run: `./run_tests.sh`

Expected: `test_stage_gen: OK`, 마지막 줄 `전체 통과`. 기존 10개 파일도 전부 통과해야 한다 — 이 태스크는 아직 `PlayField` 를 안 건드리므로 게임은 여전히 `fill_all(1)` 로 돈다.

- [ ] **Step 6: 변이 테스트 — 검사가 실제로 잡는지 본다**

세 번 망가뜨리고 매번 원복한다. 각각 **어느 단언이 어느 메시지로** 실패했는지 기록한다.

1. `stage()` 의 `rng.seed = index` 를 `rng.randomize()` 로 바꾼다.
   Expected: `같은 판 번호가 다른 배치를 냈다: 0`
2. `_fill_row` 의 미러 대입(`g.cells[BrickGrid.index(Tuning.BRICK_COLS - 1 - col, row)] = kind`) 줄을 지운다.
   Expected: `... 가 거울짝과 다르다: ...`
3. `_place_indestructible` 의 `range(1, Tuning.BRICK_ROWS)` 를 `range(0, Tuning.BRICK_ROWS)` 로 바꾼다.
   Expected: `... 의 최하단 ... 열이 불괴다 — 위쪽이 봉인된다`
4. `_fill_row` 의 `var weight := 2 if spans_center else 1` 을 `var weight := 1` 로 바꾼다.
   Expected: `... 줄에 빈칸이 ... 칸 이어졌다 (상한 ...)`. 판 한가운데 구멍이
   상한의 두 배가 되는 바로 그 버그다.

넷 다 확인하면 원복하고 `./run_tests.sh` 로 `전체 통과` 를 다시 본다.

- [ ] **Step 7: 커밋**

```bash
git add scripts/stage_gen.gd scripts/stage_gen.gd.uid scripts/brick_grid.gd tests/test_stage_gen.gd tests/test_stage_gen.gd.uid
git commit -m "feat: 판 번호로 배치를 만드는 StageGen"
```

`.uid` 파일은 Godot 이 `--import` 때 만든다. `git status --short` 로 실제로 생겼는지 확인하고, 없으면 `git add` 목록에서 뺀다. **`git add -A` 나 `git add .` 는 절대 쓰지 않는다.**

---

### Task 2: 판 진행 — 클리어하면 다음 판

**Files:**
- Modify: `scripts/play_field.gd`
- Modify: `scripts/game.gd:37-51` (`step_once` 의 lost/cleared 처리)
- Test: `tests/test_play_field.gd`
- Test: `tests/test_game_smoke.gd` (재시작 단언이 `fill_all(1)` 전제를 깔고 있다)

**Interfaces:**
- Consumes: Task 1 의 `StageGen.stage(index: int) -> BrickGrid`
- Produces:
  - `PlayField.stage_index: int` (0 기반, 초기값 0)
  - `PlayField.next_stage() -> void`
  - `PlayField.reset_run() -> void`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/test_play_field.gd` 의 `_initialize()` 에서 `_test_broken_list_carries_kind_before_the_destroying_hit()` **다음 줄**에 두 줄을 추가한다.

```gdscript
	_test_next_stage_advances_without_resetting_the_speed_ramp()
	_test_reset_run_returns_to_the_first_stage()
```

파일 끝에 두 함수를 붙인다.

```gdscript
# 판이 넘어가도 elapsed 는 이어진다. 판마다 0 으로 되돌리면 램프가 영원히
# 초반값에 머물러 난이도가 누적되지 않는다 — 100 판을 깨도 첫 판 속도다.
func _test_next_stage_advances_without_resetting_the_speed_ramp() -> void:
	var f := PlayField.new()
	f.elapsed = 42.0
	var before := f.grid.cells
	assert(f.stage_index == 0, "새 판이 0 판이 아니다: %d" % f.stage_index)
	f.next_stage()
	assert(f.stage_index == 1, "판 번호가 안 올랐다: %d" % f.stage_index)
	assert(is_equal_approx(f.elapsed, 42.0),
		"판이 넘어가며 속도 램프가 초기화됐다: %f" % f.elapsed)
	assert(f.grid.cells != before, "다음 판인데 배치가 그대로다")
	assert(f.grid.cells == StageGen.stage(1).cells, "1 판의 배치가 아니다")
	# 새 판 블럭 안에 공이 박힌 채로 시작하면 안 된다.
	assert(f.attached, "판이 넘어갔는데 공이 안 붙었다")

# 전멸하면 처음부터다. 판 번호가 안 돌아가면 마지막 판을 무한 반복한다.
func _test_reset_run_returns_to_the_first_stage() -> void:
	var f := PlayField.new()
	f.next_stage()
	f.next_stage()
	f.lives = 0
	f.elapsed = 99.0
	f.reset_run()
	assert(f.stage_index == 0, "판 번호가 0 으로 안 돌아갔다: %d" % f.stage_index)
	assert(f.lives == Tuning.LIVES, "목숨이 안 채워졌다: %d" % f.lives)
	assert(is_equal_approx(f.elapsed, 0.0), "속도 램프가 안 돌아갔다: %f" % f.elapsed)
	assert(f.grid.cells == StageGen.stage(0).cells, "0 판의 배치가 아니다")
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`

Expected: `test_play_field.gd` FAIL. `Invalid access to property or key 'stage_index'` 또는 `Function "next_stage()" not found` 계열의 SCRIPT ERROR.

- [ ] **Step 3: `PlayField` 에 판 상태를 넣는다**

`scripts/play_field.gd` 에서 `var elapsed: float = 0.0` **바로 아래**에 추가한다.

```gdscript
# 지금 몇 판인지. 0 기반이다 — HUD 만 +1 해서 보여준다. 시드가 이 값이라
# 이 숫자 하나가 배치 전체를 결정한다.
var stage_index: int = 0
```

`_init()` 의 두 줄을 바꾼다. 기존:

```gdscript
	grid = BrickGrid.new()
	grid.fill_all(1)
```

로 되어 있는 것을 이렇게 만든다.

```gdscript
	grid = StageGen.stage(stage_index)
```

파일 끝(`_touches_paddle()` 아래)에 두 메서드를 붙인다.

```gdscript
# 클리어. elapsed 는 일부러 안 건드린다 — 속도 램프는 판을 가로질러 이어져야
# 난이도가 누적된다. 공을 다시 붙이는 것은 새 판 블럭 한가운데에 공이 박힌
# 채로 시작하는 것을 막으려는 것이다.
func next_stage() -> void:
	stage_index += 1
	grid = StageGen.stage(stage_index)
	_attach()

# 전멸. 여기서만 램프가 0 으로 돌아간다.
func reset_run() -> void:
	lives = Tuning.LIVES
	elapsed = 0.0
	stage_index = 0
	grid = StageGen.stage(stage_index)
	_attach()
```

- [ ] **Step 4: `game.gd` 를 위임으로 바꾼다**

`scripts/game.gd` 의 `step_once()` 에서 lost/cleared 처리 블록을 바꾼다. 기존:

```gdscript
	if bool(r["lost"]):
		_trail.reset()
		# 마지막 목숨을 잃으면 처음부터 다시 — 1단계에는 게임오버 화면이 없다.
		if field.lives <= 0:
			field.lives = Tuning.LIVES
			field.elapsed = 0.0
			field.grid.fill_all(1)
			board.build(field.grid)
	if not field.attached:
		_trail.push(field.ball_pos, field.ball_vel.length())
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()
	if bool(r["cleared"]):
		field.grid.fill_all(1)
		board.build(field.grid)
```

를 이렇게 만든다.

```gdscript
	if bool(r["lost"]):
		_trail.reset()
		# 마지막 목숨을 잃으면 처음부터 다시 — 아직 게임오버 화면이 없다.
		if field.lives <= 0:
			field.reset_run()
			board.build(field.grid)
	if not field.attached:
		_trail.push(field.ball_pos, field.ball_vel.length())
	if bool(r["cleared"]):
		field.next_stage()
		_trail.reset()
		board.build(field.grid)
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()
```

`_update_hud()` 를 뒤로 옮긴 것은 순서 때문이다. 판 번호를 갱신하려면 `next_stage()` 가 먼저 돌아야 한다. 클리어에서도 `_trail.reset()` 을 부르는 것은 공이 다시 붙기 때문이다 — 안 지우면 이전 판에서 죽은 자리의 리본이 새 판 첫 발사에 이어진다.

- [ ] **Step 5: 깨진 기존 단언을 고친다**

`tests/test_game_smoke.gd` 의 `_test_last_life_restarts()` 는 재시작 후 격자가
**꽉 찼다**고 단언한다. 전멸 복구가 `fill_all(1)` 이던 시절의 단언이고, 이제
0 판은 밀도 55% 라 60 이 아니다. 이 줄을

```gdscript
	assert(g.field.grid.remaining() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS,
		"재시작인데 블럭이 안 채워졌다: %d" % g.field.grid.remaining())
```

이렇게 바꾼다.

```gdscript
	assert(g.field.grid.cells == StageGen.stage(0).cells,
		"재시작인데 0 판 배치가 아니다: 남은 블럭 %d" % g.field.grid.remaining())
	assert(g.field.stage_index == 0,
		"재시작인데 판 번호가 안 돌아갔다: %d" % g.field.stage_index)
```

숫자 60 을 다른 숫자로 바꾸는 게 아니라 **배치 자체를 비교하도록** 바꾸는 것이
핵심이다. "블럭이 좀 있다"는 단언은 `reset_run()` 이 엉뚱한 판을 만들어도
통과한다.

- [ ] **Step 6: 통과를 확인한다**

Run: `./run_tests.sh`

Expected: `전체 통과`. 10개 파일 전부다. `test_play_field.gd` 의
`_test_hard_brick_only_resets_stall_when_broken()` 은 기본 격자를 쓰지만 칸
(5,0)을 직접 덮어쓰므로 영향이 없어야 한다 — 만약 깨지면 그 자리에서 멈추고
왜 깨졌는지 보고할 것. 조용히 단언을 느슨하게 만들지 말 것.

- [ ] **Step 7: 변이 테스트**

1. `next_stage()` 에서 `_attach()` 를 지운다.
   Expected: `판이 넘어갔는데 공이 안 붙었다`
2. `next_stage()` 에 `elapsed = 0.0` 을 추가한다.
   Expected: `판이 넘어가며 속도 램프가 초기화됐다: 0.000000`
3. `reset_run()` 의 `stage_index = 0` 을 지운다.
   Expected: `판 번호가 0 으로 안 돌아갔다: 2`

원복하고 `./run_tests.sh` 로 `전체 통과` 를 다시 본다.

- [ ] **Step 8: 커밋**

```bash
git add scripts/play_field.gd scripts/game.gd tests/test_play_field.gd tests/test_game_smoke.gd
git commit -m "feat: 클리어하면 다음 판으로 넘어간다"
```

---

### Task 3: HUD 판 번호

**Files:**
- Modify: `scenes/game.tscn` (`HUD` 아래 `Stage` 라벨)
- Modify: `scripts/game.gd` (`@onready` 와 `_update_hud()`)
- Test: `tests/test_game_smoke.gd`

**Interfaces:**
- Consumes: Task 2 의 `PlayField.stage_index`
- Produces: 없음. 화면에만 나온다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/test_game_smoke.gd` 의 `_run()` 에서 `_test_stall_dots_follow_the_counter()` **다음 줄**에 추가한다.

```gdscript
	_test_stage_label_follows_the_stage_index()
```

파일 끝에 붙인다.

```gdscript
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `./run_tests.sh`

Expected: `test_game_smoke.gd` FAIL. `Invalid access to property or key 'stage_label'`.

- [ ] **Step 3: 씬에 라벨을 넣는다**

`scenes/game.tscn` 의 `[node name="Stall" ...]` 블록 **다음**, `[node name="Version" ...]` **앞**에 넣는다. 목숨(top 24)과 교착 점(top 68) 아래 줄이다.

```
[node name="Stage" type="Label" parent="HUD"]
offset_left = 24.0
offset_top = 112.0
offset_right = 320.0
offset_bottom = 152.0
text = "판 1"
```

`.tscn` 은 손으로 편집한다. **에디터로 열지 않는다** — 열면 `project.godot` 을 다시 써서 주석이 날아간다.

- [ ] **Step 4: `game.gd` 를 잇는다**

`@onready var stall_label: Label = $HUD/Stall` 아래에 추가한다.

```gdscript
@onready var stage_label: Label = $HUD/Stage
```

`_update_hud()` 에 한 줄 추가한다.

```gdscript
func _update_hud() -> void:
	lives_label.text = "목숨 %d" % field.lives
	# stage_index 는 0 기반이다. 플레이어에게 "0 판"을 보여줄 이유는 없다.
	stage_label.text = "판 %d" % (field.stage_index + 1)
```

- [ ] **Step 5: 통과를 확인한다**

Run: `./run_tests.sh`

Expected: `전체 통과`.

- [ ] **Step 6: 변이 테스트**

1. `_update_hud()` 의 `+ 1` 을 지운다.
   Expected: `첫 판 표시가 틀렸다: 판 0`
2. `stage_label.text` 줄 전체를 지운다.
   Expected: `판이 넘어갔는데 표시가 안 따라왔다: 판 1`

원복하고 `./run_tests.sh` 로 `전체 통과` 를 다시 본다.

- [ ] **Step 7: 커밋하고 푸시한다**

```bash
git add scenes/game.tscn scripts/game.gd tests/test_game_smoke.gd
git commit -m "feat: HUD 에 판 번호를 보여준다"
git push -u origin stage-progression
```

푸시하면 배포 워크플로가 돌아 라이브 화면의 버전 문구가 `... stage-progression <sha7>` 로 바뀐다. 그걸로 폰에서 보고 있는 것이 이 브랜치인지 확인한다.

---

## 사람이 판단할 것

테스트로 만들지 않는다. 배포 후 플레이로만 답이 나온다.

1. **절차 생성이 재미있나.** 이 청크가 존재하는 이유이고 2단계에서 가장 큰 위험이다. 재미없으면 `StageGen.stage()` 만 손으로 그린 판 로더로 갈아끼운다 — 이음매가 그러라고 있다.
2. **곡선이 너무 빠르거나 느린가.** 판 4 에서 단단 블럭, 판 8 에서 불괴 블럭이 나오는 일정이 체감상 맞는지. 상수 다섯 개(`RAMP_*`, `DENSITY_*`)만 만지면 된다.
3. **불괴 블럭 8개가 판을 지루하게 만드는가.** 상한을 6 으로 내리는 것이 첫 후보다.
4. **HUD 세 줄(목숨/교착/판)이 판을 가리는가.**

## 병합

```bash
git checkout main
git merge --no-ff stage-progression -m "merge: 절차 스테이지 생성과 판 진행"
git push origin main
git branch -d stage-progression
git push origin --delete stage-progression
```

`--no-ff` 는 선택이 아니다. fast-forward 면 SHA 가 같아 GitHub Pages 가 배포를 중복으로 보고 버린다.
