# 3DBlockBreaker 1단계 (물리 검증) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기울어진 판 위에서 중력을 받는 공을 탁구처럼 밀어 치는 벽돌깨기의 물리와 조작만 만들어, 폰에서 직접 쳐보고 튜닝값을 확정한다.

**Architecture:** 물리는 Godot 내장 물리를 쓰지 않고 판 위 2D 좌표 `(u, v)` 에서 직접 적분한다. 순수 로직(`Tuning`, `BallPhysics`, `BrickGrid`, `PaddleState`, `PlayField`)과 렌더링·입력(`BoardView`, `game.gd`)을 분리해, 물리 전체를 헤드리스 Godot 에서 assert 로 검증한다.

**Tech Stack:** Godot 4.7.2 / GDScript, 웹 export, GitHub Pages, 폰 세로 화면 터치

**Spec:** `docs/superpowers/specs/2026-09-03-3dblockbreaker-design.md`

## Global Constraints

- Godot **4.7.2**. `project.godot` 의 `config/features` 는 `PackedStringArray("4.7", "Forward Plus")`.
- 물리 틱 **120Hz** (`physics/common/physics_ticks_per_second=120`).
- 뷰포트 **720 × 1280**, `window/handheld/orientation=1` (세로).
- `pointing/emulate_touch_from_mouse=true` — 데스크톱에는 `InputEventScreenDrag` 가 없어 이게 없으면 조작 코드 전체가 맥에서 죽은 코드가 된다.
- 테스트는 `tests/test_*.gd`, `extends SceneTree`, `_initialize()` 에서 실행하고 마지막에 `print("<파일명 stem>: OK")` 후 `quit()`. 이 표식이 없으면 `run_tests.sh` 가 실패로 친다.
- 실패한 assert 는 헤드리스 Godot 을 무한 정지시킨다. 단일 테스트를 직접 돌릴 때도 반드시 시간 제한으로 감쌀 것.
- 물리 좌표는 언제나 `Vector2(u, v)`. `u` 좌우, `v` 는 플레이어 쪽이 0 이고 블럭 쪽이 큰 값. Godot 의 `Vector2.UP/DOWN` 은 화면 좌표계(y 아래로 증가) 기준이라 이 좌표계와 부호가 반대다 — **쓰지 말고 `Vector2(0, 1)` 처럼 명시할 것.**
- 모든 튜닝값은 `scripts/tuning.gd` 한 곳에만 둔다. 다른 파일에 물리 상수를 리터럴로 박지 않는다.
- 커밋 메시지는 한국어, `feat:` / `test:` / `chore:` 접두어.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `scripts/tuning.gd` | 튜닝 상수 전부. `V_MIN` 은 사거리 계약에서 파생 |
| `scripts/ball_physics.gd` | 순수 함수: 반사, 속도 clamp, 최소각 강제, 적분, 서브스텝, 벽 |
| `scripts/brick_grid.gd` | 블럭 격자 상태 + 원-AABB 질의 |
| `scripts/paddle_state.gd` | 패들 추종, 기울기 유도, 속도 평활, 스윕 상자, 법선 |
| `scripts/play_field.gd` | 위 넷을 묶어 한 스텝 진행. 발사, 목숨, 클리어 판정 |
| `scripts/board_view.gd` | 판·블럭·공·패들 메시 생성과 갱신, `(u,v)` → 판 로컬 변환 |
| `scripts/ball_trail.gd` | 속도에 비례하는 트레일 |
| `scripts/game.gd` | 터치 입력을 판 좌표로 바꿔 `PlayField` 를 돌리고 `BoardView` 를 갱신 |
| `scenes/game.tscn` | 카메라, 기울어진 판 노드, HUD, 위 스크립트 조립 |

`scripts/play_field.gd` 까지는 `Node` 를 상속하지 않는 `RefCounted` 다. 헤드리스에서 씬 없이 그대로 만들어 돌릴 수 있어야 한다.

---

### Task 1: 프로젝트 뼈대와 테스트 러너

**Files:**
- Create: `project.godot`, `.gitignore`, `run_tests.sh`, `tests/test_smoke.gd`
- Create: `scripts/.gdignore` 는 만들지 않는다 (스크립트를 임포트해야 `class_name` 이 등록된다)

**Interfaces:**
- Consumes: 없음
- Produces: `./run_tests.sh` — `tests/test_*.gd` 를 전부 돌리고 실패 시 종료코드 1

- [ ] **Step 1: 프로젝트 파일 생성**

`project.godot`:

```ini
; Engine configuration file.
config_version=5

[application]

config/name="3DBlockBreaker"
; 배포 워크플로가 빌드마다 날짜와 커밋 해시로 덮어쓴다. HUD 에 그대로
; 표시되므로 폰에서 지금 어떤 빌드를 보고 있는지 바로 알 수 있다.
config/version="dev"
run/main_scene="res://scenes/game.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[display]

window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation=1

[physics]

; 공이 빠를 때 한 스텝 이동거리를 줄여 터널링 여지를 좁힌다. 서브스텝은
; 그래도 필요하지만, 시작점이 낮을수록 서브스텝 수가 적어진다.
common/physics_ticks_per_second=120

[rendering]

renderer/rendering_method="forward_plus"

[input_devices]

; 데스크톱에는 InputEventScreenDrag 가 없다. 이게 없으면 조작 코드
; 전체가 에디터와 맥에서 죽은 코드가 된다.
pointing/emulate_touch_from_mouse=true
```

`.gitignore`:

```
.godot/
.DS_Store
*.translation
build/
.superpowers/
```

- [ ] **Step 2: 테스트 러너 가져오기**

blockbox 의 러너를 그대로 쓴다. perl `alarm` 가드, `--import` 선행, `OK` 표식 검사, `SCRIPT ERROR` 검사가 전부 실전에서 필요해서 붙은 것들이다.

```bash
cp ~/games/blockbox/run_tests.sh ./run_tests.sh
chmod +x run_tests.sh
```

- [ ] **Step 3: 실패하는 스모크 테스트 작성**

`tests/test_smoke.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_runner_catches_failure()
	print("test_smoke: OK")
	quit()

func _test_runner_catches_failure() -> void:
	# 러너가 살아 있는지만 본다. Task 2 부터 진짜 검사가 들어온다.
	assert(1 + 1 == 3, "일부러 실패시킨다 — 러너가 이걸 잡아야 한다")
```

- [ ] **Step 4: 러너가 실패를 잡는지 확인**

Run: `./run_tests.sh`
Expected: FAIL. `TIMEOUT` 또는 `SCRIPT ERROR` 와 함께 `FAIL: test_smoke.gd`, `테스트 실패`, 종료코드 1.

실패한 assert 가 헤드리스를 멈추는 것을 러너가 타임아웃으로 잡아내는지 여기서 확인해 둔다. 이걸 확인 안 하고 넘어가면 이후 모든 테스트가 조용히 통과처럼 보일 수 있다.

- [ ] **Step 5: 테스트를 통과하도록 고침**

```gdscript
func _test_runner_catches_failure() -> void:
	assert(1 + 1 == 2, "산수")
```

- [ ] **Step 6: 통과 확인**

Run: `./run_tests.sh`
Expected: `--- test_smoke.gd`, `test_smoke: OK`, `전체 통과`, 종료코드 0.

- [ ] **Step 7: 커밋**

```bash
git add project.godot .gitignore run_tests.sh tests/test_smoke.gd
git commit -m "chore: Godot 프로젝트 뼈대와 헤드리스 테스트 러너"
```

---

### Task 2: 튜닝 상수와 사거리 계약

**Files:**
- Create: `scripts/tuning.gd`
- Create: `tests/test_tuning.gd`

**Interfaces:**
- Consumes: 없음
- Produces: `class_name Tuning` — 모든 상수와 `static func v_min() -> float`

- [ ] **Step 1: 실패하는 테스트 작성**

이 테스트가 게임 규칙의 핵심 계약을 지킨다. "살살 받으면 최하단 줄만, 위쪽 줄은 밀어야 닿는다"가 숫자로 성립하는지 본다.

`tests/test_tuning.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_v_min_reaches_bottom_row()
	_test_v_min_falls_short_of_second_row()
	_test_v_max_reaches_top()
	_test_geometry_is_consistent()
	print("test_tuning: OK")
	quit()

# 패들 밴드 아래끝에서 수직 발사한 공이 도달하는 v. v0^2 / (2g) 만큼 오른다.
func _apex(v0: float) -> float:
	return Tuning.PADDLE_BAND_MIN_V + v0 * v0 / (2.0 * Tuning.GRAVITY)

func _test_v_min_reaches_bottom_row() -> void:
	var apex := _apex(Tuning.v_min())
	assert(apex >= Tuning.BRICK_BOTTOM_V - 0.001,
		"V_MIN 이 최하단 블럭 줄에 못 닿는다: apex=%f" % apex)

func _test_v_min_falls_short_of_second_row() -> void:
	# 하한만으로 둘째 줄까지 닿으면 미는 이유가 사라진다.
	var apex := _apex(Tuning.v_min())
	assert(apex < Tuning.BRICK_BOTTOM_V + 1.0,
		"V_MIN 만으로 둘째 줄까지 닿는다: apex=%f" % apex)

func _test_v_max_reaches_top() -> void:
	var apex := _apex(Tuning.V_MAX)
	assert(apex >= Tuning.BOARD_TOP_V,
		"최대 속도로도 상단 벽에 못 닿는다: apex=%f" % apex)

func _test_geometry_is_consistent() -> void:
	assert(Tuning.PADDLE_BAND_MAX_V < Tuning.BRICK_BOTTOM_V,
		"패들 밴드가 블럭 격자와 겹친다")
	assert(Tuning.BRICK_TOP_V < Tuning.BOARD_TOP_V, "블럭이 상단 벽을 넘는다")
	assert(is_equal_approx(Tuning.BRICK_TOP_V - Tuning.BRICK_BOTTOM_V,
		float(Tuning.BRICK_ROWS)), "블럭 격자 세로 길이와 줄 수가 어긋난다")
	assert(is_equal_approx(2.0 * Tuning.BOARD_HALF_WIDTH,
		float(Tuning.BRICK_COLS)), "판 폭과 열 수가 어긋난다")
	assert(Tuning.PADDLE_HALF_WIDTH < Tuning.BOARD_HALF_WIDTH,
		"패들이 판보다 넓다")
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "Tuning" not declared` 계열 SCRIPT ERROR.

