class_name Item
extends RefCounted

# 아이템 종류. BrickGrid 의 "칸 값이 곧 종류" 규약을 그대로 쓴다 — 0 은
# "아이템 없음"이다.
#
# B(워프 게이트)는 뺐다 — 캐치형 낙하 아이템이 아니라 공이 직접 통과해야
# 하는 별개 충돌 모델이라 이 아이템 세트의 전제(패들로 줍는다)와 안 맞는다.
# D(공 분열)는 공 표현 자체를 배열로 바꾸는 구조 변경이라 별도 설계에서 다룬다.
# 상수만 미리 깔아 두지 않는 것은 쓰이지 않는 분기가 같이 늘어나기 때문이다.
const NONE := 0
# Player. 목숨 +1. 즉발이라 활성 슬롯을 차지하지 않는다.
const P := 1
# Enlarge. 패들 반폭 확대. 활성 슬롯을 쓴다.
const E := 2
# Slow. 공 물리 시간을 늦춘다. 활성 슬롯을 쓴다.
const S := 3
# Catch. 패들에 닿으면 튕기지 않고 붙는다. 활성 슬롯을 쓴다.
const C := 4
# Laser. 패들에서 위로 쏜다. 활성 슬롯을 쓴다.
const L := 5

static func color(kind: int) -> Color:
	if kind == P:
		return Color(0.45, 0.95, 0.55)
	if kind == E:
		return Color(0.95, 0.75, 0.3)
	if kind == S:
		return Color(0.4, 0.6, 0.95)
	if kind == C:
		return Color(0.9, 0.4, 0.85)
	if kind == L:
		return Color(0.95, 0.25, 0.25)
	return Color(0.7, 0.7, 0.7)

# 색만으로는 종류를 못 외운다. 큐브 위에 이 글자를 띄운다.
static func letter(kind: int) -> String:
	if kind == P:
		return "P"
	if kind == E:
		return "E"
	if kind == S:
		return "S"
	if kind == C:
		return "C"
	if kind == L:
		return "L"
	return "?"
