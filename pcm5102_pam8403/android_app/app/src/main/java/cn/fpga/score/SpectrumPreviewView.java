package cn.fpga.score;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.view.View;

/** Native Canvas instrument: decorative hue legend, real returned amplitudes only. */
final class SpectrumPreviewView extends View {
    private static final int INK=0xffedf3ff,MUTED=0xff98a8c1,GRID=0xff253044,TRACK=0xff1b2537;
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Typeface regular=Typeface.create("sans-serif",Typeface.NORMAL);
    private final Typeface bold=Typeface.create("sans-serif-medium",Typeface.NORMAL);
    private LedFrame frame;
    private LinearGradient hue,meterHue;
    SpectrumPreviewView(Context context){
        super(context);
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
        setFrame(null);
    }
    void setFrame(LedFrame value){
        frame=value;
        setContentDescription(value==null?"音量色环：青、蓝、紫、品红、红。等待 FPGA 实时数据。":
            "FPGA 实时幅度。触摸 "+percent(value.touch,56)+"%，红外手势 "+percent(value.sensor,56)
            +"%，吉他 "+percent(value.guitar,56)+"%。"+(value.spectrumValid()?"频谱已就绪。":"频谱采集中。"));
        invalidate();
    }
    private float dp(float value){return value*getResources().getDisplayMetrics().density;}
    private static int percent(int value,int scale){return (value*100+scale/2)/scale;}
    @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){
        super.onSizeChanged(w,h,oldw,oldh);
        hue=new LinearGradient(dp(18),0,w-dp(18),0,LedHue.colors(),null,Shader.TileMode.CLAMP);
        meterHue=new LinearGradient(dp(86),0,w-dp(55),0,LedHue.colors(),null,Shader.TileMode.CLAMP);
    }
    private void text(Canvas c,String s,float x,float y,int color,float size,boolean strong,Paint.Align align){
        paint.setShader(null);paint.setColor(color);paint.setTextSize(dp(size));
        paint.setTypeface(strong?bold:regular);paint.setTextAlign(align);
        c.drawText(s,x,dp(y),paint);
    }
    @Override protected void onDraw(Canvas c){
        super.onDraw(c);
        float w=getWidth(),h=getHeight(),pad=dp(18),right=w-pad;
        paint.setShader(null);paint.setColor(0xff0c1322);
        c.drawRoundRect(0,0,w,h,dp(18),dp(18),paint);
        text(c,"音量色环",pad,31,INK,19,true,Paint.Align.LEFT);
        text(c,"青 → 蓝 → 紫 → 品红 → 红",pad,51,MUTED,11,false,Paint.Align.LEFT);
        String status=frame==null?"等待数据":frame.spectrumValid()?"LIVE":"采集中";
        int statusColor=frame==null?MUTED:LedHue.color(0);
        paint.setColor(frame==null?0xff1f2a3d:0xff12363e);
        c.drawRoundRect(right-dp(66),dp(16),right,dp(38),dp(11),dp(11),paint);
        text(c,status,right-dp(33),31,statusColor,10,true,Paint.Align.CENTER);
        paint.setShader(hue);
        c.drawRoundRect(pad,dp(68),right,dp(76),dp(4),dp(4),paint);
        paint.setShader(null);
        text(c,"低幅度",pad,94,MUTED,10,false,Paint.Align.LEFT);
        text(c,"高幅度",right,94,MUTED,10,false,Paint.Align.RIGHT);
        text(c,"实时频谱",pad,124,INK,12,true,Paint.Align.LEFT);
        text(c,"16 BANDS",right,124,MUTED,9,false,Paint.Align.RIGHT);
        float top=dp(140),bottom=dp(222),plotHeight=bottom-top;
        paint.setStrokeWidth(dp(1));paint.setColor(GRID);
        for(int i=0;i<3;i++){
            float y=top+plotHeight*i/2;
            c.drawLine(pad,y,right,y,paint);
        }
        if(frame!=null && frame.spectrumValid()){
            float slot=(right-pad)/16,barWidth=slot-dp(4);
            for(int i=0;i<16;i++){
                int level=frame.level(i);
                float left=pad+i*slot+dp(2),height=plotHeight*level/31f;
                if(level==0){
                    paint.setColor(LedHue.SILENT);
                    c.drawRoundRect(left,bottom-dp(2),left+barWidth,bottom,dp(1),dp(1),paint);
                }else{
                    int color=LedHue.amplitudeColor(level,31);
                    paint.setColor((color&0x00ffffff)|0x22000000);
                    c.drawRoundRect(left-dp(1),bottom-height-dp(2),left+barWidth+dp(1),bottom,dp(4),dp(4),paint);
                    paint.setColor(color);
                    c.drawRoundRect(left,bottom-Math.max(dp(3),height),left+barWidth,bottom,dp(3),dp(3),paint);
                }
            }
        }else{
            text(c,frame==null?"开启预览，查看实时频谱":"等待首个完整频谱",w/2,184,MUTED,12,false,Paint.Align.CENTER);
        }
        text(c,"0",pad,240,MUTED,9,false,Paint.Align.LEFT);
        text(c,"1.5",w/2,240,MUTED,9,false,Paint.Align.CENTER);
        text(c,"3.05 kHz",right,240,MUTED,9,false,Paint.Align.RIGHT);
        paint.setColor(GRID);c.drawLine(pad,dp(254),right,dp(254),paint);
        String[] labels={"触摸","红外/手势","吉他"};
        int[] values=frame==null?null:new int[]{frame.touch,frame.sensor,frame.guitar};
        float meterLeft=pad+dp(68),meterRight=right-dp(37);
        for(int i=0;i<3;i++){
            float y=277+i*29;
            text(c,labels[i],pad,y,MUTED,11,false,Paint.Align.LEFT);
            text(c,values==null?"—":percent(values[i],56)+"%",right,y,INK,10,true,Paint.Align.RIGHT);
            paint.setColor(TRACK);
            c.drawRoundRect(meterLeft,dp(y-8),meterRight,dp(y-1),dp(3.5f),dp(3.5f),paint);
            if(values!=null && values[i]>0){
                // Reveal the real level on a fixed, full-range hue scale.
                c.save();
                c.clipRect(meterLeft,dp(y-8),meterLeft+(meterRight-meterLeft)*values[i]/56f,dp(y-1));
                paint.setShader(meterHue);
                c.drawRoundRect(meterLeft,dp(y-8),meterRight,dp(y-1),dp(3.5f),dp(3.5f),paint);
                c.restore();paint.setShader(null);
            }
        }
    }
}
