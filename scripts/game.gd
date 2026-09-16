extends Node3D

@onready var board: BoardView = $Board
@onready var camera: Camera3D = $Camera3D
@onready var lives_label: Label = $HUD/Lives
@onready var version_label: Label = $HUD/Version
@onready var stage_label: Label = $HUD/Stage
@onready var title_screen: Control = $HUD/TitleScreen
@onready var fire_flash: ColorRect = $HUD/FireFlash
@onready var pause_button: Label = $HUD/PauseButton
@onready var pause_screen: ColorRect = $HUD/PauseScreen
@onready var game_over_screen: ColorRect = $HUD/GameOverScreen
@onready var game_over_stage: Label = $HUD/GameOverScreen/Stage
@onready var continue_button: Label = $HUD/GameOverScreen/ContinueButton
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
# 타이틀 -> 진행 -> (일시정지) <-> 진행 -> 게임오버 -> 진행. 물리가 도는 상태는
# PLAYING 하나뿐이라 "지금 돌려도 되나"를 한 군데서만 묻는다.
enum State { TITLE, PLAYING, PAUSED, OVER }
var _state: State = State.TITLE

# Admob 싱글턴은 실제 안드로이드 기기에서만 존재한다. 데스크톱/웹/헤드리스
# 테스트에서 노드를 만들면 _ready() 안에서 바로 에러를 낸다 — 그래서 이 노드
# 자체를 안드로이드에서만 만든다.
var admob: Admob = null

func _ready() -> void:
	if OS.get_name() == "Android":
		admob = Admob.new()
		admob.is_real = true
		admob.android_real_application_id = "ca-app-pub-6471092831122102~3630800345"
		admob.android_real_rewarded_id = "ca-app-pub-6471092831122102/8691555332"
		add_child(admob)
		admob.initialization_completed.connect(func(_status): admob.load_rewarded_ad())
		admob.rewarded_ad_loaded.connect(func(_ad_info, _resp): continue_button.visible = true)
		admob.rewarded_ad_user_earned_reward.connect(_on_rewarded_earned)
		admob.initialize()
	field = PlayField.new()
	_target = field.paddle.pos
	board.build(field.grid)
	# 빌드마다 배포 워크플로가 덮어쓴다. 폰에서 지금 보고 있는 것이
	# 어느 브랜치의 어느 커밋인지 눈으로 구별하려는 것이다.
	version_label.text = str(ProjectSettings.get_setting("application/config/version"))
	_update_hud()
	_trail = BallTrail.new()
	board.add_child(_trail)
	# 아이템·레이저·트레일은 전부 처음 그려질 때 셰이더 컴파일과 글리프
	# 래스터화를 치른다. 그 순간이 아이템이 떨어지거나 공을 막 쏜 직후라
	# 가장 끊기면 안 되는 때와 겹친다. 타이틀 화면에서 미리 그려 둔다.
	board.warm_up()
	_trail.push(field.ball_pos, 0.0)
	_trail.push(field.ball_pos + Vector2(0.0, 0.02), 0.0)

func _physics_process(delta: float) -> void:
	if _state != State.PLAYING:
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
	if bool(r["ignited"]):
		_flash_fire()
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
	# 그러면 게임오버로 멈춰 세운 판을 같은 프레임의 next_stage() 가 넘겨 버려,
	# 화면은 게임오버인데 뒤에서는 다음 판이 깔린다.
	#
	# 지금 물리로는 그 조합이 안 나온다 — 공이 한 프레임에 블럭 띠에서 데드존까지 갈
	# 만큼 빠르지 않다. 그래도 가드를 두는 것은 아이템 D(공 분열)가
	# "목숨은 마지막 공이 사라질 때 깎인다"로 바꾸는 순간 열리기 때문이다 — 그때 이 버그는
	# 생성기 결함으로 오진되기 딱 좋다. 끝난 판의 클리어는 이미 사라진 판의 것이다.
	if bool(r["lost"]):
		_trail.reset()
		board.play_paddle_break()
		_play_sfx(_sfx_life_lost)
		if field.lives <= 0:
			_game_over()
	# 낙하 중인 공은 트레일을 안 남긴다 — 발사한 공의 궤적이 아니라서다.
	if not field.attached and not field.dropping:
		_trail.push(field.ball_pos, field.ball_vel.length(), field.burning)
	if bool(r["cleared"]) and _state != State.OVER:
		_play_sfx(_sfx_stage_clear)
		field.next_stage()
		_trail.reset()
		board.build(field.grid)
	if bool(r["lost"]) or bool(r["cleared"]):
		_update_hud()

# 정확히 받은 순간의 보상. 알파만 올렸다 내리는 CanvasLayer 사각형이라
# 3D 쪽 비용이 없다. 점화는 몇 프레임 만에 지나가는 사건이라 공 색만으로는
# 놓치기 쉬운데, 화면이 한 번 번쩍여야 손가락과 연결된다.
#
# Node.create_tween() 대신 SceneTree 의 것을 쓴다 — board_view 와 같은 이유로,
# 트리 편입 전에 부르면 진행이 안 돼 테스트가 결과를 확인할 수 없다.
func _flash_fire() -> void:
	fire_flash.color = Color(Tuning.FIRE_COLOR, Tuning.FIRE_FLASH_ALPHA)
	var tw := (Engine.get_main_loop() as SceneTree).create_tween()
	tw.tween_property(fire_flash, "color:a", 0.0, Tuning.FIRE_FLASH_SEC)

