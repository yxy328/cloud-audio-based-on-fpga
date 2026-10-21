package cn.fpga.score;

import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;

/**
 * 孤独摇滚主题的视觉常量。
 *
 * 配色取自动画式的「舞台霓虹」——热粉、紫罗兰、青色打在深梅色底上，
 * 叠加波点律动与追光。所有颜色都集中在这里：换主题只需改这个文件。
 */
final class Theme {
    private Theme() { }

    static final int WHITE = 0xffffffff;
    static final int CONNECTED = 0xff267b53;
    static final int DRAWER_SCRIM = 0x990e0618;
    static final int PIANO_BLACK = 0xff302638;

    /** 主墨色：略带紫调的近黑，比纯黑更柔和。 */
    static final int INK = 0xff241a2e;
    /** 次级文字。 */
    static final int MUTED = 0xff75657f;
    /** 霓虹热粉，主强调色。 */
    static final int PINK = 0xffe8447f;
    /** 热粉在浅底上的文字版本，保证对比度。 */
    static final int PINK_INK = 0xffbf2e66;
    /** 紫罗兰，次强调色。 */
    static final int VIOLET = 0xff7a4fd8;
    /** 青色，冷色点缀。 */
    static final int CYAN = 0xff20b7c6;
    /** 浅色卡片底。 */
    static final int SURFACE = 0xfffffbff;
    /** 次级浅底（输入框、信息块）。 */
    static final int SURFACE_ALT = 0xfffdf2f8;
    /** 卡片描边。 */
    static final int LINE = 0x1fe8447f;
    /** 深色面板（日志区）。 */
    static final int PANEL = 0xff2a1b33;
    /** 深色面板上的文字。 */
    static final int PANEL_TEXT = 0xffe9dcff;
    /** 危险/停止类文字与其浅底。 */
    static final int DANGER = 0xffb3204f;
    static final int DANGER_BG = 0xffffeaf1;
    /** 禁用态。 */
    static final int DISABLED_BG = 0xfff3eef6;
    static final int DISABLED_FG = 0xffa99fb4;

    /** 主按钮渐变：热粉 → 蝶紫。 */
    static final int[] BUTTON = {0xfff04c8a, 0xffa44be0};
    /** 主按钮按下时的水波纹。 */
    static final int RIPPLE = 0x40ffffff;
    /** 次级按钮描边色。 */
    static final int GHOST_LINE = 0x40a44be0;

    /** 顶部主视觉：深梅 → 紫罗兰 → 热粉。 */
    static final int[] HERO = {0xff2a1440, 0xff6a2b8f, 0xffe8447f};
    /** 页面默认背景：淡樱花 → 淡丁香。 */
    static final int[] BACKDROP = {0xfffff4f9, 0xfff6f0ff, 0xfffff6fb};
    /** 背景柔光。 */
    static final int GLOW = 0x55ff7ab6;

    /** 状态栏/导航栏占位色：取自 backdrop.png 顶边，保证系统栏与背景无缝。 */
    static final int BAR = 0xfffeddED;    /** 自定义照片时的遮罩基色：深梅而不是深蓝。 */
    static final int SCRIM = Color.rgb(30, 14, 40);

    /** 圆角半径（dp）。 */
    static final int R_CARD = 22, R_BUTTON = 16, R_CHIP = 12, R_PANEL = 14;
    /** 卡片之间统一间距（dp）。 */
    static final int GAP = 14;

    static GradientDrawable gradient(int[] colors, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable(GradientDrawable.Orientation.TL_BR, colors);
        drawable.setCornerRadius(radiusDp);
        return drawable;
    }

    static GradientDrawable gradient(float radiusPx, int[] colors) {
        GradientDrawable drawable = new GradientDrawable(GradientDrawable.Orientation.TL_BR, colors);
        drawable.setCornerRadius(radiusPx);
        return drawable;
    }

    /** 卡片：浅底 + 细粉描边 + 大圆角。 */
    static GradientDrawable card(int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(SURFACE);
        drawable.setCornerRadius(radiusDp);
        drawable.setStroke(1, LINE);
        return drawable;
    }

    /** 纯色圆角块。 */
    static GradientDrawable block(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radiusDp);
        return drawable;
    }
}
