extends Node3D

@onready var board: BoardView = $Board
@onready var camera: Camera3D = $Camera3D
@onready var lives_label: Label = $HUD/Lives
@onready var version_label: Label = $HUD/Version
@onready var stage_label: Label = $HUD/Stage
@onready var title_screen: Control = $HUD/TitleScreen
@onready var _sfx_paddle_hit: AudioStreamPlayer = $Sfx/PaddleHit
@onready var _sfx_wall_hit: AudioStreamPlayer = $Sfx/WallHit
@onready var _sfx_brick_break: AudioStreamPlayer = $Sfx/BrickBreak
@onready var _sfx_stage_clear: AudioStreamPlayer = $Sfx/StageClear
@onready var _sfx_life_lost: AudioStreamPlayer = $Sfx/LifeLost
@onready var _sfx_item_get: AudioStreamPlayer = $Sfx/ItemGet

var field: PlayField
# 손가락이 닿기 전에는 패들을 제자리에 둔다.
var _target: Vector2
var _trail: BallTrail
# 타이틀 화면을 넘기기 전에는 물리를 안 돌린다.
var _started: bool = false

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
	if not _started:
		return
	step_once(delta)

# 테스트에서도 부를 수 있게 프레임 루프와 분리한다.
func step_once(delta: float) -> void:
	var r := field.step(_target, delta)
	for b in (r["broken"] as Array):
		var bd := b as Dictionary
		board.play_brick_break(int(bd["col"]), int(bd["row"]), int(bd["kind"]))
	if (r["broken"] as Array).size() > 0:
		_play_sfx(_sfx_brick_break)
	if bool(r["paddle_hit"]):
		_play_sfx(_sfx_paddle_hit)
	if bool(r["wall_hit"]):
		_play_sfx(_sfx_wall_hit)
	# P 는 목숨을 늘리므로 HUD 를 여기서 갱신한다 — 아래 lost/cleared 갱신은
	# 아이템을 먹기만 한 프레임에는 안 걸린다.
	if (r["items_taken"] as Array).size() > 0:
		_play_sfx(_sfx_item_get)
		_update_hud()
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
		board.play_paddle_break()
		_play_sfx(_sfx_life_lost)
		# 마지막 목숨을 잃으면 처음부터 다시 — 아직 게임오버 화면이 없다.
		if field.lives <= 0:
			field.reset_run()
			board.build(field.grid)
			restarted = true
	# 낙하 중인 공은 트레일을 안 남긴다 — 발사한 공의 궤적이 아니라서다.
	if not field.attached and not field.dropping:
		_trail.push(field.ball_pos, field.ball_vel.length())
	if bool(r["cleared"]) and not restarted:
		_play_sfx(_sfx_stage_clear)
		field.next_stage()
		_trail.reset()
		board.build(field.grid)
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()

# 테스트 하네스는 root.add_child() 를 _initialize() 안에서 부르는데, 그
# 시점엔 노드가 아직 트리에 편입되지 않는다 — AudioStreamPlayer.play() 는
# 트리 밖에서 부르면 에러를 낸다. 실제 게임에선 항상 트리 안이라 이 가드가
# 동작을 바꾸지 않는다.
func _play_sfx(player: AudioStreamPlayer) -> void:
	if is_inside_tree():
		player.play()

func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			_started = true
			title_screen.visible = false
		return
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
