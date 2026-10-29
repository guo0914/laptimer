"""Generate the 1024x1024 app icon (and the asset catalog entry).

Matches scheme A: dark ink background, teal gradient ring, lap ticks.
"""

import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 2  # supersample factor
W = SIZE * SS

OUT = pathlib.Path(__file__).resolve().parent.parent / "LapTimer" / "Assets.xcassets" / "AppIcon.appiconset"

INK = (9, 12, 19)
TEAL_LIGHT = (125, 243, 223)
TEAL = (61, 217, 193)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def build() -> Image.Image:
    img = Image.new("RGB", (W, W), INK)
    d = ImageDraw.Draw(img)

    # 顶部冷光
    glow = Image.new("RGB", (W, W), INK)
    gd = ImageDraw.Draw(glow)
    cx, cy = W // 2, int(W * 0.28)
    for i in range(70, 0, -1):
        r = int(W * 0.62 * i / 70)
        a = int(28 * (1 - i / 70) ** 2)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(INK[0] + a, INK[1] + a * 3, INK[2] + a * 2))
    img = Image.blend(img, glow, 0.55)
    d = ImageDraw.Draw(img)

    # 环
    ring_r = int(W * 0.315)
    ring_w = int(W * 0.055)
    center = (W // 2, int(W * 0.47))
    bbox = [center[0] - ring_r, center[1] - ring_r, center[0] + ring_r, center[1] + ring_r]

    d.arc(bbox, start=-90, end=270, fill=(25, 32, 45), width=ring_w)

    # 渐变弧：逐段绘制，从亮 teal 到深 teal
    sweep = 250
    steps = 240
    for i in range(steps):
        t = i / steps
        angle_end = -90 + sweep * (i + 1.35) / steps
        angle_start = -90 + sweep * i / steps
        col = tuple(int(TEAL_LIGHT[k] + (TEAL[k] - TEAL_LIGHT[k]) * t) for k in range(3))
        d.arc(bbox, start=angle_start, end=angle_end, fill=col, width=ring_w)

    # 刻度
    tick_r_out = ring_r - ring_w - int(W * 0.012)
    tick_len = int(W * 0.018)
    for i in range(60):
        import math

        a = math.radians(i * 6 - 90)
        x0 = center[0] + (tick_r_out - tick_len) * math.cos(a)
        y0 = center[1] + (tick_r_out - tick_len) * math.sin(a)
        x1 = center[0] + tick_r_out * math.cos(a)
        y1 = center[1] + tick_r_out * math.sin(a)
        alpha = 150 if i % 5 == 0 else 60
        d.line([(x0, y0), (x1, y1)], fill=(alpha, alpha + 12, alpha + 20), width=int(W * 0.006))

    # 表针
    hand_len = int(ring_r * 0.62)
    d.line([center, (center[0] + int(hand_len * 0.75), center[1] - int(hand_len * 0.55))],
           fill=TEAL_LIGHT, width=int(W * 0.014))
    hub = int(W * 0.02)
    d.ellipse([center[0] - hub, center[1] - hub, center[0] + hub, center[1] + hub], fill=TEAL_LIGHT)

    # 底部两条「分段」短横，暗示 lap
    bar_y = int(W * 0.84)
    for i, wfrac in enumerate((0.30, 0.18, 0.10)):
        total = sum((0.30, 0.18, 0.10))
        gap = int(W * 0.022)
        bx = W // 2 - int(W * total / 2)
        widths = [int(W * 0.30), int(W * 0.18), int(W * 0.10)]
        offset = sum(widths[:i]) + gap * i
        x0 = bx + offset
        x1 = x0 + widths[i]
        col = TEAL_LIGHT if i == 0 else (70, 84, 104)
        d.rounded_rectangle([x0, bar_y, x1, bar_y + int(W * 0.016)],
                            radius=int(W * 0.008), fill=col)

    img = img.filter(ImageFilter.SMOOTH)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)

    # iOS 图标不应自带圆角，系统会裁；这里保持直角全出血
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon = build()
    icon.save(OUT / "AppIcon-1024.png", optimize=True)

    contents = {
        "images": [
            {"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", OUT / "AppIcon-1024.png")


if __name__ == "__main__":
    main()
