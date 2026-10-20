package cn.fpga.score;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;

/**
 * 读取打包在 assets/ 里的主题素材。
 *
 * 这些图由 design/draw_assets.py 以 1080x2400 为基准绘制，属于原创几何插画，
 * 不含任何外部图片素材。解码结果按名称缓存，避免 Activity 重建时反复读盘。
 */
final class ArtAssets {
    /** 素材设计基准宽度，用来换算缩放比例，保证在任何屏幕宽度下印刷尺寸一致。 */
    static final float DESIGN_WIDTH = 1080f;

    private static final LruCache<String, Bitmap> CACHE = new LruCache<>(4);

    private ArtAssets() { }

    /** 按名称加载素材；缺失或解码失败返回 null，调用方应退回到纯色/自绘方案。 */
    static Bitmap load(Context context, String name) {
        Bitmap cached = CACHE.get(name);
        if (cached != null && !cached.isRecycled()) return cached;
        try {
            Bitmap bitmap = BitmapFactory.decodeStream(context.getAssets().open(name + ".png"));
            if (bitmap != null) CACHE.put(name, bitmap);
            return bitmap;
        } catch (java.io.IOException error) {
            return null;
        }
    }

    /** 素材像素 → 屏幕像素的缩放比。 */
    static float scale(Context context) {
        return context.getResources().getDisplayMetrics().widthPixels / DESIGN_WIDTH;
    }
}