- [ ] **Step 3: 최소 구현**

`scripts/tuning.gd`:

```gdscript
class_name Tuning
extends RefCounted

# --- 판 기하. 물리는 전부 이 (u, v) 좌표에서 돈다 ---
const BOARD_HALF_WIDTH := 5.0
const BOARD_TOP_V := 16.0
# 판을 얼마나 눕혀 보여줄지. 순수 시각 값이다. 중력을 g·sin(θ) 로 묶지
# 않는다 — 묶으면 튜닝 노브 두 개가 하나로 붙어 조정이 불편해진다.
const BOARD_TILT_DEG := 25.0

# --- 블럭 격자 ---
const BRICK_COLS := 10
const BRICK_ROWS := 6
const BRICK_BOTTOM_V := 9.0
const BRICK_TOP_V := 15.0

# --- 패들이 움직일 수 있는 띠 ---
const PADDLE_BAND_MIN_V := 0.4
const PADDLE_BAND_MAX_V := 3.0

# --- 공 ---
const GRAVITY := 12.0
const BALL_RADIUS := 0.25
const V_MAX := 34.0
# 공이 수평에 가까워지면 좌우 벽만 오가며 영영 안 내려온다.
const MIN_ANGLE_DEG := 15.0

# --- 패들 ---
# 이 게임에서 에너지를 잃는 유일한 곳. 벽과 블럭은 1.0 이다. 손실원이
# 하나뿐이라 "왜 느려졌나"의 답이 언제나 "그냥 받았으니까"가 된다.
const PADDLE_RESTITUTION := 0.80
const PADDLE_SPEED_TRANSFER := 0.60
const PADDLE_HALF_WIDTH := 1.0
const PADDLE_THICKNESS := 0.3
const PADDLE_MAX_SPEED_U := 40.0
const PADDLE_MAX_SPEED_V := 22.0
const PADDLE_MAX_TILT_DEG := 30.0
# 이 좌우 속도에서 최대 기울기에 도달한다.
const PADDLE_TILT_FULL_SPEED := 25.0
# 패들 각도만으로 법선을 정하면 손가락을 멈춘 순간 각도가 0 이라
# 수직 반사밖에 안 나온다. 접촉점 오프셋이 정지 상태의 조준을 만든다.
const CONTACT_ANGLE_MAX_DEG := 20.0
const PADDLE_VEL_SMOOTH_FRAMES := 3

const LIVES := 3

# 속도 하한은 숫자가 아니라 계약이다: 패들 밴드 아래끝에서 출발해
# 최하단 블럭 줄에 겨우 닿는 속도. 리터럴로 박으면 위 값을 조정할 때
# 계약이 조용히 깨진다.
static func v_min() -> float:
	return sqrt(2.0 * GRAVITY * (BRICK_BOTTOM_V - PADDLE_BAND_MIN_V))
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_tuning: OK`, `전체 통과`

- [ ] **Step 5: 변이 테스트로 검사가 실제로 무는지 확인**

`V_MAX` 를 잠시 `20.0` 으로 바꾸고 `./run_tests.sh` 를 돌린다. `_test_v_max_reaches_top` 이 실패해야 한다 — 최대 속도로도 상단 벽에 못 닿으면 판 위쪽 두 줄이 영영 안 깨진다. 확인 후 원복한다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/tuning.gd tests/test_tuning.gd
git commit -m "feat: 튜닝 상수와 사거리 계약 (V_MIN 은 파생값)"
```

---

### Task 3: 공 반사, 속도 clamp, 최소각 강제

**Files:**
- Create: `scripts/ball_physics.gd`
- Create: `tests/test_ball_physics.gd`

**Interfaces:**
- Consumes: `Tuning`
- Produces:
  - `BallPhysics.reflect(v: Vector2, n: Vector2) -> Vector2`
  - `BallPhysics.clamp_speed(v: Vector2, lo: float, hi: float) -> Vector2`
  - `BallPhysics.enforce_min_angle(v: Vector2, min_deg: float) -> Vector2`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_ball_physics.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_reflect_off_flat_paddle()
	_test_reflect_preserves_speed()
	_test_clamp_speed_raises_and_caps()
	_test_clamp_speed_on_zero_vector()
	_test_min_angle_lifts_near_horizontal()
	_test_min_angle_leaves_steep_alone()
	print("test_ball_physics: OK")
	quit()

func _test_reflect_off_flat_paddle() -> void:
	var up := Vector2(0.0, 1.0)
	var out := BallPhysics.reflect(Vector2(1.0, -1.0), up)
	assert(out.is_equal_approx(Vector2(1.0, 1.0)), "평평한 패들 반사가 틀렸다: %s" % out)

func _test_reflect_preserves_speed() -> void:
	var n := Vector2(0.3, 1.0).normalized()
	var v := Vector2(2.0, -7.0)
	var out := BallPhysics.reflect(v, n)
	assert(absf(out.length() - v.length()) < 0.0001,
		"반사가 속력을 바꿨다: %f -> %f" % [v.length(), out.length()])

func _test_clamp_speed_raises_and_caps() -> void:
	var slow := BallPhysics.clamp_speed(Vector2(0.0, 3.0), 10.0, 30.0)
	assert(absf(slow.length() - 10.0) < 0.0001, "하한으로 못 올렸다: %f" % slow.length())
	assert(slow.normalized().is_equal_approx(Vector2(0.0, 1.0)), "방향이 바뀌었다")
	var fast := BallPhysics.clamp_speed(Vector2(0.0, 99.0), 10.0, 30.0)
	assert(absf(fast.length() - 30.0) < 0.0001, "상한을 안 물었다: %f" % fast.length())

func _test_clamp_speed_on_zero_vector() -> void:
	# 0 벡터는 방향이 없다. 그대로 두면 공이 죽으므로 위로 세운다.
	var out := BallPhysics.clamp_speed(Vector2.ZERO, 10.0, 30.0)
	assert(absf(out.length() - 10.0) < 0.0001, "0 벡터에서 하한이 안 나왔다")
	assert(out.y > 0.0, "0 벡터는 위로 세워야 한다: %s" % out)

func _test_min_angle_lifts_near_horizontal() -> void:
	var v := Vector2(20.0, 0.2)
	var out := BallPhysics.enforce_min_angle(v, 15.0)
	var deg := absf(rad_to_deg(asin(out.y / out.length())))
	assert(deg >= 14.99, "최소각까지 못 세웠다: %f도" % deg)
	assert(absf(out.length() - v.length()) < 0.0001, "속력이 바뀌었다")
	assert(out.x > 0.0 and out.y > 0.0, "부호가 뒤집혔다: %s" % out)

func _test_min_angle_leaves_steep_alone() -> void:
	var v := Vector2(1.0, -20.0)
	var out := BallPhysics.enforce_min_angle(v, 15.0)
	assert(out.is_equal_approx(v), "이미 충분히 가파른데 건드렸다: %s" % out)
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "BallPhysics" not declared`

- [ ] **Step 3: 최소 구현**

`scripts/ball_physics.gd`:

```gdscript
class_name BallPhysics
extends RefCounted

static func reflect(v: Vector2, n: Vector2) -> Vector2:
	return v - 2.0 * v.dot(n) * n

# 방향은 그대로 두고 속력만 범위 안으로 넣는다. 0 벡터는 방향이 없어
# 그대로 두면 공이 죽으므로 위로 세운다.
static func clamp_speed(v: Vector2, lo: float, hi: float) -> Vector2:
	var s := v.length()
	if s < 0.0001:
		return Vector2(0.0, lo)
	return v * (clampf(s, lo, hi) / s)

# 공이 수평에 너무 가까우면 좌우 벽만 튕기며 영영 안 내려온다.
# 속력은 보존하고 각도만 최소각 밖으로 밀어낸다.
static func enforce_min_angle(v: Vector2, min_deg: float) -> Vector2:
	var s := v.length()
	if s < 0.0001:
		return v
	var min_sin := sin(deg_to_rad(min_deg))
	if absf(v.y) >= s * min_sin:
		return v
	var sign_y := 1.0 if v.y >= 0.0 else -1.0
	var sign_x := 1.0 if v.x >= 0.0 else -1.0
	return Vector2(sign_x * s * cos(deg_to_rad(min_deg)), sign_y * s * min_sin)
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_ball_physics: OK`

