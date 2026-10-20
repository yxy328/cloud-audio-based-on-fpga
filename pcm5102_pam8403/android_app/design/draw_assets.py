# -*- coding: utf-8 -*-
"""「孤独摇滚 · 霓虹舞台」主题素材绘制（Pillow 逐像素，1080x2400 为基准）。

不依赖任何外部图片素材，全部为原创几何/文字构成。
输出：
  app/src/main/assets/backdrop.png   1080x2400 默认全屏背景
  app/src/main/assets/hero.png       972x560  主视觉面板
  app/src/main/assets/hero_art.png   420x520  仅装饰图形（透明）
  design/out/mockup.png              1080x2400 整屏效果图
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(HERE, "out")
ASSETS = os.path.join(ROOT, "app", "src", "main", "assets")
os.makedirs(OUT, exist_ok=True)
os.makedirs(ASSETS, exist_ok=True)

SS = 2  # 超采样
W, H = 1080, 2400

INK = (0x24, 0x1A, 0x2E)
MUTED = (0x75, 0x65, 0x7F)
PINK = (0xE8, 0x44, 0x7F)
PINK_INK = (0xBF, 0x2E, 0x66)
VIOLET = (0x7A, 0x4F, 0xD8)
CYAN = (0x20, 0xB7, 0xC6)
SURFACE = (0xFF, 0xFB, 0xFF)
WHITE = (255, 255, 255)

F_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
F_REG = r"C:\Windows\Fonts\msyh.ttc"
F_MONO = r"C:\Windows\Fonts\consola.ttf"
F_SANS = r"C:\Windows\Fonts\segoeui.ttf"

# CJK 覆盖：msyh / msjh 均有中日文字形
F_CJK = F_REG
F_CJK_BOLD = F_BOLD


def font(path, size):
    return ImageFont.truetype(path, size * SS)


FONTS = {
    "bold": font(F_BOLD, 74), "reg": font(F_REG, 27),
    "hint": font(F_REG, 24), "lead": font(F_REG, 36),
    "body": font(F_REG, 25), "tag": font(F_REG, 23),
    "title": font(F_BOLD, 40), "btn": font(F_BOLD, 29),
    "badge": font(F_BOLD, 30), "eyebrow": font(F_MONO, 21),
    "chip": font(F_CJK, 19),
}


def imgsize(w, h):
    return (int(w * SS), int(h * SS))


def new_layer(w, h):
    return Image.new("RGBA", imgsize(w, h), (0, 0, 0, 0))


def finish(img, w, h):
    return img.resize((int(w), int(h)), Image.LANCZOS)


def rounded_mask(w, h, radius):
    m = Image.new("L", imgsize(w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, int(w * SS) - 1, int(h * SS) - 1],
                                        radius=int(radius * SS), fill=255)
    return m


def vgradient(w, h, stops):
    img = Image.new("RGBA", imgsize(w, h))
    d = ImageDraw.Draw(img)
    ih = int(h * SS)
    for y in range(ih):
        t = y / max(1, ih - 1)
        col = stops[-1][1] + (255,)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                k = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
                col = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)) + (255,)
                break
        d.line([(0, y), (int(w * SS), y)], fill=col)
    return img


def diag_gradient(w, h, stops, angle_deg=35):
    span = int(math.hypot(w * SS, h * SS)) + 8
    strip = vgradient(span / SS, span / SS, stops)
    rotated = strip.rotate(-angle_deg, resample=Image.BICUBIC, expand=False)
    left = (span - int(w * SS)) // 2
    top = (span - int(h * SS)) // 2
    return rotated.crop((left, top, left + int(w * SS), top + int(h * SS)))


def paste_rounded(base, layer, xy, radius):
    """把 layer 以圆角遮罩画到 base 的 xy 处（base/layer 均为 SS 坐标系）。"""
    w, h = layer.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=int(radius), fill=255)
    base.paste(layer, xy, m)


# ── 拨片：用三次贝塞尔采样出真实拨片轮廓（上宽下尖、圆肩）
def _bezier(p0, p1, p2, p3, steps=26):
    pts = []
    for i in range(steps + 1):
        t = i / float(steps)
        mt = 1.0 - t
        x = (mt ** 3) * p0[0] + 3 * (mt ** 2) * t * p1[0] + 3 * mt * (t ** 2) * p2[0] + (t ** 3) * p3[0]
        y = (mt ** 3) * p0[1] + 3 * (mt ** 2) * t * p1[1] + 3 * mt * (t ** 2) * p2[1] + (t ** 3) * p3[1]
        pts.append((x, y))
    return pts


def pick_outline(w, h):
    """返回拨片闭合轮廓点（原点在左上，尺寸 w x h）。"""
    pts = []
    # 顶部：从左肩到右肩的缓弧
    pts += _bezier((0.10 * w, 0.16 * h), (0.26 * w, -0.03 * h),
                   (0.74 * w, -0.03 * h), (0.90 * w, 0.16 * h))
    # 右腰：向右外扩后收向尖端
    pts += _bezier((0.90 * w, 0.16 * h), (1.02 * w, 0.44 * h),
                   (0.70 * w, 0.80 * h), (0.50 * w, 1.00 * h))
    # 左腰：镜像回到左肩
    pts += _bezier((0.50 * w, 1.00 * h), (0.30 * w, 0.80 * h),
                   (-0.02 * w, 0.44 * h), (0.10 * w, 0.16 * h))
    return pts


def draw_pick(canvas, cx, cy, w, h, color, rot=0, alpha=255):
    """在 canvas（SS 坐标系）上画一枚拨片，可旋转。"""
    pad = 0.18
    bw, bh = w * (1 + 2 * pad), h * (1 + 2 * pad)
    layer = Image.new("RGBA", imgsize(bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = pad * w, pad * h
    outline = [(p[0] + ox, p[1] + oy) for p in pick_outline(w, h)]
    d.polygon([(x * SS, y * SS) for x, y in outline], fill=color + (alpha,))
    if rot:
        layer = layer.rotate(-rot, resample=Image.BICUBIC, expand=False)
    canvas.alpha_composite(layer, (int(cx * SS - layer.width / 2), int(cy * SS - layer.height / 2)))


def text(d, xy, s, fnt, fill, anchor="la", stroke=0, stroke_fill=None, shadow=None):
    if shadow:
        off, scol = shadow
        d.text((xy[0] + off, xy[1] + off), s, font=fnt, fill=scol, anchor=anchor,
               stroke_width=stroke, stroke_fill=stroke_fill)
    d.text(xy, s, font=fnt, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=stroke_fill)


# ══════════════════════════════════════════════════════════
# 背景：淡樱花渐变 + 顶部柔光 + 斜向速度线 + 波点
# ══════════════════════════════════════════════════════════
def build_backdrop():
    img = vgradient(W, H, [(0.0, (0xFF, 0xF4, 0xF9)),
                           (0.55, (0xF6, 0xF0, 0xFF)),
                           (1.0, (0xFF, 0xF6, 0xFB))])

    # 顶部柔光（小 alpha 叠加后整体模糊，避免出现同心环）
    glow = new_layer(W, H)
    gd = ImageDraw.Draw(glow)
    cx, cy = int(W * 0.78 * SS), int(-H * 0.06 * SS)
    rad = int(W * 1.05 * SS)
    gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(0xFF, 0x7A, 0xB6, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(90 * SS))
    img = Image.alpha_composite(img, glow)

    # 斜向速度线（番剧常见的漫画集中线，极淡）
    rays = new_layer(W, H)
    rd = ImageDraw.Draw(rays)
    ox, oy = int(W * 0.5 * SS), int(-H * 0.02 * SS)
    for i in range(26):
        ang = math.radians(-90 + (i - 13) * 5.2)
        x2 = ox + math.cos(ang) * W * 2 * SS
        y2 = oy + math.sin(ang) * W * 2 * SS
        rd.line([(ox, oy), (x2, y2)], fill=(0xE8, 0x44, 0x7F, 8), width=int(3 * SS))
    img = Image.alpha_composite(img, rays.filter(ImageFilter.GaussianBlur(1.2 * SS)))

    # 波点：只在页面两侧，越往下越大越淡
    dots = new_layer(W, H)
    dd = ImageDraw.Draw(dots)
    for row in range(26):
        depth = row / 26.0
        y = (110 + row * 90) * SS
        if y > H * SS:
            break
        r = (2.8 + depth * 7.4) * SS
        alpha = int(34 * (1.0 - depth * 0.85))
        if alpha <= 1:
            continue
        for side in (0, 1):
            base_x = (34 if side == 0 else 760) * SS
            step = 74 if side == 0 else 78
            for k in range(4):
                x = base_x + k * step * SS
                if x > W * SS:
                    break
                dd.ellipse([x - r, y - r, x + r, y + r], fill=PINK + (alpha,))
    img = Image.alpha_composite(img, dots)
    return img


# ══════════════════════════════════════════════════════════
# Hero 面板：只画插画，文字由 App 端绘制（避免重复与拉伸变形）
# ══════════════════════════════════════════════════════════
HX, HY, HW, HH, HR = 54, 140, 972, 300, 30


def hero_layer():
    """纯插画层：渐变 / 追光 / 声波环 / 拨片 / 火花。不含任何文字。"""
    layer = new_layer(W, H)
    card = diag_gradient(HW, HH, [(0.0, (0x2A, 0x14, 0x40)),
                                  (0.58, (0x6A, 0x2B, 0x8F)),
                                  (1.0, (0xE8, 0x44, 0x7F))], angle_deg=28)
    cw, ch = card.size

    # 追光
    beams = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    bd = ImageDraw.Draw(beams)
    bd.polygon([(cw * 0.40, 0), (cw * 0.60, 0), (cw * 1.00, ch), (cw * 0.54, ch)],
               fill=(255, 255, 255, 16))
    bd.polygon([(cw * 0.68, 0), (cw * 0.80, 0), (cw * 1.02, ch), (cw * 0.84, ch)],
               fill=(255, 255, 255, 11))
    card = Image.alpha_composite(card, beams)

    # 声波环：圆心放在右侧装饰区中心
    rings = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    rcx, rcy = int(cw * 0.775), int(ch * 0.54)
    for i, rad in enumerate((66, 116, 166)):
        rd.ellipse([rcx - rad * SS, rcy - rad * SS, rcx + rad * SS, rcy + rad * SS],
                   outline=(0xFF, 0xD7, 0xEA, 42 - i * 12), width=int(2.2 * SS))
    card = Image.alpha_composite(card, rings)

    # 拨片（右中）
    px_c, py_c = (cw / SS) * 0.775, (ch / SS) * 0.56
    draw_pick(card, px_c + 7, py_c + 8, 108, 114, CYAN, rot=16, alpha=120)
    draw_pick(card, px_c, py_c, 108, 114, (0xFF, 0x7A, 0xB6), rot=16)
    hr = int(6.2 * SS)
    hx, hy = int((px_c - 16) * SS), int((py_c - 14) * SS)
    ImageDraw.Draw(card).ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 255, 255, 105))

    # 火花
    sd = ImageDraw.Draw(card)
    for (sx, sy, s) in ((58, 44, 7), (44, 250, 6), (912, 40, 7), (930, 250, 6), (430, 20, 4), (700, 268, 4)):
        spx, spy, sph = sx * SS, sy * SS, s * SS
        sd.polygon([(spx, spy - sph), (spx + sph * 0.30, spy - sph * 0.30), (spx + sph, spy),
                    (spx + sph * 0.30, spy + sph * 0.30), (spx, spy + sph),
                    (spx - sph * 0.30, spy + sph * 0.30), (spx - sph, spy),
                    (spx - sph * 0.30, spy - sph * 0.30)],
                   fill=(255, 255, 255, 160))

    paste_rounded(layer, card, (HX * SS, HY * SS), HR * SS)
    return layer


# ══════════════════════════════════════════════════════════
# 整屏效果图
# ══════════════════════════════════════════════════════════
def build_mockup():
    img = Image.alpha_composite(build_backdrop(), hero_layer())
    d = ImageDraw.Draw(img)

    # hero 上的文字：尺寸/位置与 Android 端 buildUi 中的 dp/sp 一致（卡片内边距 24dp/18dp）
    tx, ty = HX + 24, HY + 18
    text(d, (int(tx * SS), int((ty + 2) * SS)), "F P G A   /   M U S I C   L A B",
         font(F_MONO, 11), (0xFF, 0xC9, 0xDE, 255))
    text(d, (int(tx * SS), int((ty + 20) * SS)), "FPGA 曲谱助手", font(F_BOLD, 28),
         (255, 255, 255, 255), stroke=int(1.6 * SS), stroke_fill=(0x3A, 0x18, 0x52, 255),
         shadow=(int(2 * SS), (0x2A, 0x0E, 0x3C, 130)))
    text(d, (int(tx * SS), int((ty + 66) * SS)), "让每一次触碰，都有旋律。", font(F_REG, 15),
         (0xFF, 0xDC, 0xEA, 255), shadow=(int(1 * SS), (0x2A, 0x0E, 0x3C, 90)))
    text(d, (int(tx * SS), int((ty + 94) * SS)), "HC-05 蓝牙连接  ·  HUB75E 屏幕指引", font(F_REG, 12),
         (0xF0, 0xD5, 0xEA, 255))
    text(d, (int(tx * SS), int((ty + 116) * SS)), "触摸、手势与单弦吉他，由 FPGA 实时合成。", font(F_REG, 12),
         (0xF0, 0xD5, 0xEA, 255))
    text(d, (int(tx * SS), int((ty + 158) * SS)), "孤独摇滚 · 霓虹舞台主题", font(F_REG, 11),
         (0x8E, 0xF0, 0xFF, 255))

    def hgrad(w, h, c0, c1, radius):
        layer = Image.new("RGBA", imgsize(w, h), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        iw = int(w * SS)
        for x in range(iw):
            k = x / max(1, iw - 1)
            col = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)) + (255,)
            ld.line([(x, 0), (x, int(h * SS))], fill=col)
        layer.putalpha(rounded_mask(w, h, radius))
        return layer

    # 状态条
    sy = HY + HH + 26
    status = new_layer(972, 92)
    sd = ImageDraw.Draw(status)
    sd.rounded_rectangle([0, 0, int(972 * SS) - 1, int(92 * SS) - 1], radius=int(28 * SS),
                         fill=(0xFF, 0xF6, 0xFB, 252), outline=(0xE8, 0x44, 0x7F, 30),
                         width=int(1.3 * SS))
    bx = int(34 * SS)
    for level in (0.42, 0.80, 1.0, 0.60, 0.88, 0.50):
        bh = int(22 * 0.9 * level * SS)
        byy = (int(92 * SS) - bh) // 2
        sd.rounded_rectangle([bx, byy, bx + int(6 * SS), byy + bh], radius=int(3 * SS),
                             fill=(0xE8, 0x44, 0x7F, 220))
        bx += int(11 * SS)
    text(sd, (int(112 * SS), int(24 * SS)), "设 备 状 态", FONTS["tag"], MUTED + (255,))
    text(sd, (int(112 * SS), int(48 * SS)), "先在系统蓝牙设置配对 HC-05，再刷新设备",
         FONTS["badge"], PINK_INK + (255,))
    img.alpha_composite(status, (int(54 * SS), int(sy * SS)))

    def card(y, badge, title, hint, rows):
        h = 236 + len(rows) * 64
        c = new_layer(972, h)
        cd = ImageDraw.Draw(c)
        cd.rounded_rectangle([0, 0, int(972 * SS) - 1, int(h * SS) - 1], radius=int(22 * SS),
                             fill=SURFACE + (255,), outline=(0xE8, 0x44, 0x7F, 40), width=int(1.3 * SS))
        ln = hgrad(972 - 80, 4, PINK, CYAN, 2)
        c.alpha_composite(ln, (int(40 * SS), int(20 * SS)))
        # 序号徽章
        bimg = hgrad(54, 54, (0xF0, 0x4C, 0x8A), (0xA4, 0x4B, 0xE0), 18)
        c.alpha_composite(bimg, (int(40 * SS), int(44 * SS)))
        text(cd, (int((40 + 27) * SS), int((44 + 27) * SS)), badge, FONTS["badge"],
             (255, 255, 255, 255), anchor="mm")
        text(cd, (int(110 * SS), int(46 * SS)), title, FONTS["title"], INK + (255,))
        text(cd, (int(40 * SS), int(112 * SS)), hint, FONTS["hint"], MUTED + (255,))
        yy = 162
        for label, style in rows:
            if style == "primary":
                b = hgrad(892, 54, (0xF0, 0x4C, 0x8A), (0xA4, 0x4B, 0xE0), 16)
                c.alpha_composite(b, (int(40 * SS), int(yy * SS)))
                text(cd, (int((40 + 446) * SS), int((yy + 27) * SS)), label, FONTS["btn"],
                     (255, 255, 255, 255), anchor="mm")
            else:
                cd.rounded_rectangle([int(40 * SS), int(yy * SS), int((40 + 892) * SS), int((yy + 54) * SS)],
                                     radius=int(16 * SS), fill=SURFACE + (255,),
                                     outline=(0xA4, 0x4B, 0xE0, 80), width=int(1.3 * SS))
                text(cd, (int((40 + 446) * SS), int((yy + 27) * SS)), label, FONTS["btn"],
                     VIOLET + (255,), anchor="mm")
            yy += 64
        img.alpha_composite(c, (int(54 * SS), int(y * SS)))
        return y + h + 22

    y = sy + 92 + 26
    y = card(y, "01", "蓝牙连接", "先在系统蓝牙设置中配对 HC-05，再选择设备。",
             [("刷新设备", "ghost"), ("连接设备", "primary")])
    y = card(y, "02", "曲谱与播放", "导入并下载曲谱后，可选择自动演奏或跟随屏幕指引练习。",
             [("载入小星星示例 · 导入 CSV / MIDI", "ghost"), ("校验键位并下载 / 重新下载", "primary")])
    y = card(y, "03", "七键音高", "按第 1～7 键填写 MIDI 音高，范围 60～72。",
             [("第 1..7 键：60,62,64,65,67,69,71", "ghost")])
    if y + 300 < H - 70:
        y = card(y, "04", "红外 / 手势音源与吉他", "红外与手势共享 32 复音音源，音色和颤音同时生效。",
                 [("GUITAR · 单弦拨弦一次", "primary")])

    text(d, (int(W / 2 * SS), int((H - 58) * SS)),
         "FPGA MUSIC LAB  ·  孤独摇滚 · 让灵感在指尖发声", FONTS["tag"], MUTED + (255,), anchor="mm")
    return finish(img, W, H)


# ══════════════════════════════════════════════════════════
# 纯装饰素材
# ══════════════════════════════════════════════════════════
def build_hero_art():
    aw, ah = 420, 400
    art = new_layer(aw, ah)
    ad = ImageDraw.Draw(art)
    cx, cy = int(aw * 0.48 * SS), int(ah * 0.50 * SS)
    for i, rad in enumerate((80, 138, 196)):
        ad.ellipse([cx - rad * SS, cy - rad * SS, cx + rad * SS, cy + rad * SS],
                   outline=(0xFF, 0xD7, 0xEA, 46 - i * 12), width=int(2.4 * SS))
    draw_pick(art, aw * 0.50 + 7, ah * 0.52 + 8, 120, 128, CYAN, rot=16, alpha=125)
    draw_pick(art, aw * 0.50, ah * 0.52, 120, 128, (0xFF, 0x7A, 0xB6), rot=16)
    hr = int(6.6 * SS)
    hx, hy = int((aw * 0.50 - 18) * SS), int((ah * 0.52 - 15) * SS)
    ad.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 255, 255, 110))
    return finish(art, aw, ah)


def main():
    backdrop = finish(build_backdrop(), W, H)
    backdrop.save(os.path.join(ASSETS, "backdrop.png"), optimize=True)
    backdrop.save(os.path.join(OUT, "backdrop.png"))

    hero_canvas = Image.alpha_composite(new_layer(W, H), hero_layer())
    crop = hero_canvas.crop((HX * SS, HY * SS, (HX + HW) * SS, (HY + HH) * SS))
    hero_png = finish(crop, HW, HH)
    hero_png.save(os.path.join(ASSETS, "hero.png"), optimize=True)
    hero_png.save(os.path.join(OUT, "hero.png"))

    art = build_hero_art()
    art.save(os.path.join(ASSETS, "hero_art.png"), optimize=True)
    art.save(os.path.join(OUT, "hero_art.png"))

    mock = build_mockup()
    mock.save(os.path.join(OUT, "mockup.png"), optimize=True)

    for name in ("backdrop.png", "hero.png", "hero_art.png"):
        p = os.path.join(ASSETS, name)
        print(f"{name}: {Image.open(p).size} {os.path.getsize(p)} bytes")
    print("mockup:", mock.size, os.path.getsize(os.path.join(OUT, "mockup.png")), "bytes")


if __name__ == "__main__":
    main()
