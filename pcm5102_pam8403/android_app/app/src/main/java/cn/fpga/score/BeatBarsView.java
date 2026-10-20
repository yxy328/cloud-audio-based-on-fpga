package cn.fpga.score;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Shader;
import android.view.View;

/**
 * 一排静态的律动波形，用作标题旁的小标记（不用图片、不动画，省电省心）。
 */
final class BeatBarsView extends View {
    private static final float[] LEVELS = {0.42f, 0.78f, 1f, 0.62f, 0.86f, 0.5f, 0.72f, 0.34f};
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

    BeatBarsView(Context context) {
        super(context);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float w = getWidth(), h = getHeight();
        if (w <= 0 || h <= 0) return;
        paint.setShader(new LinearGradient(0, 0, 0, h, 0xfffff4f8, 0xff7ef0ff, Shader.TileMode.CLAMP));
        int count = LEVELS.length;
        float slot = w / count;
        float bar = slot * 0.54f;
        for (int i = 0; i < count; i++) {
            float level = LEVELS[i];
            float barHeight = Math.max(h * 0.16f, h * level);
            float left = i * slot + (slot - bar) * 0.5f;
            float top = (h - barHeight) * 0.5f;
            canvas.drawRoundRect(left, top, left + bar, top + barHeight, bar * 0.5f, bar * 0.5f, paint);
        }
        paint.setShader(null);
    }
}