- [ ] **Step 5: 커밋**

```bash
git add scripts/ball_physics.gd tests/test_ball_physics.gd
git commit -m "feat: 공 반사, 속도 clamp, 최소각 강제"
```

---

### Task 4: 적분, 서브스텝, 벽 충돌

**Files:**
- Modify: `scripts/ball_physics.gd`
- Create: `tests/test_ball_integration.gd`

**Interfaces:**
- Consumes: `Tuning`, Task 3 의 `BallPhysics`
- Produces:
  - `BallPhysics.step_vel(vel: Vector2, dt: float) -> Vector2`
  - `BallPhysics.step_pos(pos: Vector2, vel: Vector2, dt: float) -> Vector2`
  - `BallPhysics.substeps(speed: float, dt: float) -> int`
  - `BallPhysics.resolve_walls(pos: Vector2, vel: Vector2) -> Array[Vector2]` — `[새 위치, 새 속도]`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_ball_integration.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_gravity_pulls_toward_player()
	_test_apex_matches_formula()
	_test_substeps_keep_step_under_radius()
	_test_wall_bounce_left_and_right()
	_test_top_wall_bounce()
	print("test_ball_integration: OK")
	quit()

func _test_gravity_pulls_toward_player() -> void:
	var v := BallPhysics.step_vel(Vector2(0.0, 10.0), 0.5)
	assert(v.y < 10.0, "중력이 v 를 줄이지 않는다: %s" % v)
	assert(is_equal_approx(v.y, 10.0 - Tuning.GRAVITY * 0.5), "중력 크기가 틀렸다: %s" % v)
	assert(is_equal_approx(v.x, 0.0), "중력이 u 를 건드렸다: %s" % v)

# 적분 결과가 v0^2/(2g) 공식과 맞는지 본다. 이게 어긋나면 Task 2 의
# 사거리 계약이 실제 게임에서는 성립하지 않는다.
func _test_apex_matches_formula() -> void:
	var dt := 1.0 / 120.0
	var pos := Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	var vel := Vector2(0.0, Tuning.v_min())
	var apex := pos.y
	for i in 2000:
		vel = BallPhysics.step_vel(vel, dt)
		pos = BallPhysics.step_pos(pos, vel, dt)
		apex = maxf(apex, pos.y)
		if vel.y < 0.0:
			break
	var expected := Tuning.PADDLE_BAND_MIN_V + Tuning.v_min() * Tuning.v_min() / (2.0 * Tuning.GRAVITY)
	# 세미암시적 오일러는 도달 높이를 약 v0·dt/2 만큼 낮게 잡는다. 원인을
	# 아는 오차라 그 두 배까지만 허용한다 — 그냥 큰 수를 넣어 눈감는 것과
	# 다르다. 위로 넘어가면 적분이 에너지를 만들어내고 있다는 뜻이다.
	assert(apex <= expected + 0.001,
		"적분이 공식보다 높이 올라간다 — 에너지가 늘어난다: %f vs %f" % [apex, expected])
	assert(expected - apex < Tuning.v_min() * dt,
		"적분 도달 높이가 공식과 너무 어긋난다: %f vs %f" % [apex, expected])

func _test_substeps_keep_step_under_radius() -> void:
	var dt := 1.0 / 120.0
	var n := BallPhysics.substeps(Tuning.V_MAX, dt)
	var per_step := Tuning.V_MAX * dt / float(n)
	assert(per_step <= Tuning.BALL_RADIUS + 0.0001,
		"서브스텝을 나눠도 한 스텝이 반지름보다 크다: %f" % per_step)
	assert(BallPhysics.substeps(0.0, dt) >= 1, "서브스텝은 최소 1이어야 한다")

func _test_wall_bounce_left_and_right() -> void:
	var lim := Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS
	var r := BallPhysics.resolve_walls(Vector2(-lim - 0.5, 5.0), Vector2(-8.0, 3.0))
	assert(is_equal_approx(r[0].x, -lim), "왼쪽 벽에서 위치가 안 밀려났다: %s" % r[0])
	assert(r[1].x > 0.0, "왼쪽 벽에서 안 튕겼다: %s" % r[1])
	assert(is_equal_approx(r[1].y, 3.0), "벽이 v 속도를 건드렸다: %s" % r[1])
	var r2 := BallPhysics.resolve_walls(Vector2(lim + 0.5, 5.0), Vector2(8.0, 3.0))
	assert(r2[1].x < 0.0, "오른쪽 벽에서 안 튕겼다: %s" % r2[1])

func _test_top_wall_bounce() -> void:
	var top := Tuning.BOARD_TOP_V - Tuning.BALL_RADIUS
	var r := BallPhysics.resolve_walls(Vector2(0.0, top + 0.5), Vector2(2.0, 9.0))
	assert(is_equal_approx(r[0].y, top), "상단 벽에서 위치가 안 밀려났다: %s" % r[0])
	assert(r[1].y < 0.0, "상단 벽에서 안 튕겼다: %s" % r[1])
	# 벽은 에너지를 잃지 않는다. 손실원은 패들 하나뿐이다.
	assert(absf(r[1].length() - Vector2(2.0, 9.0).length()) < 0.0001,
		"벽이 에너지를 먹었다: %f" % r[1].length())
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `step_vel` 등이 없다는 SCRIPT ERROR

- [ ] **Step 3: 최소 구현 — `scripts/ball_physics.gd` 끝에 추가**

```gdscript
# 세미암시적 오일러. 속도를 먼저 갱신하고 그 속도로 위치를 옮긴다.
# 순서를 바꾸면 에너지가 조금씩 늘어 감쇠 설계가 무너진다.
static func step_vel(vel: Vector2, dt: float) -> Vector2:
	return vel + Vector2(0.0, -Tuning.GRAVITY) * dt

static func step_pos(pos: Vector2, vel: Vector2, dt: float) -> Vector2:
	return pos + vel * dt

# 한 스텝 이동거리가 공 반지름을 넘으면 얇은 블럭을 그냥 통과한다.
static func substeps(speed: float, dt: float) -> int:
	return maxi(1, int(ceil(speed * dt / Tuning.BALL_RADIUS)))

# 좌우 벽과 상단 벽. 반발계수 1.0 — 에너지를 잃는 곳은 패들뿐이다.
# 파고든 만큼 위치를 되밀고 속도 부호를 안쪽으로 강제한다. 부호를
# 뒤집는 대신 강제하는 것은, 한 프레임에 두 번 처리돼도 벽에 들러붙지
# 않게 하려는 것이다.
static func resolve_walls(pos: Vector2, vel: Vector2) -> Array[Vector2]:
	var p := pos
	var v := vel
	var lim := Tuning.BOARD_HALF_WIDTH - Tuning.BALL_RADIUS
	if p.x < -lim:
		p.x = -lim
		v.x = absf(v.x)
	elif p.x > lim:
		p.x = lim
		v.x = -absf(v.x)
	var top := Tuning.BOARD_TOP_V - Tuning.BALL_RADIUS
	if p.y > top:
		p.y = top
		v.y = -absf(v.y)
	var out: Array[Vector2] = [p, v]
	return out
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_ball_integration: OK`

- [ ] **Step 5: 변이 테스트**

`step_vel` 과 `step_pos` 의 호출 순서를 테스트에서 뒤집어(명시적 오일러로) `_test_apex_matches_formula` 가 실제로 어긋나는지 본다. 확인 후 원복.

- [ ] **Step 6: 커밋**

```bash
git add scripts/ball_physics.gd tests/test_ball_integration.gd
git commit -m "feat: 공 적분, 서브스텝, 벽 충돌"
```

---

### Task 5: 블럭 격자와 원-AABB 질의

**Files:**
- Create: `scripts/brick_grid.gd`
- Create: `tests/test_brick_grid.gd`

**Interfaces:**
- Consumes: `Tuning`
- Produces:
  - `BrickGrid.new()` — 전부 빈 격자
  - `BrickGrid.index(col: int, row: int) -> int` (static)
  - `BrickGrid.cell_rect(col: int, row: int) -> Rect2` (static, `(u,v)` 공간)
  - `grid.fill_all(kind: int) -> void`
  - `grid.get_cell(col: int, row: int) -> int` — 범위 밖은 0
  - `grid.hit(col: int, row: int) -> void`
  - `grid.remaining() -> int`
  - `grid.query(center: Vector2, radius: float) -> Dictionary` — `{"hit": bool, "normal": Vector2, "col": int, "row": int, "depth": float}`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_brick_grid.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_index_is_unique()
	_test_cell_rects_tile_the_zone()
	_test_fill_and_hit()
	_test_query_face_normal()
	_test_query_corner_normal()
	_test_query_misses_empty_cell()
	_test_no_tunneling_at_max_speed()
	_test_gap_between_bricks_does_not_thrash()
	print("test_brick_grid: OK")
	quit()

func _test_index_is_unique() -> void:
	var seen := {}
	for row in Tuning.BRICK_ROWS:
		for col in Tuning.BRICK_COLS:
			var i := BrickGrid.index(col, row)
			assert(i >= 0 and i < Tuning.BRICK_COLS * Tuning.BRICK_ROWS,
				"인덱스 범위 밖: %d" % i)
			assert(not seen.has(i), "인덱스 충돌: %d" % i)
			seen[i] = true
	assert(seen.size() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS, "칸 수가 안 맞는다")

