package cn.fpga.score;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.AtomicFile;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicInteger;

/** Owns photo decoding and appearance settings independently of Bluetooth work. */
final class AppearanceController {
    private static final int PICK_BACKGROUND = 40;
    private static final int DEFAULT_OVERLAY = 18;
    private static final int MAX_EDGE = 2048;
    private static final double MAX_PIXELS = 4000000.0;
    // Old and recreated Activities can briefly have live image workers together.
    private static final Object FILE_LOCK = new Object();
    private final Object stateLock = new Object();
    private final Activity activity;
    private final ImageView photo;
    private final View scrim;
    private final SharedPreferences preferences;
    private final AtomicFile storedPhoto;
    private final ExecutorService images = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final AtomicInteger revision = new AtomicInteger();
    private volatile boolean closed;
    private int overlay;
    private boolean customPhoto;
    private AlertDialog settings;
    private TextView photoState;
    private Button chooseButton;

    AppearanceController(Activity activity, FrameLayout root) {
        this.activity = activity;
        preferences = activity.getSharedPreferences("appearance", Activity.MODE_PRIVATE);
        storedPhoto = new AtomicFile(new File(activity.getFilesDir(), "background-photo.png"));
        overlay = Math.max(0, Math.min(80, preferences.getInt("overlay_percent", DEFAULT_OVERLAY)));
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[]{Color.rgb(229, 242, 255), Color.rgb(241, 235, 255), Color.rgb(225, 244, 246)}));
        photo = new ImageView(activity);
        photo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        photo.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        root.addView(photo, fullScreen());
        scrim = new View(activity);
        scrim.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        root.addView(scrim, fullScreen());
        updateScrim();
        restorePhoto();
    }

    private FrameLayout.LayoutParams fullScreen() {
        return new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT);
    }

    void showSettings() {
        if (closed || activity.isFinishing()) return;
        if (settings != null && settings.isShowing()) return;
        LinearLayout box = new LinearLayout(activity);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(24), dp(4), dp(24), dp(10));
        TextView intro = label("把喜欢的照片设为背景，打造自己的演奏空间。", 14,
                Color.rgb(85, 98, 120));
        box.addView(intro);
        photoState = label(customPhoto ? "当前：自定义照片" : "当前：默认渐变背景", 13,
                Color.rgb(76, 89, 176));
        box.addView(photoState);
        chooseButton = new Button(activity);
        chooseButton.setText("选择背景照片");
        chooseButton.setAllCaps(false);
        chooseButton.setTextColor(Color.WHITE);
        chooseButton.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Color.rgb(82, 100, 206)));
        chooseButton.setMinHeight(dp(52));
        box.addView(chooseButton, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        chooseButton.setOnClickListener(v -> pickPhoto());
        TextView heading = label("背景遮罩", 15, Color.rgb(35, 49, 76));
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.setPadding(0, dp(18), 0, dp(4));
        box.addView(heading);
        TextView value = label(overlayText(), 13, Color.rgb(85, 98, 120));
        box.addView(value);
        SeekBar shade = new SeekBar(activity);
        shade.setMax(80);
        shade.setProgress(overlay);
        shade.setContentDescription("背景深色遮罩百分比，0 到 80");
        shade.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.rgb(82, 100, 206)));
        shade.setThumbTintList(android.content.res.ColorStateList.valueOf(Color.rgb(82, 100, 206)));
        box.addView(shade, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)));
        shade.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                overlay = progress;
                updateScrim();
                value.setText(overlayText());
                if (fromUser) preferences.edit().putInt("overlay_percent", overlay).apply();
            }
            @Override public void onStartTrackingTouch(SeekBar bar) { }
            @Override public void onStopTrackingTouch(SeekBar bar) { }
        });
        TextView hint = label("向右调暗背景。照片居中铺满，超出屏幕的边缘会裁切。\n照片会保存到 App 内，重启后自动恢复。", 12,
                Color.rgb(108, 119, 138));
        box.addView(hint);
        ScrollView scroll = new ScrollView(activity);
        scroll.addView(box);
        settings = new AlertDialog.Builder(activity).setTitle("外观设置").setView(scroll)
                .setNegativeButton("恢复默认", (dialog, which) -> {
                    resetPhoto();
                    shade.setProgress(DEFAULT_OVERLAY);
                })
                .setPositiveButton("完成", null).create();
        settings.setOnDismissListener(dialog -> {
            settings = null;
            photoState = null;
            chooseButton = null;
        });
        settings.show();
    }

    private void pickPhoto() {
        if (closed) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("image/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            activity.startActivityForResult(intent, PICK_BACKGROUND);
        } catch (ActivityNotFoundException | SecurityException error) {
            message("无法打开照片选择器，请检查系统文件应用是否可用。");
        }
    }

    boolean onActivityResult(int request, int result, Intent data) {
        if (request != PICK_BACKGROUND) return false;
        if (closed || result != Activity.RESULT_OK || data == null || data.getData() == null) return true;
        final Uri uri = data.getData();
        final int version = nextRevision();
        setLoading(true);
        message("正在准备背景照片…");
        submit(() -> {
            Bitmap bitmap = null;
            try {
                bitmap = decode(ImageDecoder.createSource(activity.getContentResolver(), uri));
                if (!current(version)) { bitmap.recycle(); return; }
                if (!savePhoto(bitmap, version)) { bitmap.recycle(); return; }
                if (!current(version)) { bitmap.recycle(); return; }
                final Bitmap ready = bitmap;
                main.post(() -> {
                    if (!current(version)) { ready.recycle(); return; }
                    photo.setImageBitmap(ready);
                    customPhoto = true;
                    setLoading(false);
                    message("背景已更新，并保存到本机。");
                });
            } catch (IOException | RuntimeException error) {
                if (bitmap != null) bitmap.recycle();
                reportFailure(version, "照片无法使用，请选择完整的静态图片。原背景已保留。");
            } catch (OutOfMemoryError error) {
                if (bitmap != null) bitmap.recycle();
                reportFailure(version, "手机内存不足，请尝试较小的照片。原背景已保留。");
            }
        });
        return true;
    }

    private void restorePhoto() {
        final int version = revision.get();
        submit(() -> {
            Bitmap bitmap = null;
            try {
                synchronized (FILE_LOCK) {
                    if (!current(version) || !preferences.getBoolean("photo_enabled", false)) return;
                    // openRead also recovers an interrupted AtomicFile replacement.
                    try (FileInputStream ignored = storedPhoto.openRead()) { }
                    bitmap = decode(ImageDecoder.createSource(storedPhoto.getBaseFile()));
                }
                final Bitmap ready = bitmap;
                main.post(() -> {
                    if (!current(version)) { ready.recycle(); return; }
                    photo.setImageBitmap(ready);
                    customPhoto = true;
                    setLoading(false);
                });
            } catch (IOException | RuntimeException error) {
                if (bitmap != null) bitmap.recycle();
                if (storedPhoto.getBaseFile().exists())
                    reportFailure(version, "保存的背景暂时无法读取，已显示默认渐变。可重新选择照片。");
            } catch (OutOfMemoryError error) {
                if (bitmap != null) bitmap.recycle();
                reportFailure(version, "背景照片暂时无法加载，已显示默认渐变。");
            }
        });
    }

    private Bitmap decode(ImageDecoder.Source source) throws IOException {
        return ImageDecoder.decodeBitmap(source, (decoder, info, ignored) -> {
            if (info.isAnimated()) throw new IllegalArgumentException("Animated images are unsupported");
            int width = info.getSize().getWidth(), height = info.getSize().getHeight();
            if (width < 1 || height < 1) throw new IllegalArgumentException("Invalid image dimensions");
            double scale = Math.min(1.0, Math.min(MAX_EDGE / (double)Math.max(width, height),
                    Math.sqrt(MAX_PIXELS / ((double)width * height))));
            decoder.setTargetSize(Math.max(1, (int)(width * scale)), Math.max(1, (int)(height * scale)));
            decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB));
            decoder.setOnPartialImageListener(error -> false);
        });
    }

    private boolean savePhoto(Bitmap bitmap, int version) throws IOException {
        synchronized (FILE_LOCK) {
            if (!current(version)) return false;
            FileOutputStream stream = null;
            try {
                stream = storedPhoto.startWrite();
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) throw new IOException("Image encoding failed");
                stream.flush();
                synchronized (stateLock) {
                    if (!current(version)) { storedPhoto.failWrite(stream); return false; }
                    storedPhoto.finishWrite(stream);
                    stream = null;
                    preferences.edit().putBoolean("photo_enabled", true).apply();
                }
                return true;
            } catch (IOException | RuntimeException | OutOfMemoryError error) {
                if (stream != null) storedPhoto.failWrite(stream);
                throw error;
            }
        }
    }

    private void resetPhoto() {
        final int version = nextRevision();
        photo.setImageDrawable(null);
        customPhoto = false;
        overlay = DEFAULT_OVERLAY;
        preferences.edit().putInt("overlay_percent", overlay).putBoolean("photo_enabled", false).apply();
        updateScrim();
        setLoading(false);
        // All disk work is serialized, so an older import cannot overwrite a reset.
        submit(() -> { synchronized (FILE_LOCK) { if (current(version)) storedPhoto.delete(); } });
        message("已恢复默认渐变背景。");
    }

    private void updateScrim() {
        scrim.setBackgroundColor(Color.argb(Math.round(overlay * 255f / 100f), 7, 17, 37));
    }

    private void setLoading(boolean loading) {
        if (chooseButton != null) {
            chooseButton.setEnabled(!loading);
            chooseButton.setText(loading ? "正在准备照片…" : "选择背景照片");
        }
        if (photoState != null) photoState.setText(loading ? "正在处理图片，完成后自动保存" :
                customPhoto ? "当前：自定义照片" : "当前：默认渐变背景");
    }

    private String overlayText() { return "深色遮罩 " + overlay + "% · 拖动可实时预览"; }
    private int nextRevision() { synchronized (stateLock) { return revision.incrementAndGet(); } }
    private boolean current(int version) { return !closed && revision.get() == version; }
    private void reportFailure(int version, String detail) {
        main.post(() -> {
            if (!current(version)) return;
            setLoading(false);
            message(detail);
        });
    }
    private void submit(Runnable work) {
        if (closed) return;
        try { images.execute(work); } catch (RejectedExecutionException ignored) { }
    }
    private int dp(int size) { return Math.round(size * activity.getResources().getDisplayMetrics().density); }
    private TextView label(String value, int size, int color) {
        TextView text = new TextView(activity);
        text.setText(value);
        text.setTextSize(size);
        text.setTextColor(color);
        text.setPadding(0, dp(5), 0, dp(7));
        return text;
    }
    private void message(String value) {
        if (!closed && !activity.isFinishing() && !activity.isDestroyed())
            Toast.makeText(activity, value, Toast.LENGTH_LONG).show();
    }

    void close() {
        synchronized (stateLock) {
            closed = true;
            revision.incrementAndGet();
        }
        images.shutdownNow();
        main.removeCallbacksAndMessages(null);
        if (settings != null) settings.dismiss();
        photo.setImageDrawable(null);
    }
}
