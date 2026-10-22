"""Pixel-exact 64x64 LED design studies; these are concepts, not FPGA captures."""
from pathlib import Path
import math
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "design" / "led_scope_20261022"
OUT.mkdir(parents=True, exist_ok=True)

# Every graphic inside a panel uses integer coordinates and RGB5 values.
FONT = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["110", "001", "010", "100", "111"],
    "3": ["110", "001", "010", "001", "110"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "110", "001", "110"],
    "6": ["011", "100", "111", "101", "111"],
    "8": ["111", "101", "111", "101", "111"],
    "A": ["010", "101", "111", "101", "101"],
    "C": ["011", "100", "100", "100", "011"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"],
    "G": ["011", "100", "101", "101", "011"],
    "I": ["111", "010", "010", "010", "111"],
    "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"],
    "M": ["101", "111", "111", "101", "101"],
    "O": ["010", "101", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "V": ["101", "101", "101", "101", "010"],
    "W": ["101", "101", "111", "111", "101"],
    "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"],
    ".": ["000", "000", "000", "000", "010"],
    " ": ["000"] * 5,
}


def rgb(c):
    assert all(isinstance(v, int) and 0 <= v <= 31 for v in c)
    return tuple(round(v * 255 / 31) for v in c)


def label(im, text, x, y, color):
    for i, char in enumerate(text):
        for dy, row in enumerate(FONT[char]):
            for dx, value in enumerate(row):
                if value == "1":
                    im.putpixel((x + i * 4 + dx, y + dy), rgb(color))


def dot(im, x, y, color):
    im.putpixel((x, y), rgb(color))


def signal(kind):
    values = []
    for x in range(58):
        phase = 2 * math.pi * 2.15 * x / 57
        if kind == "sine":
            v = math.sin(phase)
        elif kind == "complex":
            v = (math.sin(phase) + .25 * math.sin(phase * 3) + .10 * math.sin(phase * 5)) / 1.08
        elif kind == "pluck":
            v = math.sin(phase * 1.7) * math.exp(-1.5 * x / 57)
        elif kind == "silence":
            v = 0
        else:
            raise ValueError(kind)
        values.append(v)
    return values


STYLES = [
    ("A", "薄荷示波器", "最均衡 · 建议先看这一版", (0, 31, 19),
     "细线主波形 / 稀疏点阵网格", "横轴只留 0、5、10 ms 三个主刻度"),
    ("B", "琥珀仪表", "刻度感更强 · 更像仪器", (31, 19, 3),
     "暖色波形 / 时间轴独立成一条标尺", "小刻度分组，主刻度清楚，边界更明确"),
    ("C", "冰蓝音乐", "更有舞台感 · 更活泼", (1, 25, 31),
     "冰蓝曲线 / 极暗填充衬托起伏", "时间轴用短节拍点，避免横线压过波形"),
    ("D", "白金极简", "最干净 · 远看容易辨认", (28, 30, 27),
     "冷白主线 / 移除纵向网格", "细金色时间轴，信息和图形尽量分开"),
]


def panel(style, kind="sine"):
    code, _, _, trace, _, _ = style
    im = Image.new("RGB", (64, 64), (0, 0, 0))
    d = ImageDraw.Draw(im)
    muted = (8, 11, 12)
    label(im, "WAVE", 3, 2, muted)
    label(im, "X16", 44, 2, (10, 15, 14))
    dot(im, 60, 4, (0, 22, 8) if kind != "silence" else (12, 5, 1))
    center = 27
    if code == "A":
        for x in (3, 17, 30, 44, 57):
            for y in range(12, 43, 6):
                dot(im, x, y, (0, 2, 2))
        for x in range(3, 61, 4):
            dot(im, x, center, (0, 3, 2))
        for x in range(3, 61):
            dot(im, x, 44, (0, 3, 2))
        for x in (3, 30, 57):
            d.line((x, 43, x, 45), fill=rgb((3, 10, 8)))
    elif code == "B":
        # A quiet open frame: no bright box surrounding the waveform.
        for y in range(12, 42, 3):
            dot(im, 2, y, (5, 3, 0))
        for x in range(3, 61, 4):
            dot(im, x, center, (4, 2, 0))
        d.line((3, 44, 60, 44), fill=rgb((8, 5, 1)))
        for x in range(3, 60, 5):
            dot(im, x, 43, (8, 5, 1))
        for x in (3, 30, 57):
            d.line((x, 42, x, 45), fill=rgb((18, 11, 2)))
    elif code == "C":
        for x in range(3, 61, 5):
            dot(im, x, center, (0, 2, 4))
        for x in range(3, 61, 3):
            dot(im, x, 44, (1, 5, 8))
        for x in (3, 30, 57):
            d.line((x, 43, x, 45), fill=rgb((1, 14, 20)))
    else:
        for x in range(3, 61, 7):
            dot(im, x, center, (3, 3, 3))
        d.line((3, 44, 60, 44), fill=rgb((6, 5, 2)))
        for x in (3, 30, 57):
            d.line((x, 43, x, 45), fill=rgb((17, 13, 4)))
    points = [(x + 3, round(center - 13 * v)) for x, v in enumerate(signal(kind))]
    if code == "C":
        for x, y in points:
            for sy in range(min(center, y), max(center, y) + 1):
                # Dithered dark fill is native to the pixel grid, not blur.
                if (x + sy) % 2 == 0:
                    dot(im, x, sy, (0, 2, 4))
    d.line(points, fill=rgb(trace), width=1)
    axis_color = (10, 13, 13) if code in "AC" else (13, 11, 7)
    label(im, "0", 2, 47, axis_color)
    label(im, "5", 29, 47, axis_color)
    label(im, "10", 54, 47, axis_color)
    # Unit shares the header: using a microscopic suffix beside '10' would
    # make the axis crowd the panel. MS at y=9 is outside the graph area.
    label(im, "MS", 53, 9, (5, 7, 8))
    levels = (10, 6, 3) if kind != "silence" else (0, 0, 0)
    colors = ((0, 24, 7), (0, 18, 26), (27, 12, 1))
    for left, ch, level, color in zip((2, 23, 44), "TIG", levels, colors):
        label(im, ch, left, 58, (7, 10, 10))
        if level:
            d.rectangle((left + 5, 59, left + 4 + level, 61), fill=rgb(color))
    return im