func _test_cell_rects_tile_the_zone() -> void:
	var first := BrickGrid.cell_rect(0, 0)
	assert(is_equal_approx(first.position.x, -Tuning.BOARD_HALF_WIDTH),
		"첫 열이 판 왼쪽 끝에서 시작하지 않는다: %s" % first)
	assert(is_equal_approx(first.position.y, Tuning.BRICK_BOTTOM_V),
		"첫 줄이 격자 아래끝에서 시작하지 않는다: %s" % first)
	var last := BrickGrid.cell_rect(Tuning.BRICK_COLS - 1, Tuning.BRICK_ROWS - 1)
	assert(is_equal_approx(last.position.x + last.size.x, Tuning.BOARD_HALF_WIDTH),
		"마지막 열이 판 오른쪽 끝과 안 맞는다: %s" % last)
	assert(is_equal_approx(last.position.y + last.size.y, Tuning.BRICK_TOP_V),
		"마지막 줄이 격자 위끝과 안 맞는다: %s" % last)

func _test_fill_and_hit() -> void:
	var g := BrickGrid.new()
	assert(g.remaining() == 0, "새 격자는 비어 있어야 한다")
	g.fill_all(1)
	assert(g.remaining() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS, "다 안 찼다")
	g.hit(3, 2)
	assert(g.get_cell(3, 2) == 0, "맞은 칸이 안 비었다")
	assert(g.get_cell(4, 2) == 1, "옆 칸이 같이 지워졌다")
	assert(g.remaining() == Tuning.BRICK_COLS * Tuning.BRICK_ROWS - 1, "남은 수가 틀렸다")
	assert(g.get_cell(-1, 0) == 0 and g.get_cell(0, 999) == 0, "범위 밖은 0이어야 한다")

func _test_query_face_normal() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var r := BrickGrid.cell_rect(5, 0)
	# 최하단 줄의 아래 면에 아래쪽에서 닿는다.
	var center := Vector2(r.position.x + 0.5, r.position.y - 0.2)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "면에 닿았는데 못 잡았다")
	assert(q["normal"].is_equal_approx(Vector2(0.0, -1.0)),
		"아래 면 법선이 틀렸다: %s" % q["normal"])
	assert(q["row"] == 0, "줄 번호가 틀렸다: %d" % q["row"])

func _test_query_corner_normal() -> void:
	var g := BrickGrid.new()
	# 블럭 하나만 남기고 그 꼭짓점에 비스듬히 닿는다.
	g.fill_all(0)
	g.cells[BrickGrid.index(5, 0)] = 1
	var r := BrickGrid.cell_rect(5, 0)
	var corner := Vector2(r.position.x, r.position.y)
	var center := corner + Vector2(-0.12, -0.12)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "꼭짓점에 닿았는데 못 잡았다")
	# 면 법선이 아니라 중심-꼭짓점 방향이어야 한다.
	assert(q["normal"].x < -0.5 and q["normal"].y < -0.5,
		"꼭짓점 법선이 면 법선으로 나왔다: %s" % q["normal"])

func _test_query_misses_empty_cell() -> void:
	var g := BrickGrid.new()
	var r := BrickGrid.cell_rect(5, 0)
	var q := g.query(Vector2(r.position.x + 0.5, r.position.y + 0.5), Tuning.BALL_RADIUS)
	assert(not q["hit"], "빈 격자에서 충돌이 나왔다")

# 최대 속도 공을 서브스텝으로 쪼개 격자에 던진다. 한 번은 잡혀야 한다.
func _test_no_tunneling_at_max_speed() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var dt := 1.0 / 120.0
	var pos := Vector2(0.1, Tuning.BRICK_BOTTOM_V - 2.0)
	var vel := Vector2(0.0, Tuning.V_MAX)
	var hit_count := 0
	for frame in 60:
		var n := BallPhysics.substeps(vel.length(), dt)
		var sub := dt / float(n)
		for s in n:
			vel = BallPhysics.step_vel(vel, sub)
			pos = BallPhysics.step_pos(pos, vel, sub)
			var q := g.query(pos, Tuning.BALL_RADIUS)
			if q["hit"]:
				hit_count += 1
				g.hit(q["col"], q["row"])
				vel = BallPhysics.reflect(vel, q["normal"])
				pos += q["normal"] * q["depth"]
		if pos.y > Tuning.BRICK_TOP_V + 1.0:
			break
	assert(hit_count > 0, "최대 속도 공이 격자를 통과했다 — 터널링")

# 인접한 두 블럭 사이의 이음매를 스쳐도 법선이 튀지 않아야 한다.
func _test_gap_between_bricks_does_not_thrash() -> void:
	var g := BrickGrid.new()
	g.fill_all(1)
	var seam_u := BrickGrid.cell_rect(5, 0).position.x
	var center := Vector2(seam_u, Tuning.BRICK_BOTTOM_V - 0.2)
	var q := g.query(center, Tuning.BALL_RADIUS)
	assert(q["hit"], "이음매 아래에서 못 잡았다")
	assert(q["normal"].y < -0.3,
		"이음매에서 법선이 아래를 안 가리킨다 — 공이 격자 안으로 빨려든다: %s" % q["normal"])
	assert(is_equal_approx(q["normal"].length(), 1.0),
		"법선이 단위벡터가 아니다: %f" % q["normal"].length())
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "BrickGrid" not declared`

- [ ] **Step 3: 최소 구현**

`scripts/brick_grid.gd`:

```gdscript
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
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_brick_grid: OK`

- [ ] **Step 5: 변이 테스트**

`query` 의 `n = away / dist` 를 면 법선 `Vector2(0.0, -1.0)` 고정으로 바꿔 `_test_query_corner_normal` 이 실패하는지 본다. 서브스텝 호출을 없애 `_test_no_tunneling_at_max_speed` 가 실패하는지 본다. 둘 다 확인 후 원복.

- [ ] **Step 6: 커밋**

```bash
git add scripts/brick_grid.gd tests/test_brick_grid.gd
git commit -m "feat: 블럭 격자와 원-AABB 질의 (모서리 법선 포함)"
```

---

### Task 6: 패들 상태 — 추종, 기울기, 속도 평활, 스윕

**Files:**
- Create: `scripts/paddle_state.gd`
- Create: `tests/test_paddle_state.gd`

**Interfaces:**
- Consumes: `Tuning`
- Produces:
  - `PaddleState.new(start_u: float)` — `pos`, `prev_pos`, `vel`, `tilt_deg`, `half_width` 필드
  - `paddle.update(target: Vector2, dt: float) -> void`
  - `paddle.normal() -> Vector2`
  - `paddle.contact_normal(ball_u: float) -> Vector2`
  - `paddle.rect() -> Rect2`
  - `paddle.swept_rect() -> Rect2`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_paddle_state.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_follows_finger_sideways()
	_test_forward_push_is_slower_than_sideways()
	_test_stays_inside_band_and_walls()
	_test_tilt_follows_sideways_velocity()
	_test_normal_points_toward_swing_direction()
	_test_contact_normal_aims_when_still()
	_test_velocity_is_smoothed()
	_test_swept_rect_covers_previous_position()
	print("test_paddle_state: OK")
	quit()

const DT := 1.0 / 120.0

func _test_follows_finger_sideways() -> void:
	var p := PaddleState.new(0.0)
	for i in 60:
		p.update(Vector2(3.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(absf(p.pos.x - 3.0) < 0.01, "손가락을 못 따라갔다: %f" % p.pos.x)

func _test_forward_push_is_slower_than_sideways() -> void:
	var a := PaddleState.new(0.0)
	var b := PaddleState.new(0.0)
	a.update(Vector2(5.0, Tuning.PADDLE_BAND_MIN_V), DT)
	b.update(Vector2(0.0, Tuning.PADDLE_BAND_MAX_V), DT)
	var moved_u := absf(a.pos.x)
	var moved_v := absf(b.pos.y - Tuning.PADDLE_BAND_MIN_V)
	assert(moved_u > moved_v,
		"앞으로 밀기가 좌우보다 느려야 한다: u=%f v=%f" % [moved_u, moved_v])
	assert(moved_u <= Tuning.PADDLE_MAX_SPEED_U * DT + 0.0001, "좌우 상한을 넘었다")
	assert(moved_v <= Tuning.PADDLE_MAX_SPEED_V * DT + 0.0001, "앞뒤 상한을 넘었다")

func _test_stays_inside_band_and_walls() -> void:
	var p := PaddleState.new(0.0)
	for i in 300:
		p.update(Vector2(99.0, 99.0), DT)
	assert(p.pos.y <= Tuning.PADDLE_BAND_MAX_V + 0.0001, "밴드 위로 나갔다: %f" % p.pos.y)
	assert(p.pos.x + p.half_width <= Tuning.BOARD_HALF_WIDTH + 0.0001,
		"패들이 벽을 뚫었다: %f" % p.pos.x)
	for i in 300:
		p.update(Vector2(-99.0, -99.0), DT)
	assert(p.pos.y >= Tuning.PADDLE_BAND_MIN_V - 0.0001, "밴드 아래로 나갔다: %f" % p.pos.y)
	assert(p.pos.x - p.half_width >= -Tuning.BOARD_HALF_WIDTH - 0.0001, "왼쪽 벽을 뚫었다")

func _test_tilt_follows_sideways_velocity() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(p.tilt_deg > 0.0, "오른쪽으로 휘두르는데 기울기가 0 이하: %f" % p.tilt_deg)
	assert(p.tilt_deg <= Tuning.PADDLE_MAX_TILT_DEG + 0.0001,
		"최대 기울기를 넘었다: %f" % p.tilt_deg)

func _test_normal_points_toward_swing_direction() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var n := p.normal()
	assert(n.x > 0.0, "오른쪽으로 휘둘렀는데 법선이 오른쪽을 안 본다: %s" % n)
	assert(n.y > 0.0, "법선이 블럭 쪽을 안 본다: %s" % n)
	assert(is_equal_approx(n.length(), 1.0), "법선이 단위벡터가 아니다")

func _test_contact_normal_aims_when_still() -> void:
	var p := PaddleState.new(0.0)
	for i in 10:
		p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	assert(absf(p.tilt_deg) < 0.001, "정지 상태인데 기울어져 있다: %f" % p.tilt_deg)
	# 정지 상태에서도 접촉점으로 좌우를 겨눌 수 있어야 한다.
	var right := p.contact_normal(p.pos.x + p.half_width)
	var left := p.contact_normal(p.pos.x - p.half_width)
	assert(right.x > 0.1, "패들 오른쪽 끝에 맞았는데 오른쪽으로 안 간다: %s" % right)
	assert(left.x < -0.1, "패들 왼쪽 끝에 맞았는데 왼쪽으로 안 간다: %s" % left)
	var center := p.contact_normal(p.pos.x)
	assert(absf(center.x) < 0.001, "정중앙은 수직이어야 한다: %s" % center)

func _test_velocity_is_smoothed() -> void:
	var p := PaddleState.new(0.0)
	# 한 프레임만 크게 튀는 지터. 평활 없이는 그대로 공에 실린다.
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	p.update(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
	p.update(Vector2(99.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var raw := (p.pos.x - p.prev_pos.x) / DT
	assert(p.vel.x < raw * 0.9,
		"한 프레임 지터가 그대로 속도가 됐다: vel=%f raw=%f" % [p.vel.x, raw])

func _test_swept_rect_covers_previous_position() -> void:
	var p := PaddleState.new(-3.0)
	# 10 프레임이면 아직 목표에도 벽에도 못 닿아 계속 움직이는 중이다.
	# 멈춘 뒤에 재면 스윕 상자가 정지 상자와 같아져 아무것도 안 잰다.
	for i in 10:
		p.update(Vector2(3.0, Tuning.PADDLE_BAND_MIN_V), DT)
	var swept := p.swept_rect()
	assert(swept.has_point(p.prev_pos), "스윕 상자가 이전 위치를 안 덮는다")
	assert(swept.has_point(p.pos), "스윕 상자가 현재 위치를 안 덮는다")
	assert(swept.size.x > p.rect().size.x, "움직이는 중인데 스윕 상자가 정지 상자와 같다")
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "PaddleState" not declared`

