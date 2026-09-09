class_name Tuning
extends RefCounted

# --- 판 기하. 물리는 전부 이 (u, v) 좌표에서 돈다 ---
# 판 폭이 화면 종횡비를 정한다. 25° 기울기 + 카메라 부각이 v 축을 약 0.55
# 배로 압축하므로, 세로 16 은 화면에서 약 8.7 로 읽힌다. 폭이 10 이면 판이
# 가로로 더 넓게 보여 720x1280 세로 화면의 절반밖에 못 채우고, 남는 위아래
# 여백 탓에 패들이 화면 한참 위에 떠 있는 것처럼 보인다. 6.4 로 좁히면
# 세로를 약 75% 채운다.
const BOARD_HALF_WIDTH := 3.2
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
const BALL_RADIUS := 0.18
const V_MAX := 34.0
# 상한이 처음부터 34 면 시작 몇 초 만에 손댈 수 없는 공이 나온다. 잘 맞은
# 공의 상한을 경과 시간에 비례해 올려 초반을 느리게 만든다. V_MAX_START
# 로도 상단 벽에는 닿는다(정점 17.07 > 16.0) — 초반부터 판 전체를 쓴다.
const V_MAX_START := 20.0
const V_MAX_RAMP_SEC := 90.0
# 공이 수평에 가까워지면 좌우 벽만 오가며 영영 안 내려온다.
const MIN_ANGLE_DEG := 15.0

# --- 패들 ---
# 이 게임에서 에너지를 잃는 유일한 곳. 벽과 블럭은 1.0 이다. 손실원이
# 하나뿐이라 "왜 느려졌나"의 답이 언제나 "그냥 받았으니까"가 된다.
const PADDLE_RESTITUTION := 0.80
const PADDLE_SPEED_TRANSFER := 0.60
const PADDLE_HALF_WIDTH := 0.64
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

# --- 아이템 ---
# 중력이 아니라 등속으로 내려온다. 공이 이미 가속하는 물체라 아이템까지
# 가속하면 "지금 뛰어가면 잡을 수 있나"를 순간 판단할 수 없다.
const ITEM_FALL_SPEED := 4.0
# 획득 판정 상자의 반폭. 패들 반폭(0.64)보다 한참 작아야 아이템 가장자리를
# 스쳤는데 먹히는 일이 없다.
const ITEM_HALF_SIZE := 0.26
# Enlarge 배율. 패들 반폭에 곱한다.
const ITEM_ENLARGE_MULT := 1.5
# Slow 가 공 물리에 매기는 시간 배율. elapsed(속도 램프)는 대상이 아니다 —
# 늦추면 난이도 진행까지 함께 얼어 이중으로 느려진다.
const ITEM_SLOW_TIMESCALE := 0.7

# 탭 발사 속도. 숫자가 아니라 계약이다: 패들 밴드 아래끝에서 출발해 최하단
# 블럭 줄에 닿는 속도. 리터럴로 박으면 위 값을 조정할 때 계약이 조용히
# 깨진다. 트레일 색·길이의 아래쪽 기준점이기도 하다.
#
# 이 값은 더 이상 속도의 하한이 아니다. 패들 반사에 하한을 두면 가만히
# 받아도 도달 높이가 안 줄어 공이 영원히 같은 높이로 돌아온다. 지금은
# 반발계수만 작동한다 — 안 치고 버티면 공이 패들 위로 가라앉을 뿐이고,
# 그동안 elapsed 는 계속 흘러 속도 램프만 오른다. 뭉개는 것 자체가 손해다.
#
# 공 반지름과 패들 두께를 뺀 근사다. 실제로는 공 중심이 더 위에서 출발해
# 최하단 줄 접촉면보다 조금 더 오른다 — 여유는 의도적으로 남긴다. 여유를
# 없애면 탭 발사가 블럭에 못 닿는다.
# 공이 살아서 굴러간 시간만 센다. 붙어 있는 동안은 안 센다 — 발사를 미루는
# 것으로 난이도를 낮출 수 있으면 규칙이 아니라 요령이 된다.
static func v_max_at(elapsed: float) -> float:
	return lerpf(V_MAX_START, V_MAX, clampf(elapsed / V_MAX_RAMP_SEC, 0.0, 1.0))

static func v_min() -> float:
	return sqrt(2.0 * GRAVITY * (BRICK_BOTTOM_V - PADDLE_BAND_MIN_V))
