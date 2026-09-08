extends Node3D

@onready var board: BoardView = $Board
@onready var camera: Camera3D = $Camera3D
@onready var lives_label: Label = $HUD/Lives
@onready var version_label: Label = $HUD/Version
@onready var stage_label: Label = $HUD/Stage

var field: PlayField
# 손가락이 닿기 전에는 패들을 제자리에 둔다.
var _target: Vector2
var _trail: BallTrail

func _ready() -> void:
	field = PlayField.new()
	_target = field.paddle.pos
	board.build(field.grid)
	# 빌드마다 배포 워크플로가 덮어쓴다. 폰에서 지금 보고 있는 것이
	# 어느 브랜치의 어느 커밋인지 눈으로 구별하려는 것이다.
	version_label.text = str(ProjectSettings.get_setting("application/config/version"))
	_update_hud()
	_trail = BallTrail.new()
	board.add_child(_trail)

func _physics_process(delta: float) -> void:
	step_once(delta)

# 테스트에서도 부를 수 있게 프레임 루프와 분리한다.
func step_once(delta: float) -> void:
	var r := field.step(_target, delta)
	board.sync(field)
	# step() 은 구조적으로 lost 와 cleared 를 한 dict 에 함께 담을 수 있다 — 서브스텝
	# 루프가 out["lost"] 를 세우고 빠져나와도 remaining() 검사는 그대로 돌기 때문이다.
	# 그러면 reset_run() 이 0 판으로 되돌린 직후 next_stage() 가 1 판으로 올려 버린다.
	#
	# 지금 물리로는 그 조합이 안 나온다 — 공이 한 프레임에 블럭 띠에서 데드존까지 갈
	# 만큼 빠르지 않다. 그래도 가드를 두는 것은 아이템 D(공 분열)가
	# "목숨은 마지막 공이 사라질 때 깎인다"로 바꾸는 순간 열리기 때문이다 — 그때 이 버그는
	# 생성기 결함으로 오진되기 딱 좋다. 되돌린 프레임의 클리어는 이미 사라진 판의 것이다.
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
	# stage_index 는 0 기반이다. 플레이어에게 "0 판"을 보여줄 이유는 없다.
	stage_label.text = "판 %d" % (field.stage_index + 1)
