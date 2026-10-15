"""Plot actual I2S-decoded RTL samples; requires Pillow, not a signal model."""
import csv
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "sim" / "build"
with (BUILD / "guitar_samples.csv").open(newline="") as source:
    rows = list(csv.DictReader(source))
times = [int(row["time_ns"]) / 1e6 for row in rows]
samples = [int(row["pcm"]) for row in rows]
assert len(samples) > 100 and all(-32768 <= y <= 32767 for y in samples)

image = Image.new("RGB", (1500, 1150), "#f4f7fb")
draw = ImageDraw.Draw(image)
font_path = Path("C:/Windows/Fonts/msyh.ttc")
def font(size):
    return ImageFont.truetype(str(font_path), size)

draw.text((55, 28), "Karplus–Strong 吉他拨弦 · RTL 仿真波形", font=font(34), fill="#142d4e")
draw.text((55, 85), "数据来自 I2S 引脚解码，非示意图  |  采样率 48,828.125 Hz  |  延迟线 110 点", font=font(20), fill="#45617c")
draw.text((55, 119), "测试激励：0.2 ms 按下，4.2 ms 松开；测试台将防抖缩短为 2 μs，音频时钟保持实际速率。", font=font(18), fill="#61758c")

def panel(y_top, title, lo, hi, limit, step):
    draw.rounded_rectangle((35, y_top, 1465, y_top+290), radius=16, fill="white")
    draw.text((60, y_top+14), title, font=font(23), fill="#142d4e")
    x0, x1, y0, y1 = 130, 1410, y_top+66, y_top+235
    def x(t): return x0+(t-lo)/(hi-lo)*(x1-x0)
    def y(v): return (y0+y1)/2-v/limit*(y1-y0)/2
    for v in (-limit, -limit//2, 0, limit//2, limit):
        py = y(v)
        draw.line((x0, py, x1, py), fill="#dbe4ee", width=1)
        label = str(v)
        draw.text((x0-15-draw.textlength(label, font=font(15)), py-10), label, font=font(15), fill="#61758c")
    t = lo
    while t <= hi+1e-6:
        px = x(t)
        draw.line((px, y0, px, y1), fill="#edf1f6")
        label = f"{t:g}"
        draw.text((px-draw.textlength(label, font=font(15))/2, y1+10), label, font=font(15), fill="#61758c")
        t += step
    draw.text((x1-65, y1+35), "时间 / ms", font=font(16), fill="#61758c")
    draw.text((55, y_top+45), "PCM", font=font(15), fill="#61758c")
    points = [(x(t), y(v)) for t,v in zip(times,samples) if lo <= t <= hi]
    # Min/max buckets preserve brief peaks when plotting many audio samples.
    if len(points) > 2*(x1-x0):
        buckets = {}
        for px,py in points:
            bucket = buckets.setdefault(int(px), [py,py])
            bucket[0],bucket[1] = min(bucket[0],py),max(bucket[1],py)
        for px,(minimum,maximum) in buckets.items():
            draw.line((px,minimum,px,maximum), fill="#1976b9", width=1)
    elif len(points) > 1:
        draw.line(points, fill="#1976b9", width=2)
    if lo == 0 and hi <= 30:
        for t,label,color in ((0.2,"按下", "#dd8b19"),(4.2,"松开", "#c9496a")):
            px=x(t)
            draw.line((px,y0,px,y1),fill=color,width=2)
            draw.text((px+5,y0+4),label,font=font(16),fill=color)

panel(170, "① 整体衰减：松开按键后，弦仍继续振动", 0, 1000, 9000, 200)
panel(475, "② 起音细节：短噪声激励 → 循环振动", 0, 20, 9000, 4)
late = [abs(v) for t,v in zip(times,samples) if 80 <= t <= 95]
late_limit = max(500, int(math.ceil(max(late,default=500)/500))*500)
panel(780, "③ 80–95 ms 局部放大：周期性波形（纵轴已放大）", 80, 95, late_limit, 3)
draw.text((55, 1092), "蓝线为 16-bit 有符号音频采样值；这是数字仿真结果，尚未包含 DAC 与功放的模拟响应。", font=font(18), fill="#61758c")
destination = BUILD / "guitar_wave.png"
image.save(destination)
print(f"Saved {destination} ({len(samples)} decoded stereo frames)")
