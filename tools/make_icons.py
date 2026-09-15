#!/usr/bin/env python3
"""assets/icon.png(512x512) 하나에서 안드로이드·스토어용 아이콘을 만든다.

돌리는 법:  python3 -m venv /tmp/v && /tmp/v/bin/pip install Pillow
            /tmp/v/bin/python tools/make_icons.py
Pillow 는 이 스크립트만의 도구다. 결과물을 커밋하므로 빌드에는 필요 없다.

적응형 아이콘(adaptive icon)은 108dp 캔버스에서 바깥 18dp 를 런처가 잘라낼 수
있다. 원본 아트워크는 벽돌 왼쪽 끝이 8.8%, 패들 아래쪽이 11% 지점이라 그대로
꽉 채우면 원형 런처에서 잘린다. 그래서 전경은 안전구역 안으로 줄이고, 배경은
원본 카드와 같은 톤의 세로 그라데이션으로 깐다 — 줄인 카드의 가장자리가 배경에
녹아들어 잘려 나간 티가 안 난다. 단색 어두운 배경도 해 봤지만 두꺼운 검은 테가
생겨 카드가 작아 보인다.
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets", "icon.png")
# 원본 카드의 위/아래 색. 여기서 벗어나면 줄인 카드의 테두리가 드러난다.
TOP, BOTTOM = (236, 237, 240), (212, 213, 219)
# 적응형 아이콘 캔버스 432px 중 전경이 차지할 크기. 72dp(288px) 안전 사각형보다
# 조금 크지만, 넘치는 부분은 카드의 부드러운 그림자뿐이라 잘려도 티가 안 난다.
FOREGROUND_PX = 300


def gradient(size):
    g = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y),
            tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
    return g.resize((size, size), Image.BILINEAR)


def composed(art, canvas_px, art_px):
    out = gradient(canvas_px)
    a = art.resize((art_px, art_px), Image.LANCZOS)
    off = (canvas_px - art_px) // 2
    out.alpha_composite(a, (off, off))
    return out


def main():
    art = Image.open(SRC).convert("RGBA")
    assert art.size == (512, 512), "원본 아이콘은 512x512 여야 한다: %s" % (art.size,)
    out = lambda *p: os.path.join(ROOT, *p)

    composed(art, 432, FOREGROUND_PX).save(out("assets", "android", "icon_foreground_432.png"))
    # 전경이 이미 배경을 깔고 있다. 배경 층은 전경이 투명한 데가 없어 안 보이지만,
    # Godot 이 요구하므로 같은 그라데이션으로 채워 둔다 — 런처가 두 층을 시차
    # 이동시킬 때(패럴랙스) 가장자리가 비지 않게 하려는 것이다.
    gradient(432).save(out("assets", "android", "icon_background_432.png"))
    # 적응형을 안 쓰는 옛 런처가 집는 그림.
    composed(art, 192, 192).convert("RGB").save(out("assets", "android", "icon_192.png"))

    # Play 스토어 아이콘: 512x512, 알파 금지, 모서리는 스토어가 직접 굴린다.
    # 여기는 마스크 안전구역이 없으므로 원본 크기 그대로 두고 투명한 모서리만 채운다.
    composed(art, 512, 512).convert("RGB").save(out("store", "play_icon_512.png"))
    print("만들었다: 적응형 전경/배경, 런처 192, 스토어 512")


if __name__ == "__main__":
    main()