def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size)


def led_view(im, step=7):
    # No photographic glow is added: the review should expose the real
    # 64x64 spatial limit, including the legibility of 3x5 characters.
    out = Image.new("RGB", (64 * step, 64 * step), "#020506")
    d = ImageDraw.Draw(out)
    for y in range(64):
        for x in range(64):
            c = im.getpixel((x, y))
            c = c if max(c) else (11, 15, 17)
            pad = 1.2 if step >= 7 else .8
            d.ellipse((x * step + pad, y * step + pad,
                       (x + 1) * step - pad, (y + 1) * step - pad), fill=c)
    return out


def single(style):
    code, name, subtitle, color, line1, line2 = style
    im = panel(style)
    im.save(OUT / f"{code}_pixels_64.png")
    im.resize((768, 768), Image.Resampling.NEAREST).save(OUT / f"{code}_pixels_enlarged.png")
    canvas = Image.new("RGB", (720, 896), "#0c141a")
    d = ImageDraw.Draw(canvas)
    d.text((40, 26), f"{code}  {name}", font=font(30), fill=rgb(color))
    d.text((40, 72), subtitle, font=font(18), fill="#bac5cc")
    canvas.paste(led_view(im, 10), (40, 116))
    d.text((40, 782), line1, font=font(19), fill="#e0e6e9")
    d.text((40, 815), line2, font=font(18), fill="#9aadb9")
    d.text((40, 860), "64×64 像素设计稿 · 同一波形 · 尚未烧录", font=font(15), fill="#637a87")
    canvas.save(OUT / f"{code}_concept.png")


def comparison():
    canvas = Image.new("RGB", (1504, 1356), "#0a1117")
    d = ImageDraw.Draw(canvas)
    d.text((40, 25), "波形与横轴，一起重新设计", font=font(34), fill="#e8eff2")
    d.text((40, 80), "四个方向 / 相同波形与比例 / 所有屏内元素均按真实 64×64 像素绘制", font=font(20), fill="#92a8b8")
    for i, style in enumerate(STYLES):
        code, name, subtitle, color, line1, line2 = style
        x, y = 40 + (i % 2) * 744, 143 + (i // 2) * 586
        d.rounded_rectangle((x - 8, y - 8, x + 688, y + 551), radius=18, fill="#101d26")
        d.text((x + 10, y + 4), f"{code}  {name}", font=font(27), fill=rgb(color))
        canvas.paste(led_view(panel(style), 7), (x + 12, y + 56))
        d.text((x + 482, y + 76), "横轴设计", font=font(19), fill="#e6edf1")
        descriptions = {
            "A": ["连续细轴", "三个主刻度", "灰绿数字", "点阵网格退后"],
            "B": ["金色标尺", "长短刻度分层", "刻度与曲线同色", "有仪器的秩序感"],
            "C": ["节奏点刻度", "冰蓝主色", "暗填充增强起伏", "信息更像音乐界面"],
            "D": ["金色细横轴", "白色波形", "移除纵向网格", "留白最多"],
        }
        for j, text in enumerate(descriptions[code]):
            d.text((x + 482, y + 123 + j * 40), text, font=font(18), fill="#96aebc")
        d.text((x + 12, y + 515), subtitle, font=font(19), fill="#c2d0d8")
    d.text((40, 1320), "概念效果图，不是实板照片或仿真验收图。最终刻度将匹配实际采样时间。", font=font(17), fill="#7c929f")
    canvas.save(OUT / "comparison.png")


def conditions():
    canvas = Image.new("RGB", (1504, 594), "#0a1117")
    d = ImageDraw.Draw(canvas)
    d.text((30, 18), "A 版在不同声音下的构图", font=font(29), fill="#d9eee7")
    for i, (kind, text) in enumerate((("sine", "纯音"), ("complex", "复杂音色"), ("pluck", "拨弦衰减"), ("silence", "静音"))):
        x = 30 + i * 370
        d.text((x, 78), text, font=font(21), fill="#abbfc8")
        canvas.paste(led_view(panel(STYLES[0], kind), 5), (x, 124))
    d.text((30, 485), "静音保留零线，音源条归零；不靠虚构的起伏装饰画面。", font=font(21), fill="#afc2cb")
    d.text((30, 533), "波形是构图示意，非现场采样；小信号显示增益会明确标注。", font=font(17), fill="#738e9f")
    canvas.save(OUT / "A_conditions.png")


if __name__ == "__main__":
    for style in STYLES:
        single(style)
    comparison()
    conditions()
    (OUT / "manifest.json").write_text(json.dumps({
        "kind": "concept-only", "panel_pixels": [64, 64], "color_bits_per_channel": 5,
        "styles": [{"id": s[0], "title": s[1]} for s in STYLES],
        "note": "Design studies use illustrative signal shapes, not measured or simulated PCM."
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(OUT / "comparison.png")