- [ ] **Step 3: 최소 구현**

`scripts/paddle_state.gd`:

```gdscript
class_name PaddleState
extends RefCounted

var pos: Vector2
var prev_pos: Vector2
var vel: Vector2 = Vector2.ZERO
var tilt_deg: float = 0.0
var half_width: float = Tuning.PADDLE_HALF_WIDTH

var _vel_samples: Array[Vector2] = []

func _init(start_u: float = 0.0) -> void:
	pos = Vector2(start_u, Tuning.PADDLE_BAND_MIN_V)
	prev_pos = pos

# 목표(손가락)를 향해 축별 최대속도로 추종한다. 순간이동을 허용하면
# 패들 속도가 무한대로 튀어 공에 비정상적인 힘이 실리고, 텔레포트가
# 공을 그대로 통과한다. 이 상한이 곧 스윙 세기의 상한이며, 그래서
# 별도의 쿨다운이나 스윙 게이지가 필요 없다.
func update(target: Vector2, dt: float) -> void:
	prev_pos = pos
	var lim_u := Tuning.BOARD_HALF_WIDTH - half_width
	var goal := Vector2(
		clampf(target.x, -lim_u, lim_u),
		clampf(target.y, Tuning.PADDLE_BAND_MIN_V, Tuning.PADDLE_BAND_MAX_V))
	var d := goal - pos
	pos.x += clampf(d.x, -Tuning.PADDLE_MAX_SPEED_U * dt, Tuning.PADDLE_MAX_SPEED_U * dt)
	pos.y += clampf(d.y, -Tuning.PADDLE_MAX_SPEED_V * dt, Tuning.PADDLE_MAX_SPEED_V * dt)
	_push_vel((pos - prev_pos) / dt)
	tilt_deg = clampf(
		vel.x / Tuning.PADDLE_TILT_FULL_SPEED * Tuning.PADDLE_MAX_TILT_DEG,
		-Tuning.PADDLE_MAX_TILT_DEG, Tuning.PADDLE_MAX_TILT_DEG)

# 터치 샘플링에는 지터가 있다. 한 프레임 델타를 그대로 쓰면 손가락을
# 멈춰도 속도가 튀는데, 이 값이 공에 실리고 기울기까지 정한다.
func _push_vel(sample: Vector2) -> void:
	_vel_samples.push_back(sample)
	while _vel_samples.size() > Tuning.PADDLE_VEL_SMOOTH_FRAMES:
		_vel_samples.pop_front()
	var sum := Vector2.ZERO
	for s in _vel_samples:
		sum += s
	vel = sum / float(_vel_samples.size())

# 기울기를 법선으로 바꾼다. Godot 의 rotated() 는 수학 방향(반시계)이라
# 오른쪽 기울기에서 +u 성분을 얻으려면 음수 각을 준다.
func normal() -> Vector2:
	return Vector2(0.0, 1.0).rotated(-deg_to_rad(tilt_deg))

# 패들 각도만 쓰면 손가락을 멈춘 순간 각도가 0 이라 수직 반사밖에
# 안 나와 조준이 불가능해진다. 접촉점 오프셋이 정지 상태의 조준이다.
func contact_normal(ball_u: float) -> Vector2:
	var offset := clampf((ball_u - pos.x) / half_width, -1.0, 1.0)
	var deg := tilt_deg + offset * Tuning.CONTACT_ANGLE_MAX_DEG
	return Vector2(0.0, 1.0).rotated(-deg_to_rad(deg))

func rect() -> Rect2:
	return _rect_at(pos)

# 패들은 축정렬 상자다. 이전 상자와 현재 상자를 합친 AABB 로 스윕이
# 된다 — 빠른 패들이 느린 공을 그냥 지나치는 것을 막는다. 대각 이동에서
# 약간 과하게 잡지만, 한 프레임 이동량이 작아 실제 오차가 없다.
func swept_rect() -> Rect2:
	return _rect_at(pos).merge(_rect_at(prev_pos))

func _rect_at(p: Vector2) -> Rect2:
	return Rect2(
		p.x - half_width, p.y - Tuning.PADDLE_THICKNESS * 0.5,
		half_width * 2.0, Tuning.PADDLE_THICKNESS)
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_paddle_state: OK`

- [ ] **Step 5: 변이 테스트**

`normal()` 의 `-deg_to_rad` 에서 음수 부호를 빼고 `_test_normal_points_toward_swing_direction` 이 실패하는지 본다. 부호가 뒤집히면 휘두른 반대쪽으로 공이 날아가는데, 눈으로는 알아채기 어렵고 손으로만 이상함을 느낀다. 확인 후 원복.

- [ ] **Step 6: 커밋**

```bash
git add scripts/paddle_state.gd tests/test_paddle_state.gd
git commit -m "feat: 패들 추종, 기울기 유도, 속도 평활, 스윕 상자"
```

---

### Task 7: PlayField — 물리 세계 통합

**Files:**
- Modify: `scripts/ball_physics.gd` (`paddle_bounce` 추가)
- Create: `scripts/play_field.gd`
- Create: `tests/test_play_field.gd`

**Interfaces:**
- Consumes: `Tuning`, `BallPhysics`, `BrickGrid`, `PaddleState`
- Produces:
  - `BallPhysics.paddle_bounce(v_in: Vector2, normal: Vector2, paddle_vel: Vector2) -> Vector2`
  - `PlayField.new()` — `grid`, `paddle`, `ball_pos`, `ball_vel`, `attached`, `lives` 필드
  - `field.launch(swing: Vector2) -> void`
  - `field.step(target: Vector2, dt: float) -> Dictionary` — `{"paddle_hit": bool, "bricks_hit": int, "lost": bool, "cleared": bool}`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_play_field.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_passive_bounce_lands_on_v_min()
	_test_decay_sequence_shrinks_then_stops()
	_test_swing_accelerates_ball()
	_test_tilted_swing_changes_direction()
	_test_paddle_never_double_bounces()
	_test_ball_below_zero_costs_a_life()
	_test_clearing_all_bricks_reports_cleared()
	print("test_play_field: OK")
	quit()

const DT := 1.0 / 120.0

