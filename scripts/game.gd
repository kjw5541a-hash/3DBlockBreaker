extends Node3D

@onready var board: BoardView = $Board
@onready var camera: Camera3D = $Camera3D
@onready var lives_label: Label = $HUD/Lives
@onready var version_label: Label = $HUD/Version
@onready var stall_label: Label = $HUD/Stall

var field: PlayField
# 손가락이 닿기 전에는 패들을 제자리에 둔다.
var _target: Vector2
var _trail: BallTrail
# 마지막으로 화면에 찍은 교착 카운터. 값이 그대로면 문자열을 새로 안 만든다 —
# 120Hz 로 도는 루프에서 매 프레임 문자열을 만들 이유가 없다.
var _shown_stall: int = -1

func _ready() -> void:
	field = PlayField.new()
	_target = field.paddle.pos
	board.build(field.grid)
	# 빌드마다 배포 워크플로가 덮어쓴다. 폰에서 지금 보고 있는 것이
	# 어느 브랜치의 어느 커밋인지 눈으로 구별하려는 것이다.
	version_label.text = str(ProjectSettings.get_setting("application/config/version"))
	_update_hud()
	_sync_stall()
	_trail = BallTrail.new()
	board.add_child(_trail)

func _physics_process(delta: float) -> void:
	step_once(delta)

# 테스트에서도 부를 수 있게 프레임 루프와 분리한다.
func step_once(delta: float) -> void:
	var r := field.step(_target, delta)
	board.sync(field)
	_sync_stall()
	# 클리어와 전멸이 같은 프레임에 함께 나올 수 있다. step() 의 서브스텝 루프가
	# out["lost"] 를 세우고 빠져나온 뒤에도 remaining() 검사는 그대로 돌기 때문이다.
	# 그러면 reset_run() 이 0 판으로 되돌린 직후 next_stage() 가 1 판으로 올려 버린다 —
	# 되돌린 프레임의 클리어는 이미 사라진 판의 것이므로 무시한다.
	var restarted := false
	if bool(r["lost"]):
		_trail.reset()
		# 마지막 목숨을 잃으면 처음부터 다시 — 아직 게임오버 화면이 없다.
		if field.lives <= 0:
			field.reset_run()
			board.build(field.grid)
			restarted = true
	if not field.attached:
		_trail.push(field.ball_pos, field.ball_vel.length())
	if bool(r["cleared"]) and not restarted:
		field.next_stage()
		_trail.reset()
		board.build(field.grid)
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()

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

# 남은 점이 곧 남은 예산이다. 이 카운터는 안 보이면 억울하다 — 단단 블럭을 두 번
# 치고 불괴 블럭을 한 번 스치면 경고 없이 목숨이 날아가는데, 그게 규칙 때문인지
# 사고인지 화면에 아무 단서가 없다.
static func stall_text(hits: int) -> String:
	var used := clampi(hits, 0, Tuning.STALL_PADDLE_HITS)
	var left := Tuning.STALL_PADDLE_HITS - used
	return "●".repeat(left) + "○".repeat(used)

# 값이 바뀐 프레임에만 문자열을 만든다. 나머지 프레임은 int 비교 하나로 끝난다.
func _sync_stall() -> void:
	if field.paddle_hits_since_brick == _shown_stall:
		return
	_shown_stall = field.paddle_hits_since_brick
	stall_label.text = stall_text(_shown_stall)
