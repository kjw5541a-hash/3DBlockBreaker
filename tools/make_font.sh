#!/usr/bin/env bash
# 한글 폰트 subset 을 다시 만든다. Godot 기본 폰트에는 한글 글리프가 없어
# HUD 가 전부 두부(□)로 나온다. 전체 Noto Sans KR 은 10MB, 한글 음절 전체만
# 남겨도 2.3MB 라 웹 빌드에 싣기엔 무겁다. 화면에 실제로 나오는 글자만 남기면
# 13KB 다.
#
# 그래서 UI 에 한글을 새로 쓰면 이 스크립트를 다시 돌려야 한다.
# tests/test_font.gd 가 빠진 글자를 잡는다 — 그 테스트가 터지면 여기로 온 것이다.
#
# fonttools 는 이 저장소의 의존성이 아니라 이 스크립트만의 도구다. 결과물인
# .ttf 를 커밋하므로 빌드에는 필요 없다.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_URL="https://github.com/google/fonts/raw/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf"
OUT="assets/NotoSansKR-subset.ttf"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet fonttools brotli

curl -sSL -o "$WORK/src.ttf" "$SRC_URL"
# 가변 폰트다. 굵기 하나로 고정하지 않으면 6MB 를 그대로 끌고 간다.
"$WORK/venv/bin/fonttools" varLib.instancer "$WORK/src.ttf" wght=400 -o "$WORK/400.ttf" >/dev/null

# 씬의 text = "..." 과 스크립트의 .text = "..." 이 화면에 나오는 글자의 전부다.
# 주석은 안 훑는다 — 이 저장소는 주석이 전부 한글이라 훑으면 subset 이 폰트
# 전체가 된다.
CHARS="$(python3 - <<'PY'
import glob, io, re
txt = ""
for f in glob.glob("scenes/*.tscn"):
	for m in re.finditer(r'^text = "(.*)"$', io.open(f, encoding="utf-8").read(), re.M):
		txt += m.group(1)
for f in glob.glob("scripts/*.gd"):
	for m in re.finditer(r'\.text = "(.*?)"', io.open(f, encoding="utf-8").read()):
		txt += m.group(1)
print("".join(sorted({c for c in txt if ord(c) > 0x7f})))
PY
)"
echo "남길 한글: $CHARS"

# ASCII 는 통째로 남긴다 — 빌드 버전 라벨이 날짜와 커밋 해시를 실어 오므로
# 어떤 영숫자가 올지 미리 알 수 없다.
"$WORK/venv/bin/pyftsubset" "$WORK/400.ttf" --output-file="$OUT" \
	--text="$CHARS" --unicodes="U+0020-007E" --no-hinting
ls -l "$OUT"
