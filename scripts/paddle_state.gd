class_name PaddleState
extends RefCounted

var pos: Vector2
var prev_pos: Vector2
var vel: Vector2 = Vector2.ZERO
var tilt_deg: float = 0.0
var half_width: float = Tuning.PADDLE_HALF_WIDTH

var _vel_samples: Array[Vector2] = []
# 스프링 중인지, 그리고 그때의 진짜 세로 속도. 평활된 vel 과 달리 지연이
# 없다 — 발사 속도가 여기서 나오므로 한 프레임도 늦으면 안 된다.
var _springing: bool = false
var _spring_vel: float = 0.0

func _init(start_u: float = 0.0) -> void:
	pos = Vector2(start_u, Tuning.PADDLE_HOME_V)
	prev_pos = pos

func springing() -> bool:
	return _springing

# 손을 뗀 순간 부른다. 여기서 속도를 매기지 않는다 — 당긴 깊이가 곧
# 용수철이 늘어난 길이라, 파워는 아래 _spring_accel() 이 알아서 만든다.
func start_spring() -> void:
	_springing = true
	_spring_vel = 0.0
	# 평활 표본에는 손가락을 끌어내리던 아래 방향 속도가 들어 있다. 그대로
	# 두면 릴리즈 직후 한두 프레임 동안 평균이 파워를 깎거나 부호를 뒤집는데,
	# 공은 바로 그 프레임에 밀려 나간다 — 평균이 따라잡을 시간이 없다.
	_vel_samples.clear()

func cancel_spring() -> void:
	_springing = false
	_spring_vel = 0.0

# 훅의 법칙 + 감쇠. 스프링 중이 아니면 0 이다.
func _spring_accel() -> float:
	if not _springing:
		return 0.0
	return -Tuning.PADDLE_SPRING_FREQ * Tuning.PADDLE_SPRING_FREQ \
		* (pos.y - Tuning.PADDLE_HOME_V) \
		- 2.0 * Tuning.PADDLE_SPRING_DAMPING * Tuning.PADDLE_SPRING_FREQ * _spring_vel

# 패들에 얹힌 공이 떨어져 나가는 순간. 용수철이 중력보다 세게 아래로
# 잡아당기기 시작하면 패들이 공보다 빠르게 감속하므로, 공은 접촉을 잃고
# 그때의 패들 속도로 날아간다. 홈을 막 지난 지점이라 거의 최고 속도다.
func separating() -> bool:
	return _springing and _spring_accel() <= -Tuning.GRAVITY

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
	if _springing:
		# 스프링 중에는 세로 타깃을 무시한다 — 손가락은 아직 아래를 가리키고
		# 있고, 그쪽으로 추종하면 튕겨 오르지 못한다. 가로는 그대로 둔다.
		# 세미암시적 오일러. 공 물리와 같은 적분기를 쓴다.
		_spring_vel += _spring_accel() * dt
		pos.y = clampf(pos.y + _spring_vel * dt,
			Tuning.PADDLE_BAND_MIN_V, Tuning.PADDLE_BAND_MAX_V)
		if absf(pos.y - Tuning.PADDLE_HOME_V) < Tuning.PADDLE_SPRING_REST_POS \
				and absf(_spring_vel) < Tuning.PADDLE_SPRING_REST_VEL:
			pos.y = Tuning.PADDLE_HOME_V
			cancel_spring()
	else:
		pos.y += clampf(d.y, -Tuning.PADDLE_MAX_SPEED_V * dt, Tuning.PADDLE_MAX_SPEED_V * dt)
	_push_vel((pos - prev_pos) / dt)
	if _springing:
		# 세로만 평활을 건너뛴다. 발사 속도가 이 값이라 한 프레임 지연도
		# 파워를 깎는다. 가로는 여전히 손가락 지터를 타므로 평활을 남긴다.
		vel.y = _spring_vel
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

# 스윗스팟. 접촉점이 조준만 정하면 어디로 받든 손해가 없어 "잘 받는다"가
# 실력이 되지 못한다. 가운데로 정확히 받으면 반발이 온전하고, 가장자리로
# 스치면 깎인다. 패들 밖 값도 가장자리로 막는다 — 안 막으면 스쳐 맞을 때
# 반발이 음수가 되어 공이 패들 쪽으로 빨려 든다.
func restitution(ball_u: float) -> float:
	var offset := clampf(absf(ball_u - pos.x) / half_width, 0.0, 1.0)
	return lerpf(Tuning.PADDLE_RESTITUTION, Tuning.PADDLE_RESTITUTION_EDGE, offset)

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
