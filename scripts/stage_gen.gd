class_name StageGen
extends RefCounted

# 판 번호 하나로 배치가 완전히 정해진다. 시드가 판 번호라 3판은 어느 기기에서
# 언제 시작해도 같은 3판이다 — 테스트가 가능해지고 플레이어가 판을 기억한다.
#
# 난이도는 여기서만 만든다. 물리 상수는 레버가 아니다 — 이 파일은 Tuning 을
# 읽기만 하고 절대 쓰지 않는다. 판이 빨라지는 것은 오직 Tuning.v_max_at()
# 전역 램프 때문이고, 여기가 하는 일은 배치뿐이다.
#
# index 는 0 기반이다. 설계 문서의 "판 N" 은 index N-1 이다.

# 곡선의 마디. 설계 §1 의 표를 그대로 옮긴 것이다.
const RAMP_A_END := 2    # 판 3 — 여기까지 밀도만
const RAMP_B_END := 6    # 판 7 — 여기까지 밀도 + 경도
const RAMP_C_END := 13   # 판 14 — 여기서 모든 레버가 상한

const DENSITY_START := 0.55
const DENSITY_MID := 0.70
const DENSITY_MAX := 0.90

const HARD_MID := 0.20
const HARD_MAX := 0.35

# 상한을 두는 이유는 판이 끝나야 하기 때문이다. 상한이 없으면 언젠가 반드시
# 클리어 불가능한 판이 나온다. 10 열짜리 줄을 다 막으려면 10 개가 필요하므로
# 이 값이 8 인 한 어떤 줄도 통째로 봉인되지 않는다.
const INDESTRUCTIBLE_MAX := 8

const GAP_START := 3
const GAP_MIN := 1

# 확률이 아니라 개수다. 판마다 정확히 이만큼 떨어지므로 아이템이 한 번도
# 안 나오는 운 나쁜 판이 없다. 난이도 곡선을 안 타는 것은 아이템이 난이도
# 레버가 아니라 보상이기 때문이다.
const ITEM_COUNT := 3

static func stage(index: int) -> BrickGrid:
	var g := BrickGrid.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = index
	var d := density(index)
	var hard := hard_ratio(index)
	var gap := max_gap(index)
	for row in Tuning.BRICK_ROWS:
		_fill_row(g, rng, row, d, hard, gap)
	_place_indestructible(g, rng, indestructible_count(index))
	_place_items(g, rng, ITEM_COUNT)
	return g

# 레버 A. 판 1–3 에서 55%→70%, 그 뒤 판 14 까지 90% 로 간다.
static func density(index: int) -> float:
	if index <= RAMP_A_END:
		return lerpf(DENSITY_START, DENSITY_MID, float(index) / float(RAMP_A_END))
	return lerpf(DENSITY_MID, DENSITY_MAX, _ramp(index, RAMP_A_END, RAMP_C_END))

# 레버 B 앞쪽. 단단 블럭은 판 4 부터 등장한다.
static func hard_ratio(index: int) -> float:
	if index <= RAMP_A_END:
		return 0.0
	if index <= RAMP_B_END:
		return lerpf(0.0, HARD_MID, _ramp(index, RAMP_A_END, RAMP_B_END))
	return lerpf(HARD_MID, HARD_MAX, _ramp(index, RAMP_B_END, RAMP_C_END))

# 레버 B 뒤쪽. 불괴 블럭은 판 8 부터. 짝수로 맞추는 것은 좌우 대칭으로 쌍을
# 놓기 때문이다 — 홀수면 마지막 하나가 짝을 못 찾아 대칭이 깨진다.
static func indestructible_count(index: int) -> int:
	if index <= RAMP_B_END:
		return 0
	var n := int(round(lerpf(0.0, float(INDESTRUCTIBLE_MAX),
		_ramp(index, RAMP_B_END, RAMP_C_END))))
	return n - (n % 2)

# 레버 D. 연속 빈칸의 최대 폭. 판 8 부터 3칸에서 1칸으로 좁아진다.
static func max_gap(index: int) -> int:
	if index <= RAMP_B_END:
		return GAP_START
	return int(round(lerpf(float(GAP_START), float(GAP_MIN),
		_ramp(index, RAMP_B_END, RAMP_C_END))))

static func _ramp(index: int, from_index: int, to_index: int) -> float:
	return clampf(float(index - from_index) / float(to_index - from_index), 0.0, 1.0)