# 패들을 가만히 둔 채 공을 한 번 받게 하고, 받은 직후 속도를 돌려준다.
func _bounce_once(v_in: Vector2) -> Vector2:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = v_in
	for i in 240:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			return f.ball_vel
		if r["lost"]:
			break
	assert(false, "패들에 안 맞았다")
	return Vector2.ZERO

func _test_passive_bounce_lands_on_v_min() -> void:
	var out := _bounce_once(Vector2(0.0, -Tuning.v_min()))
	assert(absf(out.length() - Tuning.v_min()) < 0.001,
		"가만히 받았는데 하한이 안 나온다: %f" % out.length())
	assert(out.y > 0.0, "받은 공이 위로 안 간다: %s" % out)

# 세게 친 공을 계속 가만히 받으면 도달 높이가 눈에 띄게 줄다가
# 하한에서 멈춘다. 이게 이 게임의 감쇠 설계 전부다.
func _test_decay_sequence_shrinks_then_stops() -> void:
	var speeds: Array[float] = []
	var v := 30.0
	for i in 6:
		var out := _bounce_once(Vector2(0.0, -v))
		v = out.length()
		speeds.append(v)
	for i in range(1, 4):
		assert(speeds[i] < speeds[i - 1] - 0.5,
			"%d번째에서 감쇠가 멈췄다: %s" % [i, str(speeds)])
	assert(absf(speeds[5] - Tuning.v_min()) < 0.001,
		"하한에 안 내려앉았다: %s" % str(speeds))

func _test_swing_accelerates_ball() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	# 손가락을 앞으로 밀면서 받는다.
	for i in 240:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MAX_V), DT)
		if r["paddle_hit"]:
			break
	assert(f.ball_vel.length() > Tuning.v_min() + 1.0,
		"밀었는데 가속이 안 됐다: %f" % f.ball_vel.length())

func _test_tilted_swing_changes_direction() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V + 0.6)
	f.ball_vel = Vector2(0.0, -Tuning.v_min())
	for i in 240:
		# 오른쪽으로 휘두르며 받는다. 목표를 계속 오른쪽으로 준다.
		var r := f.step(Vector2(f.paddle.pos.x + 1.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			break
	assert(f.ball_vel.x > 0.5,
		"오른쪽으로 휘둘렀는데 공이 오른쪽으로 안 간다: %s" % f.ball_vel)

func _test_paddle_never_double_bounces() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(0.0, Tuning.PADDLE_BAND_MIN_V)
	f.ball_vel = Vector2(0.0, -1.0)
	var hits := 0
	for i in 20:
		var r := f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)
		if r["paddle_hit"]:
			hits += 1
	assert(hits == 1, "접촉이 이어지는 동안 여러 번 튕겼다: %d" % hits)

func _test_ball_below_zero_costs_a_life() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.attached = false
	f.ball_pos = Vector2(4.5, 0.2)
	f.ball_vel = Vector2(0.0, -20.0)
	var before := f.lives
	var lost := false
	for i in 60:
		if f.step(Vector2(-4.0, Tuning.PADDLE_BAND_MIN_V), DT)["lost"]:
			lost = true
			break
	assert(lost, "공이 데드존으로 나갔는데 lost 가 아니다")
	assert(f.lives == before - 1, "목숨이 안 줄었다: %d -> %d" % [before, f.lives])
	assert(f.attached, "공을 잃으면 패들에 다시 붙어야 한다")

func _test_clearing_all_bricks_reports_cleared() -> void:
	var f := PlayField.new()
	f.grid.fill_all(0)
	f.grid.cells[BrickGrid.index(5, 0)] = 1
	f.attached = false
	var r := BrickGrid.cell_rect(5, 0)
	f.ball_pos = Vector2(r.position.x + 0.5, r.position.y - 0.3)
	f.ball_vel = Vector2(0.0, 8.0)
	var cleared := false
	for i in 60:
		if f.step(Vector2(0.0, Tuning.PADDLE_BAND_MIN_V), DT)["cleared"]:
			cleared = true
			break
	assert(cleared, "마지막 블럭을 깼는데 cleared 가 안 나온다")
	assert(f.grid.remaining() == 0, "블럭이 남아 있다")
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "PlayField" not declared`

- [ ] **Step 3: `scripts/ball_physics.gd` 에 패들 반사 추가**

```gdscript
# 이 게임의 전부인 식. 네 줄이 감쇠, 가속, 조준, 교착 방지를 만든다.
#
# 이미 패들에서 멀어지는 중이면 손대지 않는다. 접촉이 두 프레임 이어질 때
# 두 번 튕겨 공이 패들 안에서 진동하는 것을 막는다.
static func paddle_bounce(v_in: Vector2, normal: Vector2, paddle_vel: Vector2) -> Vector2:
	if v_in.dot(normal) >= 0.0:
		return v_in
	var out := reflect(v_in, normal) * Tuning.PADDLE_RESTITUTION
	out += paddle_vel * Tuning.PADDLE_SPEED_TRANSFER
	out = clamp_speed(out, Tuning.v_min(), Tuning.V_MAX)
	return enforce_min_angle(out, Tuning.MIN_ANGLE_DEG)
```

- [ ] **Step 4: `scripts/play_field.gd` 구현**

```gdscript
class_name PlayField
extends RefCounted

var grid: BrickGrid
var paddle: PaddleState
var ball_pos: Vector2
var ball_vel: Vector2 = Vector2.ZERO
var attached: bool = true
var lives: int = Tuning.LIVES

func _init() -> void:
	grid = BrickGrid.new()
	grid.fill_all(1)
	paddle = PaddleState.new(0.0)
	_attach()

func _attach() -> void:
	attached = true
	ball_vel = Vector2.ZERO
	ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)

# 붙어 있는 공을 스윙 속도로 쏜다. 탭만 하면(스윙 0) 하한으로 수직
# 발사한다. 첫 입력부터 스윙 문법을 가르치므로 튜토리얼이 필요 없다.
func launch(swing: Vector2) -> void:
	if not attached:
		return
	attached = false
	ball_vel = BallPhysics.enforce_min_angle(
		BallPhysics.clamp_speed(
			Vector2(0.0, Tuning.v_min()) + swing * Tuning.PADDLE_SPEED_TRANSFER,
			Tuning.v_min(), Tuning.V_MAX),
		Tuning.MIN_ANGLE_DEG)

func step(target: Vector2, dt: float) -> Dictionary:
	paddle.update(target, dt)
	var out := {"paddle_hit": false, "bricks_hit": 0, "lost": false, "cleared": false}
	if attached:
		ball_pos = paddle.pos + Vector2(0.0, Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS)
		return out

	# 한 스텝 이동거리가 반지름을 넘지 않도록 쪼갠다. 안 쪼개면 빠른
	# 공이 얇은 블럭을 그냥 통과한다.
	var n := BallPhysics.substeps(ball_vel.length(), dt)
	var sub := dt / float(n)
	for s in n:
		ball_vel = BallPhysics.step_vel(ball_vel, sub)
		ball_pos = BallPhysics.step_pos(ball_pos, ball_vel, sub)

		var wall := BallPhysics.resolve_walls(ball_pos, ball_vel)
		ball_pos = wall[0]
		ball_vel = wall[1]

		var q := grid.query(ball_pos, Tuning.BALL_RADIUS)
		if q["hit"]:
			grid.hit(q["col"], q["row"])
			out["bricks_hit"] = int(out["bricks_hit"]) + 1
			# 블럭은 에너지를 잃지 않는다. 손실원은 패들뿐이다.
			ball_vel = BallPhysics.reflect(ball_vel, q["normal"])
			ball_pos += q["normal"] * q["depth"]

		if not out["paddle_hit"] and _touches_paddle():
			var n_p := paddle.contact_normal(ball_pos.x)
			var before := ball_vel
			ball_vel = BallPhysics.paddle_bounce(before, n_p, paddle.vel)
			if ball_vel != before:
				out["paddle_hit"] = true
				# 패들 표면 밖으로 꺼내 다음 스텝에 다시 물리지 않게 한다.
				ball_pos.y = paddle.pos.y + Tuning.PADDLE_THICKNESS * 0.5 + Tuning.BALL_RADIUS

		if ball_pos.y < 0.0:
			lives -= 1
			out["lost"] = true
			_attach()
			break

	if grid.remaining() == 0:
		out["cleared"] = true
	return out

# 공 원이 패들의 스윕 상자에 닿았는지. 상자가 축정렬이라 가장 가까운
# 점까지의 거리로 판정한다.
func _touches_paddle() -> bool:
	var r := paddle.swept_rect()
	var nearest := Vector2(
		clampf(ball_pos.x, r.position.x, r.position.x + r.size.x),
		clampf(ball_pos.y, r.position.y, r.position.y + r.size.y))
	return ball_pos.distance_to(nearest) < Tuning.BALL_RADIUS
```

- [ ] **Step 5: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_play_field: OK`, `전체 통과`

- [ ] **Step 6: 변이 테스트**

`paddle_bounce` 의 `clamp_speed` 호출을 빼고 `_test_decay_sequence_shrinks_then_stops` 가 실패하는지 본다(하한 없이 무한 감속). `paddle_bounce` 첫 줄의 `dot >= 0` 가드를 빼고 `_test_paddle_never_double_bounces` 가 실패하는지 본다. 둘 다 확인 후 원복.

- [ ] **Step 7: 커밋**

