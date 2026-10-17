package cn.fpga.score;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.database.Cursor;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public final class MainActivity extends Activity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private SppLink link;
    private BluetoothAdapter adapter;
    private TextView status,scoreInfo,mapInfo,logs;
    private ProgressBar progress;
    private Spinner devices,gestureTone,gestureVibrato,gestureBank;
    private EditText mappingInput;
    private Spinner adsrTarget;
    private final SeekBar[] adsrBars=new SeekBar[4];
    private final TextView[] adsrLabels=new TextView[4];
    private final AdsrProfile[] adsrDrafts={new AdsrProfile(2,80,60,10),new AdsrProfile(10,80,60,200)};
    private AdsrEnvelopeView adsrCurve;
    private boolean loadingAdsr;
    private final VoiceBend voiceBend=new VoiceBend();
    private final SeekBar[] bendBars=new SeekBar[7];
    private final TextView[] bendLabels=new TextView[7];
    private final Integer[] bendConfirmed=new Integer[7];
    private boolean bendScheduled;
    private AppearanceController appearance;
    private static final int INK=0xff1c2c48,MUTED=0xff63728a,ACCENT=0xff5368df;
    private final List<BluetoothDevice> paired=new ArrayList<>();
    private final List<Button> lockedButtons=new ArrayList<>();
    private SongCodec.Song song=SongCodec.twinkle();
    private volatile boolean busy,cancelled,recording,recordDraining;
    private int[] mapping;
    private final StringBuilder logText=new StringBuilder();
    private final StringBuilder recordingText=new StringBuilder();
    private boolean recordingOverflow;
    private boolean recordingCompleted;
    private static final int PICK_SCORE=10,EXPORT_LOG=11,PERMISSION=12;
    @Override public void onCreate(Bundle state){super.onCreate(state);
        link=new SppLink(new SppLink.Listener(){public void line(String line){main.post(()->receive(line));}public void disconnected(String reason){main.post(()->{forgetBendConnection();mapping=null;recordingInterrupted();mapInfo.setText("键位未知，请重新连接");setStatus("蓝牙断开："+reason);});}});
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);adapter=manager==null?null:manager.getAdapter();
        buildUi();showSong();setStatus("先在系统蓝牙设置配对 HC-05，再刷新设备");
        if(hasBluetoothPermission())refreshDevices();
    }
    private int dp(int n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private GradientDrawable rounded(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private TextView text(LinearLayout box,String value,int sp,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(sp);t.setTextColor(color);t.setPadding(0,dp(4),0,dp(6));t.setLineSpacing(dp(3),1);if(sp>=18)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);box.addView(t);return t;}
    private LinearLayout row(LinearLayout box){LinearLayout r=new LinearLayout(this);r.setOrientation(LinearLayout.HORIZONTAL);box.addView(r,new LinearLayout.LayoutParams(-1,-2));return r;}
    private Button button(LinearLayout box,String value,Runnable action,boolean lock){return button(box,value,action,lock,0);}
    // 0: soft secondary, 1: primary, 2: destructive/cancel.
    private Button button(LinearLayout box,String value,Runnable action,boolean lock,int style){
        Button b=new Button(this);b.setText(value);b.setTextSize(14);b.setAllCaps(false);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setMinHeight(dp(50));b.setMinimumHeight(dp(50));b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(12),dp(10),dp(12),dp(10));
        int fill=style==1?ACCENT:style==2?0xfffff0f1:0xffedf1fc,fg=style==1?Color.WHITE:style==2?0xffb34755:ACCENT;
        android.graphics.drawable.StateListDrawable states=new android.graphics.drawable.StateListDrawable();states.addState(new int[]{-android.R.attr.state_enabled},rounded(0xffeef0f5,14));states.addState(new int[]{},rounded(fill,14));
        b.setBackgroundTintList(null);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x225368df),states,rounded(Color.WHITE,14)));b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{0xff9ba5b6,fg}));b.setElevation(0);b.setStateListAnimator(null);
        boolean horizontal=box.getOrientation()==LinearLayout.HORIZONTAL;LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(horizontal?0:-1,-2,horizontal?1:0);lp.setMargins(horizontal?dp(3):0,dp(5),horizontal?dp(3):0,dp(5));box.addView(b,lp);b.setOnClickListener(v->action.run());if(lock)lockedButtons.add(b);return b;
    }
    private LinearLayout card(LinearLayout parent,String number,String title,String hint){
        LinearLayout card=new LinearLayout(this);card.setOrientation(LinearLayout.VERTICAL);card.setPadding(dp(18),dp(17),dp(18),dp(17));GradientDrawable bg=rounded(0xf5ffffff,22);bg.setStroke(dp(1),0xaaffffff);card.setBackground(bg);card.setElevation(dp(2));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(16);parent.addView(card,lp);
        LinearLayout heading=row(card);heading.setGravity(Gravity.CENTER_VERTICAL);TextView badge=new TextView(this);badge.setText(number);badge.setGravity(Gravity.CENTER);badge.setTextSize(13);badge.setTextColor(ACCENT);badge.setTypeface(Typeface.DEFAULT,Typeface.BOLD);badge.setBackground(rounded(0xffedf1fc,10));heading.addView(badge,new LinearLayout.LayoutParams(dp(32),dp(32)));
        TextView label=new TextView(this);label.setText(title);label.setTextSize(19);label.setTextColor(INK);label.setTypeface(Typeface.DEFAULT,Typeface.BOLD);LinearLayout.LayoutParams labelLp=new LinearLayout.LayoutParams(0,-2,1);labelLp.leftMargin=dp(10);heading.addView(label,labelLp);if(hint!=null)text(card,hint,13,MUTED);return card;
    }
    private void addSpinner(LinearLayout box,Spinner spinner){spinner.setMinimumHeight(dp(54));spinner.setBackgroundTintList(ColorStateList.valueOf(ACCENT));box.addView(spinner,new LinearLayout.LayoutParams(-1,-2));}
    private ArrayAdapter<String> options(List<String> values){return new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,values){
        private View decorate(View v){if(v instanceof TextView){TextView t=(TextView)v;t.setTextColor(INK);t.setTextSize(14);t.setSingleLine(false);t.setMaxLines(2);t.setMinHeight(dp(52));t.setGravity(Gravity.CENTER_VERTICAL);t.setPadding(dp(12),dp(9),dp(12),dp(9));}return v;}
        @Override public View getView(int position,View convert,ViewGroup parent){return decorate(super.getView(position,convert,parent));}
        @Override public View getDropDownView(int position,View convert,ViewGroup parent){View v=decorate(super.getDropDownView(position,convert,parent));v.setBackgroundColor(Color.WHITE);return v;}
    };}
    private void buildUi(){
        FrameLayout root=new FrameLayout(this);appearance=new AppearanceController(this,root);
        getWindow().setStatusBarColor(Color.TRANSPARENT);getWindow().setNavigationBarColor(Color.TRANSPARENT);getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.setVerticalScrollBarEnabled(false);root.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
        // Android 15 draws system icons over the app; protect them from dark photos.
        View topBar=new View(this),bottomBar=new View(this);topBar.setBackgroundColor(0xffedf1fa);bottomBar.setBackgroundColor(0xffedf1fa);topBar.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);bottomBar.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        FrameLayout.LayoutParams topBarLp=new FrameLayout.LayoutParams(-1,0,Gravity.TOP),bottomBarLp=new FrameLayout.LayoutParams(-1,0,Gravity.BOTTOM);root.addView(topBar,topBarLp);root.addView(bottomBar,bottomBarLp);
        scroll.setOnApplyWindowInsetsListener((v,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()|WindowInsets.Type.ime());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);topBarLp.height=bars.top;bottomBarLp.height=bars.bottom;}
            else{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());topBarLp.height=insets.getSystemWindowInsetTop();bottomBarLp.height=insets.getSystemWindowInsetBottom();}
            topBar.setLayoutParams(topBarLp);bottomBar.setLayoutParams(bottomBarLp);return insets;
        });
        LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(18),dp(18),dp(18),dp(24));scroll.addView(content);setContentView(root);scroll.requestApplyInsets();
        LinearLayout hero=new LinearLayout(this);hero.setOrientation(LinearLayout.VERTICAL);hero.setPadding(dp(22),dp(22),dp(22),dp(20));GradientDrawable heroBg=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff20315b,0xff4b58a8});heroBg.setCornerRadius(dp(24));hero.setBackground(heroBg);content.addView(hero,new LinearLayout.LayoutParams(-1,-2));
        text(hero,"F P G A   /   M U S I C   L A B",11,0xffc5d1ff);
        text(hero,"FPGA 曲谱助手",28,Color.WHITE);
        text(hero,"让每一次触碰，都有旋律。",15,0xffe1e7ff);
        text(hero,"HC-05 蓝牙连接  ·  HUB75E 屏幕指引\n触摸、手势与单弦吉他，由 FPGA 实时合成。",12,0xffcdd6f3);
        button(content,"外观设置 · 更换背景",()->appearance.showSettings(),false);
        LinearLayout statusBox=new LinearLayout(this);statusBox.setOrientation(LinearLayout.VERTICAL);statusBox.setPadding(dp(17),dp(12),dp(17),dp(12));statusBox.setBackground(rounded(0xf5ffffff,18));LinearLayout.LayoutParams statusLp=new LinearLayout.LayoutParams(-1,-2);statusLp.setMargins(0,dp(8),0,dp(16));content.addView(statusBox,statusLp);text(statusBox,"设备状态",12,MUTED);status=text(statusBox,"",14,ACCENT);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout box=card(content,"01","蓝牙连接","先在系统蓝牙设置中配对 HC-05，再选择设备。");devices=new Spinner(this);devices.setContentDescription("已配对蓝牙设备");addSpinner(box,devices);
        LinearLayout connectionRow=row(box);button(connectionRow,"刷新设备",()->ensurePermission(this::refreshDevices),true);button(connectionRow,"连接设备",()->ensurePermission(this::connectSelected),true,1);
        button(box,"断开 / 取消下载",this::disconnect,false,2);
        box=card(content,"02","曲谱与播放","导入并下载曲谱后，可选择自动演奏或跟随屏幕指引练习。");
        button(box,"载入小星星示例",()->{song=SongCodec.twinkle();showSong();},true);
        button(box,"导入 CSV / MIDI 文件",this::pickScore,true);
        scoreInfo=text(box,"",14,INK);scoreInfo.setPadding(dp(13),dp(12),dp(13),dp(12));scoreInfo.setBackground(rounded(0xfff1f4fb,12));
        button(box,"查看全部音符与休止",this::preview,true);
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(100);progress.setProgressTintList(ColorStateList.valueOf(ACCENT));progress.setProgressBackgroundTintList(ColorStateList.valueOf(0xffe5eafa));progress.setContentDescription("曲谱下载进度");LinearLayout.LayoutParams progressLp=new LinearLayout.LayoutParams(-1,dp(8));progressLp.setMargins(0,dp(10),0,dp(10));box.addView(progress,progressLp);
        button(box,"校验键位并下载 / 重新下载",this::download,true,1);
        text(box,"逐条确认后发送下一条。超时或取消后请重连并从头下载；提交成功前保留板上旧谱。",12,MUTED);
        button(box,"自动演奏 · 已下载曲谱",this::audition,true,1);
        text(box,"下载提交成功后点自动演奏，开发板喇叭会从头播放，无需按触摸键；预备 1.5 秒后发声，结束自动停止。使用当前触摸音色、ADSR 和音高/压力设置，需配套新版 FPGA 位流。",12,MUTED);
        LinearLayout playRow=row(box);button(playRow,"PLAY · 开始指引",()->sendSimple("PLAY","已开始无声指引，预备 1.5 秒后进入首条音符，请按触摸键演奏"),true,1);button(playRow,"STOP · 停止",()->sendSimple("STOP","指引 / 自动演奏已停止，按住的触摸键仍可发声"),true);
        box=card(content,"03","七键音高","按第 1～7 键填写 MIDI 音高，范围 60～72。");
        mapInfo=text(box,"尚未读取键位",14,MUTED);
        button(box,"读取设备键位 MAP?",()->task(()->readMapping(),"键位已读取"),true);
        mappingInput=new EditText(this);mappingInput.setSingleLine(true);mappingInput.setText("60,62,64,65,67,69,71");mappingInput.setTextColor(INK);mappingInput.setTextSize(15);mappingInput.setMinHeight(dp(54));mappingInput.setPadding(dp(12),dp(12),dp(12),dp(12));mappingInput.setBackground(rounded(0xfff1f4fb,12));mappingInput.setContentDescription("第1到第7键的 MIDI 音高，用英文逗号分隔");box.addView(mappingInput,new LinearLayout.LayoutParams(-1,-2));
        button(box,"应用七键映射",this::applyMapping,true,1);
        button(box,"恢复默认映射",()->{if(recording||recordDraining){alert("先停止并等待日志结束，再修改键位");return;}task(()->{link.command("MAP_RESET","OK");readMapping();},"默认映射已恢复");},true);
        box=card(content,"04","红外 / 手势音源与吉他","红外与手势共享 32 复音音源，音色和颤音同时生效；音符组仅作用于手势。");
        gestureTone=choices(box,"红外 / 手势音色",new String[]{"正弦","钢琴","长笛","尤克里里","鼓"});
        button(box,"应用音源音色",()->{int value=gestureTone.getSelectedItemPosition();sendSimple("TONE,"+value,"红外 / 手势音色已确认："+gestureTone.getSelectedItem());},true);
        gestureVibrato=choices(box,"红外 / 手势颤音",new String[]{"关闭","开启"});
        button(box,"应用音源颤音",()->{int value=gestureVibrato.getSelectedItemPosition();sendSimple("VIBRATO,"+value,"红外 / 手势颤音已确认："+gestureVibrato.getSelectedItem());},true);
        gestureBank=choices(box,"手势音符组",new String[]{"低音组 C4～F4","高音组 G4～C5"});
        button(box,"应用手势音符组",()->{int value=gestureBank.getSelectedItemPosition();sendSimple("BANK,"+value,"手势音符组已确认："+gestureBank.getSelectedItem());},true);
        button(box,"GUITAR · 单弦拨弦一次",()->sendSimple("GUITAR","单弦吉他拨弦命令已确认"),true,1);
        button(box,"TEST32 · 32 路频谱验证",()->sendSimple("TEST32","已触发 32 路不同频率正弦，约 2.7 秒；颤音关闭"),true);
        text(box,"选择后点击应用，收到 OK 才生效；列表显示待发送值。吉他每点一次拨弦一次，无需手势传感器就绪。不改变触摸键或曲谱指引。板上 S1 开始/停止，S2 从头重启。",12,MUTED);
        buildAdsrControls(content);
        buildBendControls(content);
        box=card(content,"07","演奏事件日志","记录触摸键与压力事件，保存为文本供检查与重放。");
        button(box,"REC_START · 开始记录",this::startRecording,true,1);
        button(box,"REC_STOP · 停止并排空日志",this::stopRecording,true);
        button(box,"导出事件日志 .txt",this::exportLog,true);
        text(box,"保存 MAP / EVT / REC_END 文本，不录制音频、手势、吉他、ADSR 或单声部变调设置。出现 OVF/溢出时日志不完整。",12,MUTED);
        logs=text(box,"接收窗口\n",12,0xffdce5ff);logs.setTextIsSelectable(true);logs.setTypeface(Typeface.MONOSPACE);logs.setPadding(dp(14),dp(13),dp(14),dp(13));logs.setBackground(rounded(0xff22314d,14));
        TextView footer=text(content,"FPGA MUSIC LAB  ·  让灵感在指尖发声",11,MUTED);footer.setGravity(Gravity.CENTER);footer.setBackground(rounded(0xeaffffff,12));
    }
    private void buildBendControls(LinearLayout content){
        LinearLayout box=card(content,"06","七声部独立滑音","按住和弦时，分别拖动第 1～7 键的滑杆。每个声部可上下一个八度，FSR 全局滑音继续叠加。");
        for(int i=0;i<7;i++){
            final int index=i;bendLabels[i]=text(box,"",13,MUTED);
            SeekBar bar=new SeekBar(this);bendBars[i]=bar;bar.setMax(2400);bar.setProgress(1200);
            bar.setContentDescription("第 "+(i+1)+" 个触摸声部独立音高，上下1200音分");
            bar.setProgressTintList(ColorStateList.valueOf(ACCENT));bar.setThumbTintList(ColorStateList.valueOf(ACCENT));
            box.addView(bar,new LinearLayout.LayoutParams(-1,dp(42)));
            bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar b,int p,boolean fromUser){
                    if(!fromUser)return;
                    voiceBend.edit(index,p-1200,link.connected());updateBendLabel(index);
                    if(link.connected())scheduleBend();else setStatus("音高为离线草稿；连接后点击发送全部音高");
                }
                public void onStartTrackingTouch(SeekBar b){}
                public void onStopTrackingTouch(SeekBar b){}
            });updateBendLabel(i);
        }
        text(box,"连线时约每 100ms 发送一个最新位置，逐条等 OK；其他任务期间暂存拖动。未连接时只编辑草稿，重连后须手动发送。已确认值是目标音高，FPGA 平滑过渡；改动持续到再次调节、全部回正或板子复位。",12,MUTED);
        button(box,"发送全部音高",()->{
            final int[] values=voiceBend.snapshot();voiceBend.clearPending();
            task(()->{try{for(int i=0;i<7;i++){link.command(VoiceBend.command(i+1,values[i]),"OK");final int key=i;main.post(()->{bendConfirmed[key]=values[key];updateBendLabel(key);});}}
                catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"七个声部目标音高均已确认");
        },true,1);
        button(box,"全部回正 · 0 半音",()->{
            voiceBend.clearPending();
            for(int i=0;i<7;i++){voiceBend.edit(i,0,false);bendBars[i].setProgress(1200);updateBendLabel(i);}
            task(()->{try{link.command("BEND_RESET","OK");main.post(()->{for(int i=0;i<7;i++){bendConfirmed[i]=0;updateBendLabel(i);}});}
                catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"七声部变调已回正；FSR 全局滑音继续有效");
        },true);
    }
    private void updateBendLabel(int i){
        if(bendLabels[i]==null)return;
        Integer confirmed=bendConfirmed[i];
        bendLabels[i].setText("声部 "+(i+1)+" / OUT"+(i+1)+" · "+VoiceBend.label(voiceBend.value(i))+"\n"+
            (confirmed==null?"设备目标未确认": "已确认目标："+VoiceBend.label(confirmed)));
    }
    private void forgetBendConnection(){
        voiceBend.clearPending();for(int i=0;i<7;i++){bendConfirmed[i]=null;updateBendLabel(i);}
    }
    private void scheduleBend(){if(!bendScheduled){bendScheduled=true;main.postDelayed(this::flushBend,100);}}
    private void flushBend(){
        bendScheduled=false;
        if(!link.connected()){forgetBendConnection();return;}
        if(busy){if(voiceBend.hasPending())scheduleBend();return;}
        final int key=voiceBend.take();if(key<0)return;
        final int cents=voiceBend.value(key);
        task(()->{try{link.command(VoiceBend.command(key+1,cents),"OK");main.post(()->{bendConfirmed[key]=cents;updateBendLabel(key);});}
            catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"声部 "+(key+1)+" 目标音高已确认："+VoiceBend.label(cents));
        if(voiceBend.hasPending())scheduleBend();
    }
    private void buildAdsrControls(LinearLayout content){
        LinearLayout box=card(content,"05","ADSR 包络编辑","滑块或拖动曲线控制点编辑；曲线表示待发送参数，点击应用后新发音生效。");
        adsrTarget=choices(box,"作用音源",new String[]{"触摸七键","红外 / 手势 32 复音"});
        adsrCurve=new AdsrEnvelopeView(this);box.addView(adsrCurve,new LinearLayout.LayoutParams(-1,dp(210)));
        final String[] labels={"A 起音","D 衰减","S 保持音量","R 释音"};
        for(int i=0;i<4;i++){
            final int index=i;adsrLabels[i]=text(box,labels[i],13,MUTED);
            SeekBar bar=new SeekBar(this);adsrBars[i]=bar;bar.setMax(i==2?100:1000);
            bar.setContentDescription(labels[i]);bar.setProgressTintList(ColorStateList.valueOf(ACCENT));
            box.addView(bar,new LinearLayout.LayoutParams(-1,dp(42)));
            bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar b,int progress,boolean fromUser){if(!loadingAdsr)updateAdsr(new AdsrProfile(adsrBars[0].getProgress(),adsrBars[1].getProgress(),adsrBars[2].getProgress(),adsrBars[3].getProgress()));}
                public void onStartTrackingTouch(SeekBar b){} public void onStopTrackingTouch(SeekBar b){}
            });
        }
        adsrCurve.setListener(this::updateAdsr);
        adsrTarget.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){updateAdsr(adsrDrafts[position]);}
            public void onNothingSelected(AdapterView<?> parent){}
        });
        updateAdsr(adsrDrafts[0]);
        button(box,"应用 ADSR 到下一次发音",()->{int target=adsrTarget.getSelectedItemPosition();AdsrProfile draft=adsrDrafts[target];sendSimple(draft.command(target==0?"TOUCH":"SENSOR"),"ADSR 已确认，新发音采用新参数；正在响的音符保持原包络");},true,1);
        button(box,"恢复该音源原始包络",()->sendSimple("ADSR_RESET,"+(adsrTarget.getSelectedItemPosition()==0?"TOUCH":"SENSOR"),"原始包络已恢复，新发音生效；图中仍显示编辑草稿"),true);
        text(box,"A/D/R：0～1000ms，0 表示最短一个采样；S：0～100%。触摸按住保持、松手释音。红外/手势按音符时长进入释音，短音可能在起音或衰减途中结束。参数断电恢复默认。吉他和 TEST32 使用各自包络。",12,MUTED);
    }
    private void updateAdsr(AdsrProfile profile){
        if(adsrCurve==null)return;loadingAdsr=true;
        int target=Math.max(0,adsrTarget.getSelectedItemPosition());adsrDrafts[target]=profile;
        int[] values={profile.attack,profile.decay,profile.sustain,profile.release};
        String[] labels={"A 起音","D 衰减","S 保持音量","R 释音"};
        for(int i=0;i<4;i++){adsrBars[i].setProgress(values[i]);adsrLabels[i].setText(labels[i]+" · "+values[i]+(i==2?"%":" ms"));}
        adsrCurve.setProfile(profile);loadingAdsr=false;
    }
    private Spinner choices(LinearLayout box,String label,String[] values){text(box,label,13,MUTED);Spinner spinner=new Spinner(this);spinner.setContentDescription(label);spinner.setAdapter(options(Arrays.asList(values)));addSpinner(box,spinner);return spinner;}
    private boolean hasBluetoothPermission(){return Build.VERSION.SDK_INT<31||checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;}
    private Runnable afterPermission;
    private void ensurePermission(Runnable action){if(hasBluetoothPermission())action.run();else{afterPermission=action;requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT},PERMISSION);}}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==PERMISSION){Runnable r=afterPermission;afterPermission=null;if(grants.length>0&&grants[0]==PackageManager.PERMISSION_GRANTED){if(r!=null)r.run();}else alert("连接 HC-05 需要“附近的设备”权限；请在系统设置中允许后重试。");}}
    private void refreshDevices(){try{paired.clear();List<String> names=new ArrayList<>();if(adapter==null){setStatus("此手机不支持蓝牙");return;}if(!adapter.isEnabled()){setStatus("请先开启系统蓝牙并配对 HC-05");return;}
            paired.addAll(adapter.getBondedDevices());Collections.sort(paired,(a,b)->safeName(a).compareTo(safeName(b)));for(BluetoothDevice d:paired)names.add(safeName(d)+"\n"+d.getAddress());
            devices.setAdapter(options(names));if(paired.isEmpty())setStatus("未找到已配对设备。请在系统蓝牙设置配对 HC-05 后刷新。");
            else for(int i=0;i<paired.size();i++)if(safeName(paired.get(i)).toUpperCase(Locale.ROOT).contains("HC")){devices.setSelection(i);break;}
        }catch(SecurityException e){alert("请允许附近设备权限后刷新");}}
    private String safeName(BluetoothDevice d){String n=d.getName();return n==null?"未命名设备":n;}
    private void connectSelected(){if(recording||recordDraining){alert("请先停止录制并等待 REC_END，再重新连接；也可点断开以中断此次录制。");return;}int selected=devices.getSelectedItemPosition();if(selected<0||selected>=paired.size()){alert("请先刷新并选择已配对 HC-05");return;}BluetoothDevice d=paired.get(selected);forgetBendConnection();mapping=null;mapInfo.setText("连接中，尚未读取键位");task(()->{link.connect(d);link.command("PING","PONG");readMapping();},"HC-05 已连接，可下载曲谱");}
    private void setStatus(String s){status.setText(s);}
    private void setBusy(boolean value){busy=value;for(Button b:lockedButtons)b.setEnabled(!value);getWindow().setFlags(value?WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON:0,WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}
    private interface Work {void run()throws Exception;}
    private void task(Work work,String done){if(busy)return;setBusy(true);cancelled=false;setStatus("处理中…");worker.execute(()->{try{work.run();main.post(()->{setBusy(false);if(!cancelled)setStatus(done);});}catch(Exception e){main.post(()->{setBusy(false);if(!cancelled){if(!link.connected()){mapping=null;recordingInterrupted();mapInfo.setText("连接已关闭，请重新连接后重试");}setStatus("未完成："+e.getMessage());alert(e.getMessage());}});}});}
    private void recordingInterrupted(){if(recording||recordDraining){recordingOverflow=true;recordingCompleted=false;}recording=false;recordDraining=false;}
    private void disconnect(){forgetBendConnection();cancelled=true;link.close();mapping=null;recordingInterrupted();mapInfo.setText("尚未连接");setStatus("已断开。下载未提交时旧谱保留；重新连接后可重新下载。");}
    private void showSong(){scoreInfo.setText(song.name+"\n"+song.events.size()+" 条 · "+String.format(Locale.ROOT,"%.2f",song.durationMs()/1000.0)+" 秒\n需要音高："+SongCodec.notes(song.requiredMask()));progress.setProgress(0);}
    private void preview(){StringBuilder s=new StringBuilder();long at=0;for(int i=0;i<song.events.size();i++){SongCodec.Event e=song.events.get(i);s.append(i).append("  ").append(at).append("ms  ").append(SongCodec.notes(e.mask)).append("  ").append(e.durationMs).append("ms\n");at+=e.durationMs;}new AlertDialog.Builder(this).setTitle(song.name).setMessage(s.toString()).setPositiveButton("关闭",null).show();}
    private void pickScore(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");startActivityForResult(i,PICK_SCORE);}
    private void readMapping()throws Exception {int[] m=SongCodec.parseMapping(link.command("MAP?","MAP"));mapping=m;main.post(()->{mapInfo.setText("第 1..7 键："+join(m));mappingInput.setText(join(m));});}
    private static String join(int[] m){StringBuilder s=new StringBuilder();for(int v:m){if(s.length()>0)s.append(',');s.append(v);}return s.toString();}
    private void download(){if(recording||recordDraining){alert("先停止录制并等待 REC_END，再下载曲谱");return;}final SongCodec.Song selected=song;
        task(()->{readMapping();selected.checkMapping(mapping);List<String> commands=selected.commands();for(int i=0;i<commands.size();i++){if(cancelled)throw new IOException("下载已取消");String command=commands.get(i);link.command(command,"OK");final int p=(i+1)*100/commands.size();final int n=i+1;main.post(()->{progress.setProgress(p);setStatus("下载 "+n+" / "+commands.size()+"，已确认 "+command);});}},"曲谱已校验并提交。可断开手机，用板上按键或 PLAY 开始指引；掉电后需重新下载。");}
    private void sendSimple(String command,String done){task(()->link.command(command,"OK"),done);}
    private void audition(){
        if(recording||recordDraining){alert("先停止录制并等待 REC_END，再自动演奏");return;}
        task(()->{try{link.command("AUDITION","OK");}catch(IOException e){
            if(e.getMessage()!=null&&e.getMessage().contains("ERR,CMD"))throw new IOException("板上固件尚不支持自动演奏，请烧录配套新版 FPGA 位流；原 PLAY 仍可用于屏幕指引。");
            if(e.getMessage()!=null&&e.getMessage().contains("ERR,STATE"))throw new IOException("板上没有有效曲谱。请先点击校验键位并下载，等待显示已提交，再自动演奏。");
            throw e;
        }},"自动演奏已开始：预备 1.5 秒后由开发板合成发声；结束自动停止，也可点 STOP 提前停止。");
    }
    private void applyMapping(){if(recording||recordDraining){alert("录制期间键位锁定，请先停止并等待 REC_END");return;}String[] p=mappingInput.getText().toString().trim().split(",",-1);if(p.length!=7){alert("请输入 7 个 MIDI 音高，用英文逗号分隔");return;}int[] m=new int[7];try{for(int i=0;i<7;i++){m[i]=Integer.parseInt(p[i].trim());if(m[i]<60||m[i]>72)throw new NumberFormatException();}}catch(NumberFormatException e){alert("七个音高均须为 60..72");return;}
        task(()->{for(int i=0;i<7;i++)link.command("MAP,"+(i+1)+","+m[i],"OK");readMapping();},"键位已应用。若曲谱需要其他音高，下载前会提示。");}
    private void startRecording(){if(recording||recordDraining){alert("正在录制或等待日志排空");return;}recordingText.setLength(0);recordingOverflow=false;recordingCompleted=false;
        // Mark before the command: the FPGA may send MAP/EVT immediately after OK.
        recording=true;task(()->{try{link.command("REC_START","OK");}catch(Exception e){recording=false;recordingOverflow=true;throw e;}},"正在记录演奏事件；保持 App 前台");}
    private void stopRecording(){if(!recording){alert("当前没有正在进行的事件录制");return;}recordDraining=true;task(()->link.command("REC_STOP","OK"),"停止命令已确认；接收窗口 REC_END 为日志结束标记");}
    private void receive(String line){logText.append(line).append('\n');if(logText.length()>12000)logText.delete(0,logText.length()-10000);logs.setText(logText.toString());
        if(recording||recordDraining){if(recordingText.length()+line.length()+1<=2*1024*1024)recordingText.append(line).append('\n');else{recordingOverflow=true;setStatus("App 日志达到 2MB 上限，请停止并导出；此次日志不完整");}if(line.contains("OVF")||line.contains("OVERFLOW")){recordingOverflow=true;setStatus("FIFO 溢出：此次事件日志不完整");}
            if(line.startsWith("REC_END,")){recording=false;recordDraining=false;if(!line.equals("REC_END,0"))recordingOverflow=true;recordingCompleted=line.equals("REC_END,0")&&!recordingOverflow;setStatus(recordingOverflow?"录制结束，检测到溢出，日志不完整":"录制结束，事件日志可导出");}}
    }
    private void exportLog(){if(recordingText.length()==0){alert("暂无日志，请先 REC_START 记录演奏事件");return;}Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("text/plain");i.putExtra(Intent.EXTRA_TITLE,"fpga-performance-"+System.currentTimeMillis()+".txt");startActivityForResult(i,EXPORT_LOG);}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(appearance.onActivityResult(request,result,data))return;if(result!=RESULT_OK||data==null||data.getData()==null)return;Uri uri=data.getData();
        if(request==PICK_SCORE){String display="导入曲谱";try(Cursor c=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(c!=null&&c.moveToFirst())display=c.getString(0);}catch(Exception ignored){}final String name=display;
            task(()->{byte[] bytes;try(InputStream in=getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException("无法打开文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(out.size()+n>2*1024*1024)throw new IOException("文件超过 2MB");out.write(b,0,n);}bytes=out.toByteArray();}SongCodec.Song parsed=SongCodec.parse(name,bytes);main.post(()->{song=parsed;showSong();});},"曲谱已导入；下载前会核对实际键位");
        }else if(request==EXPORT_LOG){final byte[] bytes=("# FPGA performance events; audio is not recorded\n# complete="+(recordingCompleted&&!recordingOverflow)+"\n"+recordingText).getBytes(StandardCharsets.UTF_8);task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建日志文件");out.write(bytes);}},"事件日志已导出");}
    }
    private void alert(String message){new AlertDialog.Builder(this).setTitle("提示").setMessage(message).setPositiveButton("知道了",null).show();}
    @Override protected void onDestroy(){voiceBend.clearPending();main.removeCallbacksAndMessages(null);cancelled=true;link.close();worker.shutdownNow();if(appearance!=null)appearance.close();super.onDestroy();}
}
