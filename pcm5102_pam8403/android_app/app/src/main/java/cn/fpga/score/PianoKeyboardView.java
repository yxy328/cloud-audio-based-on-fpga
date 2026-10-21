package cn.fpga.score;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;

final class PianoKeyboardView extends FrameLayout {
    interface Listener {void key(int scanIndex,boolean down);}
    private final Button[] keys=new Button[16];
    private final int highestNote;
    private final Listener listener;
    PianoKeyboardView(Context context,int highestNote,Listener listener){
        super(context);this.highestNote=highestNote;this.listener=listener;setMotionEventSplittingEnabled(true);
        for(int key=0;key<16;key++)if(!ChromaticKeys.black(key))addKey(key);
        for(int key=0;key<12;key++)if(ChromaticKeys.black(key))addKey(key);
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private GradientDrawable fill(int color,int line){GradientDrawable bg=new GradientDrawable();bg.setColor(color);bg.setCornerRadius(dp(5));bg.setStroke(dp(1),line);return bg;}
    private void addKey(int key){
        boolean black=ChromaticKeys.black(key),pedal=key>=12;
        int ink=black?Theme.WHITE:Theme.INK,base=black?Theme.PIANO_BLACK:Theme.WHITE;
        Button button=new Button(getContext());keys[key]=button;button.setAllCaps(false);button.setTextSize(10);button.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        button.setText((pedal?"条"+(key-11)+" ":"")+ChromaticKeys.name(ChromaticKeys.note(key))+"\nK"+(key+1));
        button.setGravity(pedal?Gravity.CENTER:Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);button.setPadding(dp(1),dp(3),dp(1),dp(8));button.setMinWidth(0);button.setMinimumWidth(0);button.setMinHeight(0);button.setMinimumHeight(0);button.setStateListAnimator(null);
        StateListDrawable states=new StateListDrawable();states.addState(new int[]{-android.R.attr.state_enabled},fill(Theme.DISABLED_BG,Theme.GHOST_LINE));
        states.addState(new int[]{android.R.attr.state_pressed},fill(Theme.PINK,Theme.PINK));
        GradientDrawable selected=fill(base,Theme.PINK);selected.setStroke(dp(2),Theme.PINK);states.addState(new int[]{android.R.attr.state_selected},selected);
        states.addState(new int[]{},fill(base,Theme.GHOST_LINE));button.setBackground(new RippleDrawable(ColorStateList.valueOf(Theme.RIPPLE),states,null));
        button.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{Theme.DISABLED_FG,ink}));
        button.setContentDescription("扫描 K"+(key+1)+"，"+ChromaticKeys.name(ChromaticKeys.note(key))+(pedal?"，踏板条"+(key-11)+"暂作普通高音键":""));
        button.setEnabled(ChromaticKeys.note(key)<=highestNote);
        button.setOnTouchListener((view,event)->{
            if(event.getActionMasked()==MotionEvent.ACTION_DOWN){listener.key(key,true);button.setPressed(true);return true;}
            if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){listener.key(key,false);button.setPressed(false);return true;}return true;
        });
        button.setOnClickListener(view->{listener.key(key,true);button.postDelayed(()->listener.key(key,false),150);});
        addView(button,new FrameLayout.LayoutParams(0,0));
    }
    @Override protected void onMeasure(int widthSpec,int heightSpec){
        int width=MeasureSpec.getSize(widthSpec),height=resolveSize(dp(180),heightSpec);setMeasuredDimension(width,height);
        int piano=(width-dp(12))*4/5,pedalLeft=piano+dp(12);
        for(int key=0;key<16;key++){
            int keyWidth=key<12?piano*(ChromaticKeys.black(key)?6:10)/70:width-pedalLeft;
            int keyHeight=key<12?(ChromaticKeys.black(key)?height*3/5:height):height/4-dp(3);
            keys[key].measure(MeasureSpec.makeMeasureSpec(Math.max(1,keyWidth-dp(1)),MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(Math.max(1,keyHeight),MeasureSpec.EXACTLY));
        }
    }
    @Override protected void onLayout(boolean changed,int left,int top,int right,int bottom){
        int piano=(getMeasuredWidth()-dp(12))*4/5;
        for(int key=0;key<16;key++){int x=key<12?piano*ChromaticKeys.xTenths(key)/70:piano+dp(12),y=key<12?0:(key-12)*getMeasuredHeight()/4;
            keys[key].layout(x,y,x+keys[key].getMeasuredWidth(),y+keys[key].getMeasuredHeight());}
    }
    void highlight(int note){for(int key=0;key<16;key++)keys[key].setSelected(ChromaticKeys.note(key)==note);}
    @Override public void setEnabled(boolean enabled){super.setEnabled(enabled);if(keys!=null)for(int key=0;key<16;key++)if(keys[key]!=null)keys[key].setEnabled(enabled&&ChromaticKeys.note(key)<=highestNote);}
}
