package cn.fpga.score;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Build;
import android.widget.Button;

/** Selected + activated is an unconfirmed draft; selected alone is confirmed. */
final class SegmentButton extends Button {
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private boolean segmented,pending;
    private String caption;
    SegmentButton(Context context){super(context);}
    void pending(boolean value){pending=value;invalidate();}
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private GradientDrawable fill(int color){GradientDrawable drawable=new GradientDrawable();drawable.setColor(color);drawable.setCornerRadius(dp(Theme.R_BUTTON));return drawable;}
    void selection(ControlState.Selection selection){
        if(!segmented){
            segmented=true;caption=getText().toString();setStateListAnimator(null);
            StateListDrawable states=new StateListDrawable();
            states.addState(new int[]{-android.R.attr.state_enabled},fill(Theme.DISABLED_BG));
            GradientDrawable draft=fill(Theme.SURFACE);draft.setStroke(dp(2),Theme.PINK,dp(5),dp(3));
            states.addState(new int[]{android.R.attr.state_enabled,android.R.attr.state_selected,android.R.attr.state_activated},draft);
            GradientDrawable confirmed=new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,Theme.BUTTON);confirmed.setCornerRadius(dp(Theme.R_BUTTON));
            states.addState(new int[]{android.R.attr.state_enabled,android.R.attr.state_selected},confirmed);
            GradientDrawable off=fill(Theme.SURFACE_ALT);off.setStroke(dp(1),Theme.GHOST_LINE);states.addState(new int[]{},off);
            setBackground(new RippleDrawable(ColorStateList.valueOf(Theme.RIPPLE),states,fill(Theme.WHITE)));
            setPadding(dp(12),dp(20),dp(12),dp(10));setMinHeight(dp(62));
        }
        setSelected(selection!=ControlState.Selection.OFF);setActivated(selection==ControlState.Selection.DRAFT);refreshStyle();
    }
    private void refreshStyle(){
        if(!segmented)return;
        setTextColor(!isEnabled()?Theme.DISABLED_FG:!isSelected()?Theme.MUTED:isActivated()?Theme.PINK_INK:Theme.WHITE);
        setTypeface(Typeface.DEFAULT,isSelected()?Typeface.BOLD:Typeface.NORMAL);
        setElevation(isEnabled()&&isSelected()&&!isActivated()?dp(3):0);
        String state=isSelected()?(isActivated()?"待发送草稿":"设备已确认"):"未选中";
        setContentDescription(caption+"，"+state);
        if(Build.VERSION.SDK_INT>=30)setStateDescription(state);invalidate();
    }
    @Override protected void drawableStateChanged(){super.drawableStateChanged();refreshStyle();}
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);
        if(pending){paint.setColor(Theme.PINK);canvas.drawCircle(getWidth()-dp(14),getHeight()/2f,dp(3),paint);}
        if(!segmented||!isSelected())return;
        if(isActivated()){
            paint.setColor(isEnabled()?Theme.PINK_INK:Theme.DISABLED_FG);paint.setTypeface(Typeface.DEFAULT_BOLD);
            paint.setTextSize(10*getResources().getDisplayMetrics().scaledDensity);paint.setTextAlign(Paint.Align.RIGHT);
            canvas.drawText("•待发送",getWidth()-dp(9),dp(14),paint);
        }else{
            paint.setColor(isEnabled()?Theme.WHITE:Theme.DISABLED_FG);
            canvas.drawRoundRect(dp(5),dp(14),dp(8),getHeight()-dp(14),dp(1),dp(1),paint);
        }
    }
}
