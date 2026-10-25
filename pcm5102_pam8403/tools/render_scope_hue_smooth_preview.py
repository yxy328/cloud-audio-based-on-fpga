"""Concept preview of a 33-step integer hue ramp; not yet wired into RTL."""
from pathlib import Path
from PIL import Image, ImageDraw
from render_scope_concepts import rgb, font, led_view

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "design" / "led_scope_20261023"
BUILD = ROOT / "sim" / "build"

# p = window |peak| in PCM/64 units, clamped to the 2048-count loud reference.
P_MAX = 32


def ramp(p):
    q = min(p, P_MAX) * 6
    if q >= 192:
        return (31, 3, 3)
    u, d = q & 63, ((q & 63) * 7) >> 4
    return [(3, 31 - d, 31), (3 + d, 3, 31), (31, 3, 31 - d)][q >> 6]


CURRENT = [(3, 31, 31), (3, 31, 31), (3, 17, 31), (3, 3, 31), (17, 3, 31),
           (31, 3, 31), (31, 3, 17), (31, 3, 3)]


def recolored(name, color):
    im = Image.open(BUILD / f"{name}.ppm").convert("RGB")
    src = im.load()
    for y in range(64):
        for x in range(64):
            r, g, b = src[x, y]
            if max(r, g, b) - min(r, g, b) > 40:
                src[x, y] = rgb(color)
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", (1512, 1000), "#0b141b")
    d = ImageDraw.Draw(canvas)
    d.text((28, 18), "色环丝滑化 · 8 档 → 33 档（纯整数公式，无查表无 DSP）", font=font(32), fill="#e5f0ef")
    d.text((28, 68), "峰值按 PCM/64 累加并钳在 32（=2048 响度参考），色相 = 180° + p×5.625°，每档只差 5.6°。",
           font=font(20), fill="#9fb4c0")

    d.text((28, 118), "现在：capture_peak 只有 1/256 分辨率，物理上最多 8 档", font=font(20), fill="#cbded7")
    for i, c in enumerate(CURRENT):
        d.rectangle((28 + i * 183, 150, 28 + i * 183 + 175, 190), fill=rgb(c))

    d.text((28, 212), "改后：换成 1/64 峰值累加，33 档连续走完半圈", font=font(20), fill="#cbded7")
    for p in range(33):
        x = 28 + p * 44
        d.rectangle((x, 244, x + 43, 284), fill=rgb(ramp(p)))
        if p % 4 == 0:
            d.text((x + 1, 288), "p32=红" if p == 32 else f"p{p}", font=font(14), fill="#7c95a2")

    d.text((28, 330), "同一帧只有一种颜色：整帧在每次 publish（约 10.5ms）时换色，"
                      "所以「丝滑」体现在渐强过程中颜色一档档挪，而不是一根线里有渐变",
           font=font(19), fill="#9fb4c0")

    d.text((28, 372), "渐强过程（真实 RTL 帧，仅按 33 档公式重新着色）", font=font(24), fill="#cbded7")
    steps = [("scope_weak128", 2, "p2 · 峰值 128"), ("scope_fsr25", 8, "p8 · 峰值 512"),
             ("scope_fsr50", 16, "p16 · 峰值 1024"), ("scope_fsr100", 32, "p32 · 峰值 2048"),
             ("scope_overrange", 32, "p32 · 峰值满幅（钳位）")]
    for i, (name, p, tag) in enumerate(steps):
        x0 = 28 + i * 297
        d.text((x0, 412), tag, font=font(19), fill="#b6d3c4")
        canvas.paste(led_view(recolored(name, ramp(p)), 4), (x0, 444))
        d.rectangle((x0, 712, x0 + 148, 738), fill=rgb(ramp(p)))
        c = ramp(p)
        d.text((x0 + 6, 742), f"RGB5 {c[0]},{c[1]},{c[2]}", font=font(16), fill="#a8c2ce")

    d.text((28, 786), "整数公式：q=min(p,32)×6；扇区=q÷64；u=q mod 64；d=(u×7)÷16；",
           font=font(19), fill="#b6d3c4")
    d.text((28, 818), "  扇区0 (3,31-d,31)  扇区1 (3+d,3,31)  扇区2 (31,3,31-d)  q=192 时钉 (31,3,3)",
           font=font(19), fill="#b6d3c4")
    d.text((28, 858), "与真 HSV 逐档比对：33 档全部通道误差 ≤1 LSB，色相严格单调，不经过绿和黄。",
           font=font(19), fill="#a1b5c0")
    d.text((28, 892), "代价：audio_visualizer 里加一个 6 位饱和峰值累加器（约 12 CLS）+ 色环公式（约 20 CLS）。",
           font=font(19), fill="#a1b5c0")
    d.text((28, 926), "概念稿，尚未接入 RTL。33 档是硬上限：样本量化在 PCM/64，再细就要动波形几何。",
           font=font(19), fill="#738d9d")
    canvas.save(OUT / "hue_smooth_33_preview.png")
    print(OUT / "hue_smooth_33_preview.png")


if __name__ == "__main__":
    main()
