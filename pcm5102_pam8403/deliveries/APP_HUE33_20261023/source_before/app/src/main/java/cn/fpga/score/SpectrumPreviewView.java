package cn.fpga.score;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.View;

/** Draws only the FPGA's returned values, with the panel's 16-band grouping. */
final class SpectrumPreviewView extends View {
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private LedFrame frame;
    SpectrumPreviewView(Context context){super(context);setContentDescription("FPGA 实时频谱及触摸、红外手势、吉他幅度预览");}
    void setFrame(LedFrame value){frame=value;invalidate();}
    private float dp(float value){return value*getResources().getDisplayMetrics().density;}
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);
        float w=getWidth(),h=getHeight(),pad=dp(8),meterTop=h-dp(80),bottom=meterTop-dp(12);
        paint.setColor(Theme.SURFACE_ALT);canvas.drawRoundRect(0,0,w,h,dp(12),dp(12),paint);
        if(frame==null){paint.setColor(Theme.MUTED);paint.setTextSize(dp(13));canvas.drawText("开启预览后显示 FPGA 数据",pad,dp(30),paint);return;}
        float slot=(w-2*pad)/16;
        for(int i=0;i<16;i++){
            float left=pad+i*slot,barWidth=Math.max(dp(1),slot-dp(3));
            paint.setColor(0xffded7e7);canvas.drawRect(left,dp(12),left+barWidth,bottom,paint);
            if(frame.spectrumValid()){
                paint.setColor(i<5?0xff299c6b:i<11?0xff159eb0:0xffdc8b28);
                float height=(bottom-dp(12))*frame.level(i)/31f;
                canvas.drawRect(left,bottom-height,left+barWidth,bottom,paint);
            }
        }
        int[] values={frame.touch,frame.sensor,frame.guitar};
        int[] colors={0xff299c6b,0xff159eb0,0xffdc8b28};
        String[] labels={"触摸","红外/手势","吉他"};
        paint.setTextSize(dp(12));
        for(int i=0;i<3;i++){
            float y=meterTop+i*dp(24),left=dp(74),right=w-pad;
            paint.setColor(Theme.MUTED);canvas.drawText(labels[i],pad,y+dp(12),paint);
            paint.setColor(0xffded7e7);canvas.drawRoundRect(left,y+dp(2),right,y+dp(14),dp(4),dp(4),paint);
            paint.setColor(colors[i]);canvas.drawRoundRect(left,y+dp(2),left+(right-left)*values[i]/56f,y+dp(14),dp(4),dp(4),paint);
        }
    }
}
