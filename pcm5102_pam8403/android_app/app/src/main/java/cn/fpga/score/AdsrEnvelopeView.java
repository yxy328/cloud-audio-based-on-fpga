package cn.fpga.score;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.MotionEvent;
import android.view.View;

/** Draft envelope editor. The horizontal sustain span is only a preview. */
public final class AdsrEnvelopeView extends View {
    public interface Listener {void changed(AdsrProfile value);}
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private AdsrProfile value=new AdsrProfile(10,80,60,200);
    private Listener listener;
    private int dragging=-1;
    private float dragAxis;
    private static final int HOLD=300;
    public AdsrEnvelopeView(Context context){super(context);setContentDescription("ADSR 包络预览，可拖动起音、衰减、保持音量与释音控制点");setFocusable(true);}
    public void setProfile(AdsrProfile p){value=p;invalidate();}
    public void setListener(Listener l){listener=l;}
    private float dp(float x){return x*getResources().getDisplayMetrics().density;}
    private float axis(){return dragging>=0?dragAxis:Math.max(500,(value.attack+value.decay+HOLD+value.release)*1.25f);}
    private float px(float time){return dp(28)+time/axis()*(getWidth()-dp(48));}
    private float py(float level){return getHeight()-dp(28)-level*(getHeight()-dp(52));}
    private float[][] handles(){return new float[][]{{px(value.attack),py(1)},
        {px(value.attack+value.decay),py(value.sustain/100f)},
        {px(value.attack+value.decay+HOLD/2f),py(value.sustain/100f)},
        {px(value.attack+value.decay+HOLD+value.release),py(0)}};}
    @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);
        paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(1));paint.setColor(0x22e8447f);
        for(int i=0;i<=4;i++)canvas.drawLine(dp(28),py(i/4f),getWidth()-dp(20),py(i/4f),paint);
        Path line=new Path();float[][] points=value.points(HOLD);
        line.moveTo(px(points[0][0]),py(points[0][1]));
        for(int i=1;i<points.length;i++)line.lineTo(px(points[i][0]),py(points[i][1]));
        // 曲线本体用霓虹粉，与主按钮同一家族。
        paint.setColor(Theme.PINK);paint.setStrokeWidth(dp(3));canvas.drawPath(line,paint);
        paint.setStyle(Paint.Style.FILL);float[][] handles=handles();
        for(int i=0;i<handles.length;i++){
            paint.setColor(i==dragging?Theme.CYAN:Theme.PINK);canvas.drawCircle(handles[i][0],handles[i][1],dp(6),paint);
        }
        paint.setColor(Theme.MUTED);paint.setTextSize(dp(11));
        canvas.drawText("100%",0,dp(14),paint);canvas.drawText("0%",0,py(0)+dp(4),paint);
        canvas.drawText("保持段为示意，S 是音量",dp(28),getHeight()-dp(7),paint);
    }
    private int limit(float x,int max){return Math.max(0,Math.min(max,Math.round(x)));}
    @Override public boolean onTouchEvent(MotionEvent event){
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN){
            float[][] h=handles();float best=dp(28)*dp(28);int found=-1;
            for(int i=0;i<h.length;i++){float x=event.getX()-h[i][0],y=event.getY()-h[i][1],dist=x*x+y*y;if(dist<best){best=dist;found=i;}}
            if(found<0)return false;
            dragAxis=axis();dragging=found;
            if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(true);
            invalidate();return true;
        }
        if(dragging<0)return false;
        if(event.getActionMasked()==MotionEvent.ACTION_MOVE){
            float time=(event.getX()-dp(28))/Math.max(1,getWidth()-dp(48))*dragAxis;
            int s=limit((getHeight()-dp(28)-event.getY())/Math.max(1,getHeight()-dp(52))*100,100);
            value=value.drag(dragging,time,s,HOLD);
            if(listener!=null)listener.changed(value);invalidate();return true;
        }
        if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){
            dragging=-1;if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(false);
            invalidate();if(event.getActionMasked()==MotionEvent.ACTION_UP)performClick();return true;
        }
        return true;
    }
    @Override public boolean performClick(){super.performClick();return true;}
}
