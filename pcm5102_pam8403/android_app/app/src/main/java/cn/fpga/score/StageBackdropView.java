package cn.fpga.score;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.view.View;

/**
 * 默认的「舞台夜色」背景。
 *
 * 优先显示打包的 backdrop.png（原创插画）；素材缺失时退回本类自绘的
 * 渐变 + 柔光 + 波点，保证任何情况下都有背景。
 */
final class StageBackdropView extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint imagePaint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private Bitmap art;
    private Bitmap cache;

    StageBackdropView(Context context) {
        super(context);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    /** 设置已有的素材位图；为 null 时使用自绘风格。 */
    void setArt(Bitmap bitmap) {
        art = bitmap;
        recycleCache();
        invalidate();
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (art != null && !art.isRecycled()) {
            // 铺满屏幕并居中裁剪，保持素材比例。
            float scale = Math.max(getWidth() / (float) art.getWidth(),
                    getHeight() / (float) art.getHeight());
            float dx = (getWidth() - art.getWidth() * scale) * 0.5f;
            float dy = (getHeight() - art.getHeight() * scale) * 0.5f;
            canvas.save();
            canvas.translate(dx, dy);
            canvas.scale(scale, scale);
            canvas.drawBitmap(art, 0, 0, imagePaint);
            canvas.restore();
            return;
        }
        if (cache != null && !cache.isRecycled()) canvas.drawBitmap(cache, 0, 0, null);
    }

    @Override protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        recycleCache();
        if (width <= 0 || height <= 0) return;
        cache = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(cache);
        float w = width, h = height, unit = getResources().getDisplayMetrics().density;

        // 1) 底色：淡樱花 → 淡丁香 → 淡粉，竖向缓慢过渡。
        paint.setShader(new LinearGradient(0, 0, w * 0.25f, h,
                Theme.BACKDROP, new float[]{0f, 0.55f, 1f}, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, w, h, paint);

        // 2) 顶部柔光：模拟舞台顶灯打下来的一团暖粉。
        paint.setShader(new RadialGradient(w * 0.82f, -h * 0.12f, Math.max(w, h) * 0.72f,
                new int[]{Theme.GLOW, 0x00ff7ab6}, new float[]{0f, 1f}, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, w, h, paint);

        // 3) 波点律动：圆点越往下越大越淡，在边缘自然消失，形成节奏渐变。
        paint.setShader(null);
        paint.setStyle(Paint.Style.FILL);
        float step = (11f + h * 0.008f) * unit;
        int cols = (int) Math.ceil(w / step) + 1;
        int rows = (int) Math.ceil(h / step) + 1;
        for (int row = 0; row < rows; row++) {
            for (int col = 0; col < cols; col++) {
                float x = col * step + (row % 2 == 0 ? 0 : step * 0.5f);
                float y = row * step;
                if (x > w + step) continue;
                float depth = y / Math.max(1f, h);
                if (depth > 0.72f) continue;
                float radius = (1.1f + depth * 3.4f) * unit;
                int alpha = (int) (26 * (1f - depth / 0.72f));
                if (alpha <= 0) continue;
                paint.setColor((alpha << 24) | 0x00e8447f);
                canvas.drawCircle(x, y, radius, paint);
            }
        }
        paint.setShader(null);
    }

    @Override protected void onDetachedFromWindow() {
        recycleCache();
        super.onDetachedFromWindow();
    }

    private void recycleCache() {
        if (cache != null && !cache.isRecycled()) cache.recycle();
        cache = null;
    }
}
