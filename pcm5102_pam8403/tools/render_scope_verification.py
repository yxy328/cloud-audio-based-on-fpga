"""Render actual RTL-generated PPM frames, preserving their 64x64 pixels."""
from pathlib import Path
from PIL import Image, ImageDraw
from render_scope_concepts import led_view, font

root=Path(__file__).resolve().parents[1]
build=root/'sim/build'
out=root/'design/led_scope_20261022/verified'
out.mkdir(parents=True,exist_ok=True)
frames=[
    ('scope_fsr100','FSR 100% / 峰值 2048','×8 · ±4K · 红色'),
    ('scope_fsr50','FSR 50% / 峰值 1024','×16 · ±2K · 紫色'),
    ('scope_fsr25','FSR 25% / 峰值 512','×32 · ±1K · 饱和蓝'),
    ('scope_overrange','FSR 25% / 混音峰值 100%','优先扩大到 ×1 / ±100%'),
    ('scope_weak128','FSR 25% / 峰值 128','×32 · 低于 1% 的信号也显示蓝色'),
    ('scope_silence','静音 / 峰值 0%','低亮白零线 · 电平条归零'),
]
canvas=Image.new('RGB',(1512,1300),'#0b141b')
d=ImageDraw.Draw(canvas)
d.text((28,20),'新版 LED 波形 · RTL 仿真像素输出',font=font(32),fill='#e5f0ef')
d.text((28,72),'颜色按真实数字峰值变化，FSR 改变显示量程；字体和刻度也由 RTL 输出。',font=font(20),fill='#9fb4c0')
for i,(name,title,detail) in enumerate(frames):
    im=Image.open(build/f'{name}.ppm').convert('RGB')
    assert im.size==(64,64)
    im.save(out/f'{name}_64.png')
    im.resize((640,640),Image.Resampling.NEAREST).save(out/f'{name}.png')
    x=28+(i%3)*500;y=132+(i//3)*550
    d.text((x,y),title,font=font(23),fill='#cbded7')
    canvas.paste(led_view(im,7),(x,y+48))
    d.text((x,y+511),detail,font=font(19),fill='#a8c2ce')
d.text((28,1260),'波形页底部为总混音 PK；XY 和频谱页继续保留触摸 / 红外手势 / 吉他三组幅度条。',font=font(20),fill='#99b1bf')
canvas.save(out/'scope_verified_comparison.png')
canvas.crop((0,0,1512,686)).save(out/'scope_playing_preview.png')
print(out/'scope_verified_comparison.png')
