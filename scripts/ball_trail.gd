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

# 불타는 동안은 속도계 노릇을 잠깐 그만둔다. 속도는 리본 길이로도 읽히지만
# 불은 몇 초짜리 상태라, 지금 블럭을 뚫는 중인지가 더 급한 정보다.
static func color_for(speed: float, burning: bool = false) -> Color:
	if burning:
		return Tuning.FIRE_COLOR
	return Color(0.35, 0.45, 0.7).lerp(Color(1.0, 0.9, 0.5), _t(speed))

func point_count() -> int:
	return _points.size()

# 목숨을 잃으면 이력을 버린다. 안 버리면 죽은 자리의 리본이 다음 발사까지
# 화면에 남고, 발사 순간 옛 점과 새 점이 한 줄로 이어져 버린다.
func reset() -> void:
	_points.clear()
	_mesh.clear_surfaces()

func push(p: Vector2, speed: float, burning: bool = false) -> void:
	_points.push_back(p)
	while _points.size() > sample_count(speed):
		_points.pop_front()
	_redraw(color_for(speed, burning))

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
