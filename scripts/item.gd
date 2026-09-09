class_name Item
extends RefCounted

# 아이템 종류. BrickGrid 의 "칸 값이 곧 종류" 규약을 그대로 쓴다 — 0 은
# "아이템 없음"이다.
#
# 지금은 P, E, S, C 네 종. 나머지 셋(L, B, D)은 4b 나머지 청크에서 붙는다.
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

static func color(kind: int) -> Color:
	if kind == P:
		return Color(0.45, 0.95, 0.55)
	if kind == E:
		return Color(0.95, 0.75, 0.3)
	if kind == S:
		return Color(0.4, 0.6, 0.95)
	if kind == C:
		return Color(0.9, 0.4, 0.85)
	return Color(0.7, 0.7, 0.7)