```bash
git add scripts/ball_physics.gd scripts/play_field.gd tests/test_play_field.gd
git commit -m "feat: PlayField 통합 — 패들 반사, 감쇠, 목숨, 클리어"
```

---

### Task 8: 판 좌표 변환과 렌더링

**Files:**
- Create: `scripts/board_view.gd`
- Create: `tests/test_board_view.gd`

**Interfaces:**
- Consumes: `Tuning`, `BrickGrid`, `PaddleState`
- Produces:
  - `BoardView.board_to_local(p: Vector2, height: float) -> Vector3` (static)
  - `BoardView.brick_height(kind: int) -> float` (static)
  - `view.build(grid: BrickGrid) -> void` — 블럭 메시 생성
  - `view.sync(field: PlayField) -> void` — 공·패들·블럭 표시 갱신

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_board_view.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_local_mapping()
	_test_tilted_board_lifts_far_end()
	_test_brick_heights_differ_by_kind()
	_test_build_and_remove_bricks()
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
	# 1단계는 일반 블럭만 쓰지만, 종류별 높이는 이 함수 하나에 모아 둔다.
	assert(BoardView.brick_height(1) > 0.0, "일반 블럭 높이가 0 이다")
	assert(BoardView.brick_height(2) > BoardView.brick_height(1),
		"단단한 블럭이 더 두꺼워야 한다")
	assert(BoardView.brick_height(3) > BoardView.brick_height(2),
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
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "BoardView" not declared`

- [ ] **Step 3: 최소 구현**

`scripts/board_view.gd`:

```gdscript
class_name BoardView
extends Node3D

# 블럭 60개는 개별 MeshInstance3D 로 충분하다. MultiMesh 배칭은 이
# 규모에 과하고, 배칭하면 개별 파괴 연출이 즉시 번거로워진다.
var _bricks: Dictionary = {}   # index -> MeshInstance3D
var _ball: MeshInstance3D
var _paddle: MeshInstance3D

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
static func brick_height(kind: int) -> float:
	match kind:
		2: return 0.6
		3: return 0.8
		_: return 0.4

func brick_count() -> int:
	return _bricks.size()

func build(grid: BrickGrid) -> void:
	for key in _bricks.keys():
		(_bricks[key] as Node).free()
	_bricks.clear()
	refresh_bricks(grid)
	if _ball == null:
		_ball = _make_ball()
		add_child(_ball)
	if _paddle == null:
		_paddle = _make_paddle()
		add_child(_paddle)

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
				continue
			if _bricks.has(i):
				continue
			var m := _make_brick(col, row, kind)
			_bricks[i] = m
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
	# 줄마다 색을 바꿔 어느 줄까지 닿았는지 눈으로 세게 한다.
	mat.albedo_color = Color.from_hsv(fmod(float(row) * 0.13, 1.0), 0.55, 0.9)
	m.material_override = mat
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
```

- [ ] **Step 4: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_board_view: OK`

`brick_count()` 는 `_bricks` 딕셔너리 크기를 본다. 해제를 `free()` 로 하는 것은 테스트의 BoardView 가 SceneTree 에 붙지 않은 채 만들어지기 때문이다 — `queue_free()` 는 트리 밖에서 처리 시점이 불확실하다.

- [ ] **Step 5: 커밋**

```bash
git add scripts/board_view.gd tests/test_board_view.gd
git commit -m "feat: 판 좌표 변환과 블럭·공·패들 렌더링"
```

---

### Task 9: 씬 조립과 터치 입력

**Files:**
- Create: `scenes/game.tscn`
- Create: `scripts/game.gd`
- Create: `tests/test_game_smoke.gd`

**Interfaces:**
- Consumes: `PlayField`, `BoardView`, `Tuning`
- Produces: `game.gd` — `Node3D`. 자식으로 `Camera3D`, 기울어진 `Board`(`BoardView`), `CanvasLayer` HUD

- [ ] **Step 1: 실패하는 스모크 테스트 작성**

`tests/test_game_smoke.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_scene_loads_and_runs()
	_test_screen_point_maps_to_board()
	print("test_game_smoke: OK")
	quit()

func _test_scene_loads_and_runs() -> void:
	var packed := load("res://scenes/game.tscn") as PackedScene
	assert(packed != null, "게임 씬을 못 불러왔다")
	var g := packed.instantiate()
	root.add_child(g)
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
	var vp := root.get_viewport().get_visible_rect().size
	var center := g.screen_to_board(vp * 0.5)
	var right := g.screen_to_board(Vector2(vp.x * 0.9, vp.y * 0.5))
	assert(right.x > center.x, "화면 오른쪽이 판 오른쪽으로 안 간다: %f vs %f" % [right.x, center.x])
	var low := g.screen_to_board(Vector2(vp.x * 0.5, vp.y * 0.9))
	var high := g.screen_to_board(Vector2(vp.x * 0.5, vp.y * 0.1))
	assert(high.y > low.y, "화면 위쪽이 판 안쪽(v 큰 쪽)으로 안 간다: %f vs %f" % [high.y, low.y])
	g.free()
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `res://scenes/game.tscn` 을 못 불러온다

- [ ] **Step 3: `scripts/game.gd` 구현**

```gdscript
extends Node3D

@onready var board: BoardView = $Board
@onready var camera: Camera3D = $Camera3D
@onready var lives_label: Label = $HUD/Lives
@onready var version_label: Label = $HUD/Version

var field: PlayField
# 손가락이 닿기 전에는 패들을 제자리에 둔다.
var _target: Vector2

func _ready() -> void:
	field = PlayField.new()
	_target = field.paddle.pos
	board.build(field.grid)
	# 빌드마다 배포 워크플로가 덮어쓴다. 폰에서 지금 보고 있는 것이
	# 어느 브랜치의 어느 커밋인지 눈으로 구별하려는 것이다.
	version_label.text = str(ProjectSettings.get_setting("application/config/version"))
	_update_hud()

func _physics_process(delta: float) -> void:
	step_once(delta)

# 테스트에서도 부를 수 있게 프레임 루프와 분리한다.
func step_once(delta: float) -> void:
	var r := field.step(_target, delta)
	board.sync(field)
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()
	if bool(r["cleared"]):
		field.grid.fill_all(1)
		board.build(field.grid)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_target = screen_to_board((event as InputEventScreenDrag).position)
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_target = screen_to_board(t.position)
		else:
			# 손가락을 뗄 때 붙어 있던 공을 그때의 스윙 속도로 쏜다.
			field.launch(field.paddle.vel)

# 판이 기울어져 있으므로 화면 좌표를 그대로 쓸 수 없다. 카메라 광선을
# 판 평면과 교차시킨다. 손가락 밑에 패들이 정확히 오는 감각이 전부
# 여기서 나오므로 근사하지 않는다.
func screen_to_board(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var plane := Plane(board.global_transform.basis.y.normalized(), board.global_position)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return _target
	var local := board.to_local(hit as Vector3)
	return Vector2(local.x, -local.z)

func _update_hud() -> void:
	lives_label.text = "목숨 %d" % field.lives
```

- [ ] **Step 4: `scenes/game.tscn` 구성**

Godot 에디터에서 만들거나 아래 구조를 그대로 쓴다.

- `Game` (`Node3D`, `scripts/game.gd`)
  - `Board` (`Node3D`, `scripts/board_view.gd`) — `rotation.x = 25°` (`BOARD_TILT_DEG` 와 같은 값)
  - `Camera3D` — `position = (0, 9.5, 12)`, `rotation.x = -32°`, `fov = 40`
  - `DirectionalLight3D` — `rotation = (-50°, -30°, 0)`, `shadow_enabled = true`
  - `HUD` (`CanvasLayer`)
    - `Lives` (`Label`) — 상단 좌측 여백
    - `Version` (`Label`) — 하단 좌측 여백, 작은 글씨

카메라 값은 판 10 × 16 전체가 720 × 1280 세이프 에어리어 안에 들어오도록 에디터에서 눈으로 맞춘 뒤 확정한다. HUD 는 판 **위아래 여백**에만 둔다 — 판 옆 세로 패널은 폰에서 플레이 영역을 가린다.

블럭은 그림자를 드리우지 않게 한다(`_make_brick` 에서 `m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`). 웹 빌드와 폰 성능 때문이다. 이 한 줄을 `scripts/board_view.gd` 의 `_make_brick` 에 추가한다.

- [ ] **Step 5: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_game_smoke: OK`, `전체 통과`

- [ ] **Step 6: 눈으로 확인**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . `
마우스로 드래그해 패들이 손가락을 따라오는지, 앞으로 밀면 공이 가속하는지, 좌우로 휘두르면 방향이 바뀌는지 본다. `emulate_touch_from_mouse` 덕에 마우스가 터치로 들어온다.

- [ ] **Step 7: 커밋**

```bash
git add scenes/game.tscn scripts/game.gd scripts/board_view.gd tests/test_game_smoke.gd
git commit -m "feat: 씬 조립과 터치 입력 (화면 좌표를 판 평면으로 역투영)"
```

---

### Task 10: 속도 트레일과 HUD

**Files:**
- Create: `scripts/ball_trail.gd`
- Create: `tests/test_ball_trail.gd`
- Modify: `scripts/game.gd`, `scenes/game.tscn`

**Interfaces:**
- Consumes: `Tuning`
- Produces:
  - `BallTrail.sample_count(speed: float) -> int` (static)
  - `BallTrail.color_for(speed: float) -> Color` (static)
  - `trail.push(p: Vector2, speed: float) -> void`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_ball_trail.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	_test_length_scales_with_speed()
	_test_color_scales_with_speed()
	_test_history_is_bounded()
	print("test_ball_trail: OK")
	quit()

# 플레이어가 알아야 할 유일한 숨은 상태는 "지금 공이 센가 약한가"다.
# 트레일이 그 상태를 그대로 비춰야 한다.
func _test_length_scales_with_speed() -> void:
	var slow := BallTrail.sample_count(Tuning.v_min())
	var fast := BallTrail.sample_count(Tuning.V_MAX)
	assert(fast > slow, "빠른 공의 트레일이 더 길어야 한다: %d vs %d" % [fast, slow])
	assert(slow >= 2, "가장 느릴 때도 선이 보여야 한다: %d" % slow)

func _test_color_scales_with_speed() -> void:
	var slow := BallTrail.color_for(Tuning.v_min())
	var fast := BallTrail.color_for(Tuning.V_MAX)
	assert(fast.get_luminance() > slow.get_luminance(),
		"빠른 공이 더 밝아야 한다: %f vs %f" % [fast.get_luminance(), slow.get_luminance()])

func _test_history_is_bounded() -> void:
	var t := BallTrail.new()
	for i in 500:
		t.push(Vector2(float(i) * 0.01, 5.0), Tuning.V_MAX)
	assert(t.point_count() <= BallTrail.sample_count(Tuning.V_MAX),
		"이력이 무한히 쌓인다: %d" % t.point_count())
	t.free()
```

- [ ] **Step 2: 실패 확인**

Run: `./run_tests.sh`
Expected: FAIL — `Identifier "BallTrail" not declared`

- [ ] **Step 3: 최소 구현**

`scripts/ball_trail.gd`:

```gdscript
class_name BallTrail
extends MeshInstance3D

const MIN_SAMPLES := 3
const MAX_SAMPLES := 14
const WIDTH := 0.16

var _points: Array[Vector2] = []
var _mesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()

func _init() -> void:
	mesh = _mesh
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 이게 없으면 정점 색이 무시돼 트레일이 단색으로 나온다 —
	# 속도를 색으로 보여주는 것 자체가 죽는다.
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _t(speed: float) -> float:
	return clampf((speed - Tuning.v_min()) / (Tuning.V_MAX - Tuning.v_min()), 0.0, 1.0)

static func sample_count(speed: float) -> int:
	return int(round(lerpf(float(MIN_SAMPLES), float(MAX_SAMPLES), _t(speed))))

static func color_for(speed: float) -> Color:
	return Color(0.35, 0.45, 0.7).lerp(Color(1.0, 0.9, 0.5), _t(speed))

func point_count() -> int:
	return _points.size()

func push(p: Vector2, speed: float) -> void:
	_points.push_back(p)
	while _points.size() > sample_count(speed):
		_points.pop_front()
	_redraw(color_for(speed))

# 판 로컬 평면 위에 리본 하나를 그린다. 판이 기울어져 있으므로 리본도
# 같이 기울어 보인다 — 별도 처리가 필요 없다.
func _redraw(tint: Color) -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var p: Vector2 = _points[i]
		var fade := float(i) / float(_points.size() - 1)
		var dir: Vector2
		if i == 0:
			dir = (_points[1] - p).normalized()
		else:
			dir = (p - _points[i - 1]).normalized()
		var side := Vector2(-dir.y, dir.x) * WIDTH * 0.5 * fade
		var c := tint
		c.a = fade
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(BoardView.board_to_local(p + side, Tuning.BALL_RADIUS * 0.5))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(BoardView.board_to_local(p - side, Tuning.BALL_RADIUS * 0.5))
	_mesh.surface_end()
```

- [ ] **Step 4: `scripts/game.gd` 에 연결**

`_ready()` 끝에:

```gdscript
	_trail = BallTrail.new()
	board.add_child(_trail)
```

필드 선언에 `var _trail: BallTrail` 를 추가하고, `step_once` 의 `board.sync(field)` 다음 줄에:

```gdscript
	if not field.attached:
		_trail.push(field.ball_pos, field.ball_vel.length())
```

- [ ] **Step 5: 통과 확인**

Run: `./run_tests.sh`
Expected: `test_ball_trail: OK`, `전체 통과`

- [ ] **Step 6: 눈으로 확인**

에디터에서 실행해 세게 친 직후 트레일이 길고 밝아지고, 몇 번 가만히 받아 감쇠하면 짧고 흐려지는지 본다. 이게 안 보이면 플레이어가 언제 밀어야 하는지 알 방법이 없다.

- [ ] **Step 7: 커밋**

```bash
git add scripts/ball_trail.gd tests/test_ball_trail.gd scripts/game.gd scenes/game.tscn
git commit -m "feat: 공 속도를 길이와 색으로 보여주는 트레일"
```

---

### Task 11: 웹 export 와 Pages 배포

**Files:**
- Create: `export_presets.cfg`
- Create: `.github/workflows/deploy.yml`
- Create: `assets/icon.png`

**Interfaces:**
- Consumes: 전체 프로젝트
- Produces: 어느 브랜치를 밀어도 테스트를 돌린 뒤 Pages 에 배포하는 워크플로

- [ ] **Step 1: blockbox 설정 가져와 이름 바꾸기**

```bash
mkdir -p .github/workflows assets
cp ~/games/blockbox/export_presets.cfg ./export_presets.cfg
cp ~/games/blockbox/.github/workflows/*.yml ./.github/workflows/deploy.yml
cp ~/games/blockbox/assets/icon.png ./assets/icon.png
sed -i '' 's/blockbox/3dblockbreaker/g' .github/workflows/deploy.yml
grep -n '3dblockbreaker' .github/workflows/deploy.yml
```

`export_presets.cfg` 의 export path 와 프리셋 이름이 `Web` 인지 확인한다. 워크플로가 `--export-release "Web"` 을 부른다.

아이콘은 임시로 blockbox 것을 쓴다. 1단계의 목적은 손맛 확인이지 브랜딩이 아니다.

- [ ] **Step 2: 워크플로가 참조하는 이름 확인**

`deploy.yml` 안에서 확인할 것:
- `BASENAME=3dblockbreaker-...` 로 바뀌었는지
- `<meta name="apple-mobile-web-app-title" content="3dblockbreaker">`, `<title>` 이 바뀌었는지
- `index.html` 은 빌드 이름을 담지 않고 `version.txt` 를 읽어 iframe 으로 띄우는 구조가 그대로인지 (`grep -q 'version.txt'`, `! grep -q "$BASENAME"` 검사가 살아 있어야 한다)

이 구조를 바꾸면 폰 홈 화면에 추가한 아이콘이 다음 배포에서 404 가 된다.

- [ ] **Step 3: 로컬 export 스모크**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/local.html
test -s build/web/local.wasm && echo "export ok"
```

Expected: `export ok`. 실패하면 웹 export 템플릿이 없는 것이다 — 에디터의 Manage Export Templates 에서 4.7.2 를 받는다.

- [ ] **Step 4: 커밋하고 밀어서 배포 확인**

```bash
git add export_presets.cfg .github/workflows/deploy.yml assets/icon.png
git commit -m "chore: 웹 export 와 GitHub Pages 배포 워크플로"
```

푸시 후 Actions 에서 `Run tests` 단계가 통과하고 배포가 끝나는지 본다. 저장소 Settings > Pages 의 Source 를 GitHub Actions 로 두어야 한다.

- [ ] **Step 5: 폰에서 열어 1단계 판정**

배포된 주소를 폰에서 열고 실제로 친다. 확인할 다섯 가지는 스펙 11절에 있다:

1. `PADDLE_RESTITUTION` 0.80 / `PADDLE_SPEED_TRANSFER` 0.60 — 감쇠와 가속의 비율
2. `PADDLE_MAX_SPEED_V` 22 — 밀기 제한이 답답한지 헐거운지
3. `PADDLE_MAX_TILT_DEG` 30 + `CONTACT_ANGLE_MAX_DEG` 20 — 조준 폭
4. `GRAVITY` 12 / `V_MIN` — 왕복 리듬
5. 판 10 × 16, 블럭 10열 × 6줄 — 비율

값을 고칠 때는 `scripts/tuning.gd` 만 고치고 `./run_tests.sh` 를 돌린다. Task 2 의 사거리 계약 테스트가 조합이 깨지는 것을 잡아 준다.

---

## 1단계 범위 밖 (2단계)

아래는 이 계획에 없다. 스펙에는 있지만 1단계의 판정에 필요 없다.

- 아이템 7종 전부 (E / C / L / S / D / B / P) 와 드랍 규칙 — 드랍 확률과 생성 규칙은 사용자가 따로 정하기로 한 항목이다
- 단단 블럭(내구 3)과 불괴 블럭. `BoardView.brick_height` 는 종류별 높이를 이미 알지만 `BrickGrid` 는 내구를 세지 않는다
- 텍스트 그리드 파일로 스테이지 레이아웃 정의. 1단계는 `fill_all(1)` 한 판
- 스테이지 진행, 점수, 최고점 저장
- 파편, 카메라 셰이크, 사운드
