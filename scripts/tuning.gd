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
# 최하단 블럭 줄에 닿는 속도. 리터럴로 박으면 위 값을 조정할 때 계약이
# 조용히 깨진다.
#
# 공 반지름과 패들 두께를 빼고 밴드 하단(0.4)과 블럭 하단(9.0)만 쓴 근사다.
# 실제로는 공 중심이 0.8 에서 출발해 9.40 까지 오르고 접촉면은 8.75 라
# 0.65 만큼 여유가 있다 — 계약은 "겨우"가 아니라 "확실히 닿는다"에 가깝다.
# 여유를 없애려면 두 항을 빼면 되지만, 하한이 낮아지면 최저속 랠리가
# 블럭에 못 닿아 갇힌다. 여유는 의도적으로 남긴다.
static func v_min() -> float:
	return sqrt(2.0 * GRAVITY * (BRICK_BOTTOM_V - PADDLE_BAND_MIN_V))