# 테스트 하네스는 root.add_child() 를 _initialize() 안에서 부르는데, 그
# 시점엔 노드가 아직 트리에 편입되지 않는다 — AudioStreamPlayer.play() 는
# 트리 밖에서 부르면 에러를 낸다. 실제 게임에선 항상 트리 안이라 이 가드가
# 동작을 바꾸지 않는다.
func _play_sfx(player: AudioStreamPlayer) -> void:
	if is_inside_tree():
		player.play()

func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	# 일시정지 버튼은 Button 이 아니라 라벨이고, 판정은 여기서 사각형으로 한다.
	# 터치 하나가 GUI 와 게임 조작 두 갈래로 나뉘면 어느 쪽이 먼저 먹었는지에
	# 따라 패들이 튄다. 누를 때만 토글하고 뒤따라 오는 뗌은 버린다 — 안 그러면
	# 재개시킨 그 손가락의 뗌이 스프링 발사로 읽혀 공이 제멋대로 나간다.
	if touch != null and (_state == State.PLAYING or _state == State.PAUSED) \
			and pause_button.get_global_rect().has_point(touch.position):
		if touch.pressed:
			_toggle_pause()
		return
	match _state:
		State.TITLE:
			if touch != null and touch.pressed:
				_start()
		State.OVER:
			if touch != null and touch.pressed:
				if continue_button.visible and continue_button.get_global_rect().has_point(touch.position):
					admob.show_rewarded_ad()
				else:
					_restart()
		State.PLAYING:
			_play_input(event)

func _start() -> void:
	_state = State.PLAYING
	title_screen.visible = false
	# 워밍업 잔재를 치운다. 트레일 점을 남기면 첫 발사 궤적이
	# 공이 있지도 않았던 자리와 한 줄로 이어진다.
	board.end_warm_up()
	_trail.reset()

# 안드로이드 뒤로 가기. quit_on_go_back 을 꺼 뒀으므로 여기서 안 받으면 아무
# 일도 안 일어난다.
func _notification(what: int) -> void:
	# 뒤로 가기는 토글이고 포커스 상실은 한 방향이다 — 전화를 받고 돌아왔는데
	# 공이 이미 날아가고 있으면 손이 못 따라간다. 돌아올 때 저절로 풀지 않는
	# 이유도 같다. 둘 다 멈출 것이 있을 때만 쓴다 — 타이틀이나 게임오버 위에
	# 일시정지 화면이 겹쳐 뜨면 어느 터치가 먹는지 알 수 없어진다.
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _state == State.PLAYING or _state == State.PAUSED:
				_toggle_pause()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _state == State.PLAYING:
				_toggle_pause()

func _toggle_pause() -> void:
	_state = State.PLAYING if _state == State.PAUSED else State.PAUSED
	pause_screen.visible = _state == State.PAUSED

# 마지막 목숨을 잃었다. 말없이 처음부터 다시 돌리면 플레이어는 자기가 진
# 것인지 화면이 튄 것인지 구별할 수 없다. 멈춰 세우고 어디까지 갔는지 보여준다.
func _game_over() -> void:
	_state = State.OVER
	game_over_stage.text = "판 %d 까지" % (field.stage_index + 1)
	game_over_screen.visible = true
	# 광고는 한 번 보여주면 소모된다(remove_rewarded_ads_after_displayed) — 게임오버
	# 화면이 뜰 때마다 다음 걸 새로 불러온다. 버튼은 로드가 끝나야(rewarded_ad_loaded)
	# 다시 보인다.
	if admob != null:
		continue_button.visible = false
		admob.load_rewarded_ad()

# 이어하기 광고를 다 보면 판을 그대로 두고 목숨만 하나 준다 — 처음부터 다시
# 시작하는 것과 달리 여기까지 깬 블럭은 안 살아난다.
func _on_rewarded_earned(_ad_info, _reward_data) -> void:
	if _state != State.OVER:
		return
	continue_button.visible = false
	game_over_screen.visible = false
	field.lives = 1
	_trail.reset()
	_target = field.paddle.pos
	_update_hud()
	_state = State.PLAYING

func _restart() -> void:
	continue_button.visible = false
	game_over_screen.visible = false
	field.reset_run()
	board.build(field.grid)
	_trail.reset()
	# 마지막에 손가락이 있던 자리를 그대로 두면 새 공이 시작하자마자 패들이
	# 그리로 미끄러진다.
	_target = field.paddle.pos
	_update_hud()
	_state = State.PLAYING

func _play_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_target = screen_to_board((event as InputEventScreenDrag).position)
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			# 다시 잡으면 올라가던 패들을 손가락이 도로 가져간다.
			field.paddle.cancel_spring()
			_target = screen_to_board(t.position)
		else:
			# 손을 뗀다 = 스프링. 손가락이 아직 아래를 가리키고 있으므로
			# 타깃도 홈으로 올려 둔다 — 안 그러면 스프링이 끝나자마자
			# 패들이 도로 손가락 자리로 내려간다.
			_target.y = Tuning.PADDLE_HOME_V
			field.paddle.start_spring()
			if field.attached:
				# 발사 속도는 여기서 안 준다. 올라오는 패들이 실제로 쳐서 만든다.
				field.release_ball()
			else:
				# 공이 이미 날아가는 중이면 같은 탭 제스처가 레이저를 쏜다
				# (L 이 없거나 쿨다운 중이면 fire_laser() 안에서 조용히 무시된다).
				field.fire_laser()

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
