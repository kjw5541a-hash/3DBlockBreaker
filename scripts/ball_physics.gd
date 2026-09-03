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
