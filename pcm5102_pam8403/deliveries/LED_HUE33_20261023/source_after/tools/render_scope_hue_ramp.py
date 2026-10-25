"""Check all RTL hue codes against integer/HSV models and render real PPMs."""
from pathlib import Path
import colorsys
import csv
from collections import Counter
from PIL import Image, ImageDraw
from render_scope_concepts import rgb, font, led_view

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'design/led_scope_20261023/hue33'
BUILD = ROOT / 'sim/build'
SAT = 0.903
FRAMES = [('scope_weak128', 2, 128), ('scope_fsr25', 8, 512),
          ('scope_fsr50', 16, 1024), ('scope_fsr100', 32, 2048)]


def expected(p):
    q = min(p, 32) * 6
    if q == 192:
        return (31, 3, 3)
    d = ((q % 64) * 7) // 16
    return [(3, 31-d, 31), (3+d, 3, 31), (31, 3, 31-d)][q // 64]


def main():
    rows = list(csv.DictReader((BUILD/'scope_hue33_palette.csv').open(encoding='ascii')))
    assert len(rows) == 64
    colors = []
    for p, row in enumerate(rows):
        assert int(row['p']) == p
        c = tuple(int(row[k]) for k in ('r', 'g', 'b'))
        assert c == expected(p), (p, c, expected(p))
        ideal = tuple(round(v*31) for v in colorsys.hsv_to_rgb(
            ((180+min(p, 32)*5.625) % 360)/360, SAT, 1.0))
        assert max(abs(a-b) for a,b in zip(c, ideal)) <= 1, (p, c, ideal)
        assert min(c) == 3 and max(c) == 31
        if colors:
            a = colors[-1]
            assert c[0] >= a[0] and c[1] <= a[1] and c[2] <= a[2]
        if p >= 32:
            assert c == (31, 3, 3)
        colors.append(c)
    assert len(set(colors[:33])) == 33
    metadata = {Path(r['file']).stem: r for r in csv.DictReader(
        (BUILD/'scope_hue33_frames.csv').open(encoding='ascii'))}
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = Image.new('RGB', (1512, 990), '#0b141b')
    d = ImageDraw.Draw(canvas)
    d.text((28, 18), 'LED 音量色环 · 33 档实际 RTL 输出', font=font(32), fill='#e5f0ef')
    d.text((28, 70), 'PCM 每 64 计数一级；色相 180° 青 → 360° 红；一帧一种颜色，渐强时逐档移动。',
           font=font(20), fill='#9fb4c0')
    for p, c in enumerate(colors[:33]):
        x = 28+p*44
        d.rectangle((x, 120, x+43, 170), fill=rgb(c))
        if p % 4 == 0:
            d.text((x, 178), str(p), font=font(17), fill='#a8c2ce')
    d.text((28, 222), '以下为 testbench 直接导出的 PPM，未后期换色；capture_peak64 与发布帧同步。',
           font=font(21), fill='#cbded7')
    for i, (name, p, amplitude) in enumerate(FRAMES):
        row = metadata[name]
        assert int(row['peak64']) == p, (name, row)
        c = tuple(int(row[k]) for k in ('r', 'g', 'b'))
        assert c == colors[p]
        im = Image.open(BUILD/f'{name}.ppm').convert('RGB')
        pixels = im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()
        saturated = [(c, n) for c,n in Counter(pixels).items() if max(c)-min(c)>40]
        dominant = max(saturated, key=lambda e:e[1])[0]
        assert dominant == rgb(colors[p]), (name, dominant, rgb(colors[p]))
        x = 28+i*372
        d.text((x, 270), f'峰值 {amplitude} · p={p}', font=font(22), fill='#cbded7')
        canvas.paste(led_view(im, 5), (x, 316))
        d.rectangle((x, 654, x+52, 684), fill=rgb(c))
        d.text((x+62, 656), f'RGB5 {c}', font=font(19), fill='#adc2cc')
    d.text((28, 728), '静音判据仍为 capture_peak==0；非零但不足 64 计数显示青色，零信号显示灰色。',
           font=font(20), fill='#a1b5c0')
    d.text((28, 776), '原有量程保护、PK 百分比、电平条长度和显示 RAM 几何保持不变。',
           font=font(20), fill='#a1b5c0')
    d.text((28, 824), '64 个输入码已与整数模型逐项比对；33 个色相点与 HSV 的通道误差均不超过 1 LSB。',
           font=font(19), fill='#a1b5c0')
    d.text((28, 872), '这是数字仿真结果，尚未进行本版实体面板验收。', font=font(19), fill='#8ea6b2')
    canvas.save(OUT/'hue33_verified.png')
    print(f'OK 64 RTL palette codes, 33 unique hues, HSV error <=1 LSB, monotonic saturation, 4 real RTL frames -> {OUT / "hue33_verified.png"}')


if __name__ == '__main__':
    main()

