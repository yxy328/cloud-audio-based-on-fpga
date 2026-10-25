"""Volume -> color-wheel ramp study, checked against the real RTL PPM frames."""
from pathlib import Path
import colorsys
from collections import Counter
from PIL import Image, ImageDraw
from render_scope_concepts import rgb, font, led_view

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "design" / "led_scope_20261022" / "hue_ramp"
BUILD = ROOT / "sim" / "build"

# Fixed saturation, full value, hue walking the lower half of the wheel.
SAT, VAL, H0, HSTEP, HMAX = 0.903, 1.0, 180.0, 30.0, 360.0
PICKS = ["#12b9ba", "#1258ba", "#1f12ba", "#8812ba", "#ba1297", "#ba1247", "#ba1812"]


def ramp_hue(n):
    return min(H0 + max(0, n - 2) * HSTEP, HMAX)


def hsv5(hue):
    r, g, b = colorsys.hsv_to_rgb((hue % 360.0) / 360.0, SAT, VAL)
    return tuple(round(v * 31) for v in (r, g, b))


def expected(bucket):
    return hsv5(ramp_hue(bucket))


OLD = {  # previous palette() constants, kept only to draw the before/after chips
    0: (8, 8, 8), 1: (0, 0, 24), 2: (0, 0, 31), 3: (8, 0, 31), 4: (16, 0, 31),
    5: (24, 0, 24), 6: (31, 0, 16), 7: (31, 0, 8), 8: (31, 0, 0),
}
FRAMES = [  # name, capture_peak bucket, PCM peak shown in the panel
    ("scope_weak128", 1, "128"),
    ("scope_fsr25", 2, "512"),
    ("scope_fsr50", 4, "1024"),
    ("scope_fsr100", 8, "2048"),
]


def strip(width, height):
    im = Image.new("RGB", (width, height))
    d = ImageDraw.Draw(im)
    for x in range(width):
        hue = H0 + (HMAX - H0) * x / (width - 1)
        c = tuple(round(v * 255) for v in colorsys.hsv_to_rgb((hue % 360) / 360, SAT, VAL))
        d.line((x, 0, x, height - 1), fill=c)
    return im


def dominant(path):
    im = Image.open(path).convert("RGB")
    sat = [(c, n) for c, n in Counter(im.getdata()).items() if max(c) - min(c) > 40]
    return im, (max(sat, key=lambda entry: entry[1])[0] if sat else None)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    W = 1512
    canvas = Image.new("RGB", (W, 1120), "#0b141b")
    d = ImageDraw.Draw(canvas)
    d.text((28, 20), "LED 波形颜色 · 已按音量沿色环改动（RTL 实测帧）", font=font(32), fill="#e5f0ef")
    d.text((28, 70), "色相 180°(青)→360°(红) 固定 S=0.903 / V=1.00；第 2 档起每档 +30°，第 1 档与第 2 档同为青。",
           font=font(20), fill="#9fb4c0")

    for i, hexv in enumerate(PICKS):
        x = 28 + i * 208
        d.rectangle((x, 112, x + 190, 150), fill=hexv)
        d.text((x + 4, 154), hexv, font=font(17), fill="#a8c2ce")

    canvas.paste(strip(W - 56, 46), (28, 190))
    d.text((28, 240), "连续色环（设计参考，面板只能出 32 级/通道）", font=font(17), fill="#8ea6b2")

    d.text((28, 288), "实际写进 palette() 的 8 档 RGB5（左→右 = capture_peak 1→8，≥8 钉在红）",
           font=font(19), fill="#cbded7")
    for n in range(1, 9):
        x = 28 + (n - 1) * 182
        c = expected(n)
        d.rectangle((x, 320, x + 174, 364), fill=rgb(c))
        d.text((x + 2, 370), f"{n} · RGB5 {c[0]},{c[1]},{c[2]} · {round(ramp_hue(n))}°",
               font=font(16), fill="#a8c2ce")
        d.text((x + 2, 392), f"旧 {OLD[n][0]},{OLD[n][1]},{OLD[n][2]}", font=font(15), fill="#6d8492")

    d.text((28, 428), "真实 RTL 帧（sim/build/*.ppm 由 tb_audio_scope 直接输出，未做任何后期换色）",
           font=font(24), fill="#cbded7")
    bad = []
    for i, (name, bucket, peak) in enumerate(FRAMES):
        im, color = dominant(BUILD / f"{name}.ppm")
        want = rgb(expected(bucket))
        if color != want:
            bad.append(f"{name}: RTL {color} != spec {want}")
        x0 = 28 + i * 372
        d.text((x0, 468), f"峰值 {peak} · 第 {bucket} 档 · {'一致' if color == want else '不一致'}",
               font=font(20), fill="#b6d3c4" if color == want else "#ff8f8f")
        canvas.paste(led_view(im, 5), (x0, 502))
        d.rectangle((x0, 830, x0 + 34, 856), fill=rgb(OLD[bucket]))
        d.text((x0 + 42, 832), "旧", font=font(18), fill="#a8c2ce")
        d.rectangle((x0 + 84, 830, x0 + 118, 856), fill=want)
        d.text((x0 + 126, 832), "新 = RTL 实测", font=font(18), fill="#a8c2ce")

    d.text((28, 886), "档位边界没动：1=128 2=512 4=1024 8=2048，safe_range / PK 百分比 / 电平条长度全部不变。",
           font=font(19), fill="#a1b5c0")
    d.text((28, 920), "静音仍是低亮白零线 (8,8,8)；底部 PK 电平条与波形同色，一起沿色环走。",
           font=font(19), fill="#a1b5c0")
    d.text((28, 954), "注意：正常演奏时 capture_peak 落在 2..8，所以青色只出现在最轻的 1~2 档，"
                      "第 1、2 档同色是低端钳位的结果。", font=font(19), fill="#a1b5c0")
    canvas.save(OUT / "hue_ramp_mapping.png")
    if bad:
        raise SystemExit("RTL palette does not match the spec:\n  " + "\n  ".join(bad))
    print("OK 4 RTL frames match the wheel spec ->", OUT / "hue_ramp_mapping.png")


if __name__ == "__main__":
    main()
