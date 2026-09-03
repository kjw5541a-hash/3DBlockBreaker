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
