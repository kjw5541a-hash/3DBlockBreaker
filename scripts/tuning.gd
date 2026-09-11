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
# 손을 뗐을 때 돌아가 쉬는 자리. 밴드 한가운데라 아래로 당길 여유와 위로
# 튕겨 넘어갈 여유가 같다 — 한쪽에 붙여 두면 그쪽 오버슈트가 벽에 막힌다.
const PADDLE_HOME_V := (PADDLE_BAND_MIN_V + PADDLE_BAND_MAX_V) * 0.5

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
# 스윗스팟. 위 값은 패들 한가운데로 정확히 받았을 때고, 중심에서 멀어질수록
# 여기까지 선형으로 깎인다. 가운데 값을 1.0 위로 올리면 받을 때마다 에너지가
# 늘어 "손실원은 패들뿐"이라는 전제가 무너지므로, 정확도는 보상이 아니라
# 손실을 안 보는 것으로 표현한다.
const PADDLE_RESTITUTION_EDGE := 0.45
const PADDLE_SPEED_TRANSFER := 0.60
# 불타는 공이 붙는 판정창. 위 반발계수와 같은 정규화 오프셋을 쓴다 —
# 0.25 면 그 지점 반발계수가 0.71 이라 "잘 받았다" 구간과 겹친다. 가운데로
# 받는다는 하나의 실력이 두 보상을 준다.
#
# half_width 로 정규화하므로 Enlarge 를 먹으면 창도 1.5 배가 된다. 받기
# 쉬워지는 아이템이 불도 내기 쉬워지는 것이라 성격이 맞다.
const PADDLE_SWEET_SPOT := 0.25
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

# --- 스프링 복귀 ---
# 손가락으로 홈 아래로 끌어내렸다 놓으면 감쇠 조화진동자로 돌아온다:
#   a = -ω²·(y - HOME) - 2ζω·v
# 패들에 얹힌 공은 같이 가속하다가 홈을 조금 지나서 떨어져 나가므로,
# 홈을 지날 때의 속도가 곧 발사 속도가 된다.
#
# ω 는 파워 노브다. 최고 속도가 당긴 깊이에 비례해 오르는데, 그 값이
# V_MAX_START 를 넘으면 안 된다 — 넘으면 공이 v_max 에 잘려 자기를 밀어낸
# 패들보다 느려지고, 패들이 공을 추월해 메시를 뚫고 지나간다. 최대 깊이
# 1.3 에 ζ=0.3 이면 22.0 에서 약 19.7 이 나온다.
#
# ζ 는 잔진동 노브다. 0.3 이면 홈 위로 0.48 만큼 한 번 시원하게 넘어갔다가
# 두어 번 만에 가라앉는다. 더 낮추면 파워는 오르지만 패들이 몇 초씩 떨린다.
const PADDLE_SPRING_FREQ := 22.0
const PADDLE_SPRING_DAMPING := 0.3
# 홈에서 이만큼 안쪽으로 들어오고 속도도 이만큼 줄면 스냅하고 끝낸다.
# 감쇠 진동은 수학적으로는 영원히 안 멈춘다.
const PADDLE_SPRING_REST_POS := 0.01
const PADDLE_SPRING_REST_VEL := 0.1

# --- 불타는 공 ---
# 점화 순간의 화면 번쩍임. HUD 의 ColorRect 알파가 이 값에서 0 으로 내려간다.
# 길면 번쩍임이 아니라 화면이 밝아진 것으로 읽혀 블럭이 안 보인다.
const FIRE_FLASH_SEC := 0.15
const FIRE_FLASH_ALPHA := 0.45
const FIRE_COLOR := Color(1.0, 0.55, 0.15)

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

# --- Laser (아이템 L) ---
const LASER_SPEED := 20.0
# 연타로 화면을 레이저로 도배하는 것을 막는다.
const LASER_COOLDOWN := 0.25
# 충돌 판정 반경. 얇은 볼트라 공(0.18)보다 훨씬 작다.
const LASER_HALF_SIZE := 0.05

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
