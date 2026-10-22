"""FSR-linked range study. Synthetic PCM and control values, no hardware claim."""
from pathlib import Path
import math
from PIL import Image, ImageDraw
from render_scope_concepts import FONT, rgb, label, dot, led_view, font

OUT = Path(__file__).resolve().parents[1] / "design" / "led_scope_20261022"
FONT.update({
    "+": ["000", "010", "111", "010", "000"],
    "-": ["000", "000", "111", "000", "000"],
    "%": ["101", "001", "010", "100", "101"],
})


def panel(fsr_percent, linked=True):
    # Three anchors of a proposed power-of-two range policy. FSR gain is a
    # control percentage; PCM peak is separately normalized to signed FS.
    half_range = fsr_percent if linked else 100
    gain = 100 // half_range
    source_peak = 0.80
    output_peak = source_peak * fsr_percent / 100
    im = Image.new("RGB", (64, 64), (0, 0, 0))
    d = ImageDraw.Draw(im)
    label(im, f"FSR{fsr_percent}%", 2, 2, (10, 16, 14))
    label(im, f"X{gain}", 51, 2, (0, 25, 15))
    # Signed vertical labels always name the original PCM percentage, even
    # when the displayed waveform has been enlarged. Equal heights therefore
    # no longer silently imply equal signal amplitudes.
    for text, top in ((f"+{half_range}", 10), ("0", 25), (f"-{half_range}", 39)):
        label(im, text, 15 - (len(text) * 4 - 1), top, (9, 12, 12))
    for x in (18, 38, 58):
        for y in (12, 20, 27, 35, 42):
            dot(im, x, y, (0, 2, 2))
    for x in range(18, 61, 3):
        dot(im, x, 27, (0, 3, 2))
    points = []
    for x in range(18, 61):
        phase = 2 * math.pi * 2.15 * (x - 18) / 42
        value = output_peak * math.sin(phase)
        y = round(27 - 15 * value / (half_range / 100))
        points.append((x, y))
    d.line(points, fill=rgb((0, 31, 19)), width=1)
    d.line((18, 45, 60, 45), fill=rgb((0, 4, 3)))
    for x in (18, 38, 58):
        d.line((x, 44, x, 46), fill=rgb((3, 11, 8)))
    label(im, "MS", 2, 48, (7, 10, 10))
    label(im, "0", 17, 48, (9, 12, 12))
    label(im, "5", 37, 48, (9, 12, 12))
    label(im, "10", 55, 48, (9, 12, 12))
    peak_percent = round(output_peak * 100)
    label(im, f"PK{peak_percent}%", 2, 57, (12, 16, 15))
    # The meter ALWAYS spans 0..100% signed digital full scale. It has no FSR
    # compensation and can be compared across all ranges and all input sources.
    width = 37
    for i in range(width):
        if (i + 1) / width <= output_peak:
            color = (0, 26, 7) if i < width * .75 else (28, 16, 0)
            d.line((24 + i, 58, 24 + i, 60), fill=rgb(color))
    for x in (24, 33, 42, 51, 60):
        dot(im, x, 62, (5, 8, 8))
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", (1536, 812), "#0a1117")
    d = ImageDraw.Draw(canvas)
    d.text((36, 22), "FSR 联动量程，真实电平保持固定刻度", font=font(32), fill="#e3eee9")
    d.text((36, 77), "同一触摸音源 / 原始峰值 80% / 仅改变 FSR 音量 / 64×64 设计示意", font=font(20), fill="#90a8b5")
    for i, (percent, title) in enumerate(((100, "轻压 · 音量 100%"), (50, "中间状态 · 音量 50%"), (25, "重压 · 音量 25%"))):
        left = 36 + 500 * i
        im = panel(percent)
        im.save(OUT / f"FSR_{percent}_pixels_64.png")
        im.resize((640, 640), Image.Resampling.NEAREST).save(OUT / f"FSR_{percent}_pixels_enlarged.png")
        d.text((left, 132), title, font=font(25), fill="#c1d8cd")
        canvas.paste(led_view(im, 7), (left, 180))
        d.text((left, 646), f"显示 ×{100 // percent}   /   纵轴 ±{percent}%", font=font(22), fill="#b6d3c4")
        d.text((left, 683), f"真实峰值 {round(.8 * percent)}%   /   电平条同步变短", font=font(20), fill="#a1b5c0")
    d.text((36, 741), "波形可同高，纵轴数值与 PK 电平条明确区分大小。百分比表示数字幅度，不是扬声器响度。", font=font(20), fill="#bdcdd5")
    d.text((36, 781), "概念稿，尚未接入 RTL；最终混音超量程时需优先扩大范围。时间刻度位置将在实现时匹配采样窗口。", font=font(16), fill="#738d9d")
    canvas.save(OUT / "FSR_range_comparison.png")
    print(OUT / "FSR_range_comparison.png")


if __name__ == "__main__":
    main()
