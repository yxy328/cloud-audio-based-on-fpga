"""Render the three externally decoded HUB75E frames for visual inspection."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
build = root / "sim/build"
frames = [
    ("audio_visual_panel", "实时波形与音源幅度"),
    ("xy_lissajous_panel", "参考李萨如 · 八字 1:2"),
    ("xy_spectrum_panel", "实时 FFT 频谱（16频段）"),
]
font_path = Path("C:/Windows/Fonts/msyh.ttc")
font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else ImageFont.load_default()
small = ImageFont.truetype(str(font_path), 20) if font_path.exists() else ImageFont.load_default()
canvas = Image.new("RGB", (1248, 560), "#13171e")
draw = ImageDraw.Draw(canvas)
draw.text((24, 18), "HUB75E 音频可视化 · FPGA 引脚仿真", font=font, fill="white")
for index, (name, label) in enumerate(frames):
    frame = Image.open(build / f"{name}.ppm").convert("RGB")
    assert frame.size == (64, 64), frame.size
    frame.resize((512, 512), Image.Resampling.NEAREST).save(build / f"{name}.png")
    left = 24 + index * 408
    draw.text((left, 70), label, font=font, fill="white")
    canvas.paste(frame.resize((384, 384), Image.Resampling.NEAREST), (left, 112))
draw.text((24, 520), "波形页底部为总混音 PK；XY / FFT 为三音源幅度。仿真重建，尚未实板验收。", font=small, fill="#b9c3d2")
canvas.save(build / "xy_fft_panel_preview.png")
print(build / "xy_fft_panel_preview.png")

presets = [
    ("xy_lissajous_panel", "八字 · REF 1:2 / 0°"),
    ("xy_multiloop_panel", "多瓣 · REF 2:3 / 0°"),
    ("xy_circle_panel", "圆 · REF 1:1 / 90°"),
    ("xy_ellipse_panel", "椭圆 · REF 1:1 / 45°"),
    ("xy_line_panel", "直线 · REF 1:1 / 0°"),
    ("xy_audio_panel", "实际混音延时 XY · AUD"),
]
comparison = Image.new("RGB", (1248, 1000), "#13171e")
draw = ImageDraw.Draw(comparison)
draw.text((24, 14), "HUB75E 六种 XY 画面 · FPGA 外部引脚仿真重建", font=font, fill="white")
for index, (name, label) in enumerate(presets):
    frame = Image.open(build / f"{name}.ppm").convert("RGB")
    assert frame.size == (64, 64), frame.size
    frame.resize((512, 512), Image.Resampling.NEAREST).save(build / f"{name}.png")
    left, top = 24 + (index % 3) * 408, 60 + (index // 3) * 440
    draw.text((left, top), label, font=small, fill="white")
    comparison.paste(frame.resize((384, 384), Image.Resampling.NEAREST), (left, top+34))
draw.text((24, 958), "REF 为数学参考；AUD 为现场混音。下方三条为真实音源幅度。尚未实板验收。", font=small, fill="#b9c3d2")
comparison.save(build / "lissajous_presets_preview.png")
print(build / "lissajous_presets_preview.png")
