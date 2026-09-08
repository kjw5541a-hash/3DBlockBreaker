class_name Item
extends RefCounted

# 아이템 종류. BrickGrid 의 "칸 값이 곧 종류" 규약을 그대로 쓴다 — 0 은
# "아이템 없음"이다.
#
# 지금은 P 한 종뿐이다. 나머지 여섯(E, S, C, L, B, D)은 4b 에서 붙는다.
# 상수만 미리 깔아 두지 않는 것은 쓰이지 않는 분기가 같이 늘어나기 때문이다.
const NONE := 0
# Player. 목숨 +1. 즉발이라 활성 슬롯을 차지하지 않는다.
const P := 1

static func color(kind: int) -> Color:
	if kind == P:
		return Color(0.45, 0.95, 0.55)
	return Color(0.7, 0.7, 0.7)