# 절반만 만들고 거울로 접는다.
#
# 안쪽 열부터 바깥으로 훑는 이유는 빈칸 길이 때문이다. 가운데를 가로지르는
# 빈칸 구간은 왼쪽 절반에서 한 칸 비울 때마다 오른쪽 거울짝도 같이 비어
# 실제로는 두 칸씩 길어진다. 그 구간이 끊기기 전까지 weight 가 2 인 이유다.
# 한 번 막히고 나면 왼쪽의 빈칸 구간과 오른쪽의 빈칸 구간이 따로 놀므로
# 그 뒤로는 한 칸에 1 이다. 바깥에서 안으로 세면 이 이음매를 놓쳐 판
# 한가운데에 상한의 두 배짜리 구멍이 뚫린다.
static func _fill_row(g: BrickGrid, rng: RandomNumberGenerator, row: int,
		density_v: float, hard: float, gap: int) -> void:
	var half := Tuning.BRICK_COLS / 2
	var run := 0
	# 지금 세고 있는 빈칸 구간이 아직 판 가운데와 이어져 있는가.
	var spans_center := true
	for k in half:
		var col := half - 1 - k
		var weight := 2 if spans_center else 1
		var kind := 0
		# 빈칸 상한에 걸리면 밀도와 무관하게 채운다. 레버 D 가 레버 A 를
		# 이기는 쪽이 맞다 — 둘 다 어려워지는 방향이라 충돌이 아니다.
		if run + weight > gap or rng.randf() < density_v:
			kind = rng.randi_range(2, BrickGrid.MAX_HARD) if rng.randf() < hard else 1
			run = 0
			spans_center = false
		else:
			run += weight
		g.cells[BrickGrid.index(col, row)] = kind
		g.cells[BrickGrid.index(Tuning.BRICK_COLS - 1 - col, row)] = kind

# 쌍으로 놓는다. 최하단 줄(row 0)은 건너뛴다 — 최하단 줄이 통째로 막히면
# 위쪽 전부가 봉인된다. 줄 하나를 빼는 편이 "다 막혔는지" 검사하고 되돌리는
# 것보다 짧고, 되돌릴 일이 없으니 항상 끝난다.
static func _place_indestructible(g: BrickGrid, rng: RandomNumberGenerator,
		count: int) -> void:
	var half := Tuning.BRICK_COLS / 2
	var spots: Array[int] = []
	for row in range(1, Tuning.BRICK_ROWS):
		for col in half:
			if g.cells[BrickGrid.index(col, row)] > 0:
				spots.append(BrickGrid.index(col, row))
	_shuffle(spots, rng)
	for i in mini(count / 2, spots.size()):
		var idx := spots[i]
		var row := idx / Tuning.BRICK_COLS
		var col := idx % Tuning.BRICK_COLS
		g.cells[idx] = BrickGrid.INDESTRUCTIBLE
		g.cells[BrickGrid.index(Tuning.BRICK_COLS - 1 - col, row)] = BrickGrid.INDESTRUCTIBLE

# 깰 수 있는 칸 중에서만 고른다. 불괴 칸에 넣으면 영원히 안 떨어지므로
# 불괴를 다 놓은 뒤에 부른다.
#
# 불괴 블럭과 달리 좌우 대칭으로 놓지 않는다. 여기서는 개수 보장이 대칭보다
# 우선이다 — 쌍으로 놓으면 홀수 개를 정확히 맞출 수 없다. 아이템은 배치의
# 일부가 아니라 그 위에 얹힌 보상이라 대칭이 깨져도 판이 잡음으로 안 보인다.
# 종류별 가중치. 설계 문서(phase2)의 원 비중(P5 E22 S20 C18 L15)을 그대로
# 옮겼다 — B 는 아이템 세트에서 뺐고, D 는 별도 설계에서 합류한다.
# C(Catch)는 놓을 때 발사 속도가 안 붙는 버그가 있어 일단 스폰에서 뺐다 —
# _apply_item/step() 의 캐치 로직 자체는 그대로 둬서 고치면 바로 되살아난다.
const _ITEM_WEIGHTS := {Item.P: 5, Item.E: 22, Item.S: 20, Item.L: 15}

static func _place_items(g: BrickGrid, rng: RandomNumberGenerator, count: int) -> void:
	var spots: Array[int] = []
	for i in g.cells.size():
		if g.cells[i] > 0:
			spots.append(i)
	_shuffle(spots, rng)
	for i in mini(count, spots.size()):
		g.item_cells[spots[i]] = _pick_kind(rng)

static func _pick_kind(rng: RandomNumberGenerator) -> int:
	var total := 0
	for w in _ITEM_WEIGHTS.values():
		total += w
	var roll := rng.randi_range(1, total)
	for kind in _ITEM_WEIGHTS:
		roll -= int(_ITEM_WEIGHTS[kind])
		if roll <= 0:
			return kind
	return Item.P

# Array.shuffle() 은 전역 RNG 를 쓴다 — 시드가 안 먹어 판이 매번 달라진다.
# 시드 붙은 rng 로 직접 섞는다.
static func _shuffle(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := arr[i]
		arr[i] = arr[j]
		arr[j] = t
