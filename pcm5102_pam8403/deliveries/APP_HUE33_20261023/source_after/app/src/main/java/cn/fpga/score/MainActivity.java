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
import android.text.Editable;
import android.text.TextWatcher;
import java.util.function.Supplier;
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
    private final ExecutorService phoneWorker=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private SppLink link;
    private BluetoothAdapter adapter;
    private TextView status,scoreInfo,mapInfo,logs;
    private ProgressBar progress;
    private Spinner libraryTier,libraryTracks;
    private TextView libraryInfo;
    private List<SongLibrary.Entry> libraryEntries=Collections.emptyList();
    private SongLibrary.Entry exportingScore;
    private Spinner devices,gestureTone,gestureVibrato,gestureBank;
    private EditText mappingInput,calibrationInput;
    private Spinner mappingTarget;
    private PianoKeyboardView mappingKeyboard;
    private TextView controlsInfo,volumeLabel,wetLabel,adcInfo;
    private Spinner touchMode,serialPolarity,effectChoice,holdChoice,analogChoice,pressureChoice,polyChoice;
    private SeekBar volumeBar,wetBar;
    private final SeekBar[] performanceBars=new SeekBar[5];
    private final TextView[] performanceLabels=new TextView[5];
    private SeekBar performanceTempo;
    private TextView performanceTempoLabel,performanceState;
    private boolean defaultGlide=true;
    private int[] confirmedPitch,confirmedVibrato,confirmedEcho;
    private Spinner echoChoice,echoDivision;
    private SeekBar echoTempo;
    private TextView echoLabel,echoState;
    private SeekBar tuningBar;
    private Spinner standardPitch;
    private TextView tuningLabel;
    private DeviceControls confirmedControls;
    private Spinner xyRatio,xyPhase;
    private TextView xyInfo;
    private TextView ledStatus,ledPreviewInfo;
    private SpectrumPreviewView ledPreview;
    private volatile boolean ledPreviewRunning;
    private boolean ledPollPending;
    private int ledGeneration;
    private long ledLastFrameAt;
    private final Runnable ledPoll=this::pollLedPreview;
    private final Runnable ledStale=()->{
        if(ledPreviewRunning && SystemClock.uptimeMillis()-ledLastFrameAt>=1500){
            ledPreview.setFrame(null);ledPreviewInfo.setText("数据已过期，等待设备；其他命令执行期间预览暂停。");
        }
    };
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
    private static final int INK=Theme.INK,MUTED=Theme.MUTED,ACCENT=Theme.PINK_INK;
    private final List<BluetoothDevice> paired=new ArrayList<>();
    private final List<Button> lockedButtons=new ArrayList<>();
    private SongCodec.Song song=SongCodec.twinkle();
    private volatile boolean busy,cancelled,recording,recordDraining;
    private int[] mapping;
    private final StringBuilder logText=new StringBuilder();
    private final StringBuilder recordingText=new StringBuilder();
    private boolean recordingOverflow;
    private boolean recordingCompleted;
    private PhonePiano phonePiano;
    private PhoneTake phoneDraft;
    private PhoneTakeStore phoneStore;
    private TextView phoneInfo;
    private boolean phoneRecording,phoneDirty,phoneBusy;
    private long phoneStart;
    private byte[] phoneExportMidi;
    private static final int PICK_SCORE=10,EXPORT_LOG=11,PERMISSION=12,EXPORT_SCORE=14,EXPORT_PHONE=15;
    private static final String[] SECTION_NAMES={"设备","演奏","声音","曲谱","显示","记录"};
    private static final String[] GROUP_NAMES={"键位与触发","音高","音色","包络","表情","延音与复音","音量与平衡"};
    private final ControlState controlState=new ControlState();
    private final LinearLayout[] sections=new LinearLayout[6],sourcePages=new LinearLayout[3];
    private final LinearLayout[][] sourceGroups=new LinearLayout[3][7];
    private final Button[] navButtons=new Button[6],sourceButtons=new Button[3],pageButtons=new Button[4],xyButtons=new Button[6],takeButtons=new Button[4];
    private final List<DraftBinding> draftBindings=new ArrayList<>();
    private final List<View> deviceInputs=new ArrayList<>();
    private LinearLayout drawer,adsrPanel,sensorTonePanel,sensorExpressionPanel;
    private FrameLayout drawerOverlay;
    private View connectionDot;
    private TextView sectionTitle,headerPending,settingsSummary,takeReason,logReason,workflowStatus;
    private Button takeConfigure,logStart,logStop,adsrApply;
    private TextView adsrBadge,takeInfo;
    private boolean takePolling;
    private ScrollView contentScroll;
    private int currentSection,currentSource;
    private boolean drawerOpen,uiReady,resumed;
    private LedState confirmedLed;
    private TakeStatus confirmedTake;
    private String confirmedSerial,confirmedCalibration;
    private final Map<String,String> acknowledged=new HashMap<>();
    private final Runnable displayPoll=this::pollDisplayState;
    private static final int[] XY_RATIOS={2,3,1,1,1,0},XY_PHASES={0,0,2,1,0,0};
    private final class DraftBinding {
        final String key;final int section;final Button apply;final TextView badge;final Supplier<String> draft;
        DraftBinding(String key,int section,Button apply,TextView badge,Supplier<String> draft){this.key=key;this.section=section;this.apply=apply;this.badge=badge;this.draft=draft;}
    }
    @Override public void onCreate(Bundle state){super.onCreate(state);
        if(state!=null){String id=state.getString("exportingScore");for(SongLibrary.Entry entry:SongLibrary.all())if(entry.id.equals(id)){exportingScore=entry;break;}}
        link=new SppLink(new SppLink.Listener(){
            public void line(String line){main.post(()->receive(line));}
            public void disconnected(String reason){main.post(()->{forgetBendConnection();mapping=null;recordingInterrupted();forgetControls();mapInfo.setText("键位未知，请重新连接");setStatus("蓝牙断开："+reason);});}
        });
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);adapter=manager==null?null:manager.getAdapter();
        buildUi();showSong();setStatus("先在系统蓝牙设置配对 HC-05，再刷新设备");
        if(hasBluetoothPermission())refreshDevices();
    }
    private int dp(int n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private GradientDrawable rounded(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    /** 卡片与按钮共用的抬升阴影：让层次从「平面」变成「纸片叠起来」。 */
    private void lift(View view,int dp){view.setElevation(dp(dp));}
    private TextView text(LinearLayout box,String value,int sp,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(sp);t.setTextColor(color);t.setPadding(0,dp(4),0,dp(6));t.setLineSpacing(dp(3),1);if(sp>=18)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);box.addView(t);return t;}
    private LinearLayout row(LinearLayout box){LinearLayout r=new LinearLayout(this);r.setOrientation(LinearLayout.HORIZONTAL);box.addView(r,new LinearLayout.LayoutParams(-1,-2));return r;}
    private Button button(LinearLayout box,String value,Runnable action,boolean lock){return button(box,value,action,lock,0);}
    // 0: 描边次级, 1: 霓虹主按钮, 2: 危险/取消。
    private Button button(LinearLayout box,String value,Runnable action,boolean lock,int style){
        Button b=new SegmentButton(this);b.setText(value);b.setTextSize(14);b.setAllCaps(false);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setMinHeight(dp(50));b.setMinimumHeight(dp(50));b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(12),dp(10),dp(12),dp(10));b.setLetterSpacing(0.01f);
        android.graphics.drawable.StateListDrawable states=new android.graphics.drawable.StateListDrawable();
        states.addState(new int[]{-android.R.attr.state_enabled},rounded(Theme.DISABLED_BG,Theme.R_BUTTON));
        if(style==1){
            GradientDrawable neon=Theme.gradient(Theme.BUTTON,Theme.R_BUTTON);states.addState(new int[]{},neon);
            b.setBackground(new RippleDrawable(ColorStateList.valueOf(Theme.RIPPLE),states,null));
            b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{Theme.DISABLED_FG,Color.WHITE}));
            lift(b,3);
        }else{
            int fill=style==2?Theme.DANGER_BG:Theme.SURFACE,fg=style==2?Theme.DANGER:Theme.VIOLET;
            GradientDrawable soft=rounded(fill,Theme.R_BUTTON);
            if(style!=2)soft.setStroke(dp(1),Theme.GHOST_LINE);
            states.addState(new int[]{},soft);
            b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22a44be0),states,rounded(0xffffffff,Theme.R_BUTTON)));
            b.setTextColor(new ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{Theme.DISABLED_FG,fg}));
        }
        b.setElevation(0);b.setStateListAnimator(null);
        boolean horizontal=box.getOrientation()==LinearLayout.HORIZONTAL;LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(horizontal?0:-1,-2,horizontal?1:0);lp.setMargins(horizontal?dp(3):0,dp(5),horizontal?dp(3):0,dp(5));box.addView(b,lp);b.setOnClickListener(v->action.run());if(lock)lockedButtons.add(b);return b;
    }
    private LinearLayout card(LinearLayout parent,String number,String title,String hint){
        LinearLayout card=new LinearLayout(this);card.setOrientation(LinearLayout.VERTICAL);card.setPadding(dp(18),dp(17),dp(18),dp(17));
        GradientDrawable bg=Theme.card(Theme.R_CARD);card.setBackground(bg);lift(card,2);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(Theme.GAP);parent.addView(card,lp);
        // 顶部一道 3dp 粉紫渐变细线，给每张卡片一个「舞台上沿」的暗示。
        View edge=new View(this);edge.setBackground(Theme.gradient(new int[]{Theme.PINK,Theme.VIOLET,Theme.CYAN},2));
        LinearLayout.LayoutParams edgeLp=new LinearLayout.LayoutParams(-1,dp(3));edgeLp.bottomMargin=dp(13);edge.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);card.addView(edge,edgeLp);
        LinearLayout heading=row(card);heading.setGravity(Gravity.CENTER_VERTICAL);
        TextView badge=new TextView(this);badge.setText(number);badge.setGravity(Gravity.CENTER);badge.setTextSize(13);badge.setTextColor(Color.WHITE);badge.setTypeface(Typeface.DEFAULT,Typeface.BOLD);badge.setBackground(Theme.gradient(Theme.BUTTON,Theme.R_CHIP));heading.addView(badge,new LinearLayout.LayoutParams(dp(34),dp(34)));
        TextView label=new TextView(this);label.setText(title);label.setTextSize(19);label.setTextColor(INK);label.setTypeface(Typeface.DEFAULT,Typeface.BOLD);label.setLetterSpacing(0.01f);LinearLayout.LayoutParams labelLp=new LinearLayout.LayoutParams(0,-2,1);labelLp.leftMargin=dp(11);heading.addView(label,labelLp);
        if(hint!=null)text(card,hint,13,MUTED);return card;
    }
    private void addSpinner(LinearLayout box,Spinner spinner){spinner.setMinimumHeight(dp(54));spinner.setBackgroundTintList(ColorStateList.valueOf(ACCENT));box.addView(spinner,new LinearLayout.LayoutParams(-1,-2));}
    /** 进度条：粉紫渐变填充 + 淡粉轨道，和主按钮同一套霓虹色。 */
    private android.graphics.drawable.Drawable progressDrawable(){
        GradientDrawable track=new GradientDrawable();track.setCornerRadius(dp(4));track.setColor(0x33e8447f);
        GradientDrawable fill=new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,Theme.BUTTON);fill.setCornerRadius(dp(4));
        android.graphics.drawable.ClipDrawable clip=new android.graphics.drawable.ClipDrawable(fill,Gravity.START,android.graphics.drawable.ClipDrawable.HORIZONTAL);
        android.graphics.drawable.LayerDrawable layers=new android.graphics.drawable.LayerDrawable(new android.graphics.drawable.Drawable[]{track,clip});
        layers.setId(0,android.R.id.background);layers.setId(1,android.R.id.progress);
        return layers;
    }
    private ArrayAdapter<String> options(List<String> values){return new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,values){
        private View decorate(View v){if(v instanceof TextView){TextView t=(TextView)v;t.setTextColor(INK);t.setTextSize(14);t.setSingleLine(false);t.setMaxLines(2);t.setMinHeight(dp(52));t.setGravity(Gravity.CENTER_VERTICAL);t.setPadding(dp(12),dp(9),dp(12),dp(9));}return v;}
        @Override public View getView(int position,View convert,ViewGroup parent){return decorate(super.getView(position,convert,parent));}
        @Override public View getDropDownView(int position,View convert,ViewGroup parent){View v=decorate(super.getDropDownView(position,convert,parent));v.setBackgroundColor(Theme.SURFACE_ALT);return v;}
    };}
    private void buildUi(){
        FrameLayout root=new FrameLayout(this);
        getWindow().setStatusBarColor(Color.TRANSPARENT);getWindow().setNavigationBarColor(Color.TRANSPARENT);getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        // Android 15 draws system icons over the app; protect them from dark photos.
        View topBar=new View(this),bottomBar=new View(this);topBar.setBackgroundColor(Theme.BAR);bottomBar.setBackgroundColor(Theme.BAR);topBar.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);bottomBar.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        FrameLayout.LayoutParams topBarLp=new FrameLayout.LayoutParams(-1,0,Gravity.TOP),bottomBarLp=new FrameLayout.LayoutParams(-1,0,Gravity.BOTTOM);root.addView(topBar,topBarLp);root.addView(bottomBar,bottomBarLp);
        appearance=new AppearanceController(this,root,topBar,bottomBar);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.setVerticalScrollBarEnabled(false);root.addView(scroll,new FrameLayout.LayoutParams(-1,-1));contentScroll=scroll;
        LinearLayout shell=new LinearLayout(this);shell.setOrientation(LinearLayout.VERTICAL);
        root.addView(shell,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);header.setBackground(rounded(Theme.SURFACE,0));shell.addView(header,new LinearLayout.LayoutParams(-1,dp(48)));
        FrameLayout hamburger=new FrameLayout(this);hamburger.setContentDescription("打开分区导航");hamburger.setFocusable(true);hamburger.setOnClickListener(v->openDrawer());
        for(int n=0;n<3;n++){View line=new View(this);line.setBackgroundColor(Theme.INK);FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(dp(21),dp(2),Gravity.TOP|Gravity.CENTER_HORIZONTAL);lp.topMargin=dp(16+n*7);hamburger.addView(line,lp);}header.addView(hamburger,new LinearLayout.LayoutParams(dp(52),-1));
        sectionTitle=new TextView(this);sectionTitle.setTextSize(18);sectionTitle.setTextColor(INK);sectionTitle.setTypeface(Typeface.DEFAULT,Typeface.BOLD);header.addView(sectionTitle,new LinearLayout.LayoutParams(0,-2,1));
        connectionDot=new View(this);header.addView(connectionDot,new LinearLayout.LayoutParams(dp(10),dp(10)));
        headerPending=new TextView(this);headerPending.setText(" •");headerPending.setTextSize(22);headerPending.setTextColor(Theme.PINK);headerPending.setContentDescription("当前分区有待发送草稿");header.addView(headerPending,new LinearLayout.LayoutParams(dp(28),-2));
        workflowStatus=text(shell,"",12,Theme.PINK_INK);workflowStatus.setPadding(dp(18),dp(5),dp(18),dp(5));workflowStatus.setBackground(rounded(Theme.SURFACE_ALT,0));workflowStatus.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.removeView(scroll);shell.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        shell.setOnApplyWindowInsetsListener((v,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()|WindowInsets.Type.ime());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);topBarLp.height=bars.top;bottomBarLp.height=bars.bottom;}
            else{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());topBarLp.height=insets.getSystemWindowInsetTop();bottomBarLp.height=insets.getSystemWindowInsetBottom();}
            topBar.setLayoutParams(topBarLp);bottomBar.setLayoutParams(bottomBarLp);return insets;
        });
        LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(18),dp(18),dp(18),dp(24));scroll.addView(content);
        for(int n=0;n<sections.length;n++){sections[n]=new LinearLayout(this);sections[n].setOrientation(LinearLayout.VERTICAL);content.addView(sections[n],new LinearLayout.LayoutParams(-1,-2));}
        content=sections[0];setContentView(root);shell.requestApplyInsets();
        // ── 主视觉：打包的原创插画 hero.png 只含图形，文字由 Java 绘制（避免重复与拉伸）。
        FrameLayout hero=new FrameLayout(this);hero.setBackground(Theme.gradient(Theme.HERO,24));lift(hero,4);content.addView(hero,new LinearLayout.LayoutParams(-1,-2));
        android.widget.ImageView heroArt=new android.widget.ImageView(this);
        android.graphics.Bitmap heroBitmap=ArtAssets.load(this,"hero");
        if(heroBitmap!=null){heroArt.setImageBitmap(heroBitmap);heroArt.setScaleType(android.widget.ImageView.ScaleType.FIT_XY);}
        heroArt.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        // 素材宽 972、高 300；卡片内可用宽度取 dp(36)，按同比例定高，保证不失真。
        {int cardW=Math.max(1,getResources().getDisplayMetrics().widthPixels-dp(36));int cardH=Math.round(cardW*300f/972f);hero.addView(heroArt,new FrameLayout.LayoutParams(-1,cardH));}
        LinearLayout heroText=new LinearLayout(this);heroText.setOrientation(LinearLayout.VERTICAL);heroText.setPadding(dp(24),dp(18),dp(26),dp(16));hero.addView(heroText,new FrameLayout.LayoutParams(-1,-2));
        text(heroText,"F P G A   /   M U S I C   L A B",11,0xffffc9de);
        TextView heroTitle=text(heroText,"FPGA 曲谱助手",28,Color.WHITE);heroTitle.setLetterSpacing(0.02f);heroTitle.setShadowLayer(dp(6),0,dp(2),0xaa3a1852);
        text(heroText,"让每一次触碰，都有旋律。",15,0xffffdcea);
        text(heroText,"HC-05 蓝牙连接  ·  HUB75E 屏幕指引\n触摸、手势与单弦吉他，由 FPGA 实时合成。",12,0xfff0d5ea);
        TextView heroTag=text(heroText,"孤独摇滚 · 霓虹舞台主题",11,0xff8ef0ff);heroTag.setLetterSpacing(0.06f);
        button(content,"外观设置 · 更换背景",()->appearance.showSettings(),false);
        LinearLayout statusBox=new LinearLayout(this);statusBox.setOrientation(LinearLayout.VERTICAL);statusBox.setPadding(dp(17),dp(13),dp(17),dp(13));statusBox.setBackground(rounded(0xf8fff6fb,18));LinearLayout.LayoutParams statusLp=new LinearLayout.LayoutParams(-1,-2);statusLp.setMargins(0,dp(8),0,dp(16));content.addView(statusBox,statusLp);
        LinearLayout statusHead=row(statusBox);statusHead.setGravity(Gravity.CENTER_VERTICAL);
        BeatBarsView statusBars=new BeatBarsView(this);statusBars.setAlpha(0.85f);LinearLayout.LayoutParams sbLp=new LinearLayout.LayoutParams(dp(16),dp(9));sbLp.rightMargin=dp(8);statusHead.addView(statusBars,sbLp);
        TextView statusTag=new TextView(this);statusTag.setText("设备状态");statusTag.setTextSize(12);statusTag.setTextColor(MUTED);statusTag.setLetterSpacing(0.08f);statusHead.addView(statusTag);
        try{android.content.pm.PackageInfo installed=getPackageManager().getPackageInfo(getPackageName(),0);text(statusBox,"当前安装：v"+installed.versionName+" / Code"+installed.getLongVersionCode(),12,MUTED);}
        catch(PackageManager.NameNotFoundException e){throw new IllegalStateException(e);}
        status=text(statusBox,"",14,ACCENT);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout box=card(content,"01","蓝牙连接","先在系统蓝牙设置中配对 HC-05，再选择设备。");devices=new Spinner(this);devices.setContentDescription("已配对蓝牙设备");addSpinner(box,devices);
        LinearLayout connectionRow=row(box);button(connectionRow,"刷新设备",()->ensurePermission(this::refreshDevices),true);button(connectionRow,"连接设备",()->ensurePermission(this::connectSelected),true,1);
        button(box,"断开 / 取消下载",this::disconnect,false,2);
        text(box,"当前手机与FPGA仅通过HC-05通信，无需USB串口模块或OTG。",12,MUTED);
        buildPerformance();
        buildControls(content);
        box=card(sections[3],"02","曲谱与播放","从分级曲库选曲，或从文件夹导入；下载后可自动演奏或跟随屏幕练习。");
        buildSongLibrary(box);
        button(box,"载入小星星示例",()->{song=SongCodec.twinkle();showSong();},true);
        button(box,"从文件夹导入 CSV / MIDI",this::pickScore,true);
        scoreInfo=text(box,"",14,INK);scoreInfo.setPadding(dp(13),dp(12),dp(13),dp(12));scoreInfo.setBackground(rounded(Theme.SURFACE_ALT,12));scoreInfo.setLineSpacing(dp(4),1);
        button(box,"查看全部音符与休止",this::preview,true);
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(100);progress.setProgressDrawable(progressDrawable());progress.setContentDescription("曲谱下载进度");LinearLayout.LayoutParams progressLp=new LinearLayout.LayoutParams(-1,dp(8));progressLp.setMargins(0,dp(10),0,dp(10));box.addView(progress,progressLp);
        button(box,"校验键位并下载 / 重新下载",this::download,true,1);
        text(box,"逐条确认后发送下一条。超时或取消后请重连并从头下载；提交成功前保留板上旧谱。",12,MUTED);
        button(box,"自动演奏 · 已下载曲谱",this::audition,true,1);
        text(box,"下载提交成功后点自动演奏，开发板喇叭会从头播放，无需按触摸键；预备 1.5 秒后发声，结束自动停止。使用当前触摸 ADSR 和音高/压力设置，需配套新版 FPGA 位流。",12,MUTED);
        LinearLayout playRow=row(box);button(playRow,"PLAY · 开始指引",()->sendSimple("PLAY","已开始无声指引，预备 1.5 秒后进入首条音符，请按触摸键演奏"),true,1);button(playRow,"STOP · 停止",()->sendSimple("STOP","指引 / 自动演奏已停止，按住的触摸键仍可发声"),true);
        buildLedControls(sections[4]);
        box=card(sourceGroups[0][1],"MAP","七键音高映射","按第 1～7 键填写 MIDI 音高，范围 60～72。");
        mapInfo=text(box,"尚未读取键位",14,MUTED);
        button(box,"读取设备键位 MAP?",()->task(()->readMapping(),"键位已读取"),true);
        mappingInput=new EditText(this);mappingInput.setSingleLine(true);mappingInput.setText("60,61,62,63,64,65,66");mappingInput.setTextColor(INK);mappingInput.setTextSize(15);mappingInput.setMinHeight(dp(54));mappingInput.setPadding(dp(12),dp(12),dp(12),dp(12));mappingInput.setBackground(rounded(Theme.SURFACE_ALT,Theme.R_CHIP));mappingInput.setContentDescription("第1到第7键的 MIDI 音高，用英文逗号分隔");
        mappingTarget=choices(box,"选择要修改的扫描键号（当前仅 K1～K7 可映射）",new String[]{"K1 · 白1","K2 · 黑1","K3 · 白2","K4 · 黑2","K5 · 白3","K6 · 白4","K7 · 黑3"});
        mappingKeyboard=new PianoKeyboardView(this,72,(key,down)->{if(down)editMappedNote(ChromaticKeys.note(key));});box.addView(mappingKeyboard,new LinearLayout.LayoutParams(-1,dp(180)));
        text(box,"先选键号，再点琴键填写目标 MIDI 音高；粉框显示该键草稿。K8～K16 仍固定音高；后三个踏板条高音超出 MAP 的60～72范围，不能选。",12,MUTED);
        text(box,"高级入口 · 七键 MIDI 文本",13,MUTED);box.addView(mappingInput,new LinearLayout.LayoutParams(-1,-2));
        button(box,"应用七键映射",this::applyMapping,true,1);
        button(box,"恢复默认映射",()->{if(recording||recordDraining){alert("先停止并等待日志结束，再修改键位");return;}task(()->{link.command("MAP_RESET","OK");readMapping();},"默认映射已恢复");},true);
        sensorTonePanel=card(sourceGroups[1][2],"TONE","共享音色","作用于：红外 + 手势（共用一套参数）。调整后两个音源同时改变；阶段 E0/E1（免～中成本）再分源。");
        gestureTone=choices(sensorTonePanel,"红外 / 手势音色",new String[]{"正弦","钢琴","长笛","尤克里里","鼓","电钢琴","钟声","弦乐"});
        button(sensorTonePanel,"应用音源音色",()->{int value=gestureTone.getSelectedItemPosition();sendSimple("TONE,"+value,"红外 / 手势音色已确认："+gestureTone.getSelectedItem());},true);
        sensorExpressionPanel=card(sourceGroups[1][4],"VIB","共享颤音","作用于：红外 + 手势（共用一套参数）。下方颤音改变音高；起振延迟从整体使能或应用参数时计时，不是逐音符延迟。");
        gestureVibrato=choices(sensorExpressionPanel,"红外 / 手势颤音",new String[]{"关闭","开启"});
        button(sensorExpressionPanel,"应用音源颤音",()->{int value=gestureVibrato.getSelectedItemPosition();sendSimple("VIBRATO,"+value,"红外 / 手势颤音已确认："+gestureVibrato.getSelectedItem());},true);
        gestureBank=choices(sourceGroups[2][0],"手势音符组",new String[]{"低音组 C4～F4","高音组 G4～C5"});
        button(sourceGroups[2][0],"应用手势音符组",()->{int value=gestureBank.getSelectedItemPosition();sendSimple("BANK,"+value,"手势音符组已确认："+gestureBank.getSelectedItem());},true);
        text(sourceGroups[2][0],"音符组只作用于手势；七参数族中的其他共享项会明确标注。",12,MUTED);
        button(sections[1],"GUITAR · 单弦拨弦一次",()->sendSimple("GUITAR","单弦吉他拨弦命令已确认"),true,1);
        text(sections[1],"吉他每点一次拨弦一次，无需手势传感器就绪；使用独立的固定包络。",12,MUTED);
        button(sections[4],"TEST32 · 32 路频谱验证",()->sendSimple("TEST32","已触发 32 路不同频率正弦，约 2.7 秒；颤音关闭"),true);
        buildAdsrControls(sourceGroups[0][3]);
        buildBendControls(sourceGroups[0][1]);
        buildPerformanceControls();
        box=card(sections[5],"EVT","板上事件 · RAM / Flash · 板上回放","统一版由下面按钮控制事件录制，16 个实体键保留演奏。独立事件版还可用 K13～K16 控制。");
        takeInfo=text(box,"连接新版 FPGA 固件后读取录制状态。",13,MUTED);
        text(box,"录的是按键和表情事件，不是音频；保存在板上，当前不提供文件导出。停止后可直接回放或保存，无需先回放才能保存。",12,MUTED);
        takeReason=text(box,"",13,Theme.DANGER);
        takeConfigure=button(box,"切到可录配置 · 关闭踏板 / 复音 16",this::configureTake,true);
        takeButtons[0]=segment(box,"1 · 开始录制",()->takeAction("TAKE_REC"),true);
        LinearLayout takeRow=row(box);
        takeButtons[1]=segment(takeRow,"2 · 停止",()->takeAction("TAKE_STOP"),true);
        takeButtons[2]=segment(takeRow,"3 · 回放",()->takeAction("TAKE_PLAY"),true);
        takeButtons[3]=segment(box,"4 · 保存到板上 Flash",()->takeAction("TAKE_SAVE"),true);
        button(box,"删除已录制内容",()->takeAction("TAKE_DEL"),true,2);
        button(box,"读取录制状态",()->takeAction(null),true);
        text(box,"等待显示 Flash 保存并读回校验成功后才能断电。容量为 1024 条事件；连续音量或音高变化会较快用满。覆盖与删除均需再次确认。",12,MUTED);
        buildPhoneRecording(sections[5]);
        box=card(sections[5],"LOG","演奏事件日志 · 手机内存 · 导出 TXT","REC_START / REC_STOP 记录设备事件文本；不是音频，也不等同于板上 TAKE 录制。统一固件可能未启用此通路，设备拒绝会显示原因。");
        logReason=text(box,"",12,Theme.DANGER);
        logStart=button(box,"REC_START · 开始事件日志",this::startRecording,true,1);
        logStop=button(box,"REC_STOP · 停止事件日志",this::stopRecording,true);
        button(box,"导出事件日志 .txt",this::exportLog,false);
        button(box,"一键切到日志配置 · 8 键 / 关闭延音 / FSR",this::configureLog,true);
        logs=text(box,"接收窗口\n",12,Theme.PANEL_TEXT);logs.setTextIsSelectable(true);logs.setTypeface(Typeface.MONOSPACE);logs.setPadding(dp(14),dp(13),dp(14),dp(13));logs.setBackground(rounded(Theme.PANEL,Theme.R_PANEL));logs.setLineSpacing(dp(2),1);
        installDraftBindings();buildDrawer(root);uiReady=true;showSection(0);showSource(0);refreshControlUi();
        TextView footer=text(sections[0],"FPGA MUSIC LAB  ·  孤独摇滚 · 让灵感在指尖发声",11,MUTED);footer.setGravity(Gravity.CENTER);footer.setLetterSpacing(0.06f);footer.setBackground(rounded(0x8cfff6fb,Theme.R_CHIP));
    }
    private Button segment(LinearLayout box,String label,Runnable action,boolean lock){
        Button button=button(box,label,action,lock);((SegmentButton)button).selection(ControlState.Selection.OFF);return button;
    }
    private LinearLayout segmentGroup(LinearLayout parent){
        LinearLayout group=new LinearLayout(this);group.setOrientation(LinearLayout.VERTICAL);group.setPadding(dp(3),dp(3),dp(3),dp(3));
        GradientDrawable border=rounded(Theme.SURFACE_ALT,Theme.R_BUTTON);border.setStroke(dp(1),Theme.GHOST_LINE);group.setBackground(border);
        parent.addView(group,new LinearLayout.LayoutParams(-1,-2));return group;
    }
    private void buildPerformance(){
        LinearLayout tabs=segmentGroup(sections[1]);LinearLayout buttons=row(tabs);String[] names={"触摸","红外","手势"};
        for(int source=0;source<3;source++){
            final int index=source;sourceButtons[source]=segment(buttons,names[source],()->showSource(index),false);
            LinearLayout page=new LinearLayout(this);page.setOrientation(LinearLayout.VERTICAL);sourcePages[source]=page;sections[1].addView(page);
            for(int group=0;group<7;group++){
                LinearLayout box=card(page,""+(group+1),GROUP_NAMES[group],null);sourceGroups[source][group]=box;
                text(box,source==0?"作用于：触摸键盘":"作用于：红外 + 手势（共用一套参数）",12,MUTED);
            }
        }
        unavailable(sourceGroups[0][2],"本音源暂不支持音色切换：当前只有正弦。由阶段 E1 补齐，成本：中。");
        text(sourceGroups[1][0],"固定 8 路光束触发；当前无需设置触发模式。",13,MUTED);
        for(int source=1;source<3;source++){
            text(sourceGroups[source][1],"支持混音页的共享移调与 A4 标准音；逐弦定弦和逐声部弯音尚未实现，须在 E 的 100 CLS 预算内另作评估。",13,MUTED);
            unavailable(sourceGroups[source][5],"本音源暂不支持 HOLD / POLY：使用固定的 32 复音与音符时长。延音与复音分源列入阶段 E 资源审查，成本按高类风险处理、尚未测量；未获预算前不启用。");
        }
        for(int source=0;source<3;source++)unavailable(sourceGroups[source][6],source==0?
            "本音源暂不支持独立轨道增益、震音和逐音力度。由阶段 E4 补齐，成本：低；当前可在“声音”调总音量，在“表情”设置 FSR 用途。":
            "本音源暂不支持独立轨道增益与震音。由阶段 E4 补齐，成本：低。力度 N/A：无压力传感器。");
        LinearLayout future=card(sections[2],"PITCH","移调、标准音、律制与震音",null);
        unavailable(future,"待固件支持：由阶段 C6～C8 / E4 补齐，成本：免～低；资源测试通过后再启用。");
    }
    private void unavailable(LinearLayout parent,String description){
        TextView notice=text(parent,description,13,MUTED);notice.setBackground(rounded(Theme.DISABLED_BG,Theme.R_CHIP));notice.setPadding(dp(12),dp(12),dp(12),dp(12));
        notice.setEnabled(false);notice.setContentDescription(description);
    }
    private void moveTo(View view,LinearLayout parent){
        if(view==null||view.getParent()==parent)return;
        if(view.getParent()!=null)((ViewGroup)view.getParent()).removeView(view);parent.addView(view);
    }
    private void showSource(int source){
        currentSource=source;
        for(int n=0;n<3;n++){sourcePages[n].setVisibility(n==source?View.VISIBLE:View.GONE);((SegmentButton)sourceButtons[n]).selection(n==source?ControlState.Selection.CONFIRMED:ControlState.Selection.OFF);sourceButtons[n].setContentDescription(new String[]{"触摸","红外","手势"}[n]+(n==source?"，当前页签":"，切换页签"));if(Build.VERSION.SDK_INT>=30)sourceButtons[n].setStateDescription(n==source?"当前页签":"未选中");}
        int target=source==0?0:1;moveTo(adsrPanel,sourceGroups[source][3]);adsrTarget.setSelection(target);updateAdsr(adsrDrafts[target]);
        if(source!=0){moveTo(sensorTonePanel,sourceGroups[source][2]);moveTo(sensorExpressionPanel,sourceGroups[source][4]);}
        refreshControlUi();
    }
    private void showSection(int section){
        currentSection=section;for(int n=0;n<6;n++)sections[n].setVisibility(n==section?View.VISIBLE:View.GONE);
        sectionTitle.setText((section+1)+" · "+SECTION_NAMES[section]);contentScroll.scrollTo(0,0);refreshControlUi();
        main.removeCallbacks(displayPoll);if(section==4)scheduleDisplayPoll();
    }
    private void buildDrawer(FrameLayout root){
        drawerOverlay=new FrameLayout(this);drawerOverlay.setVisibility(View.GONE);drawerOverlay.setElevation(dp(12));root.addView(drawerOverlay,new FrameLayout.LayoutParams(-1,-1));
        View scrim=new View(this);scrim.setBackgroundColor(Theme.DRAWER_SCRIM);scrim.setContentDescription("关闭分区导航");scrim.setOnClickListener(v->closeDrawer());drawerOverlay.addView(scrim,new FrameLayout.LayoutParams(-1,-1));
        drawer=new LinearLayout(this);drawer.setOrientation(LinearLayout.VERTICAL);drawer.setBackground(rounded(Theme.SURFACE,0));drawer.setPadding(dp(12),dp(12),dp(12),dp(12));drawer.setClickable(true);
        FrameLayout.LayoutParams drawerLp=new FrameLayout.LayoutParams(dp(280),-1,Gravity.START);drawerOverlay.addView(drawer,drawerLp);
        text(drawer,"当前生效设置",18,INK);settingsSummary=text(drawer,"",12,MUTED);
        ScrollView navScroll=new ScrollView(this);drawer.addView(navScroll,new LinearLayout.LayoutParams(-1,0,1));LinearLayout nav=new LinearLayout(this);nav.setOrientation(LinearLayout.VERTICAL);navScroll.addView(nav);
        for(int n=0;n<6;n++){final int section=n;navButtons[n]=segment(nav,(n+1)+" · "+SECTION_NAMES[n],()->{showSection(section);closeDrawer();},false);}
        button(drawer,"关闭导航",this::closeDrawer,false);
        drawerOverlay.setOnApplyWindowInsetsListener((view,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());drawerLp.topMargin=safe.top;drawerLp.bottomMargin=safe.bottom;drawerLp.leftMargin=safe.left;drawerLp.rightMargin=safe.right;}
            else{drawerLp.topMargin=insets.getSystemWindowInsetTop();drawerLp.bottomMargin=insets.getSystemWindowInsetBottom();drawerLp.leftMargin=insets.getSystemWindowInsetLeft();drawerLp.rightMargin=insets.getSystemWindowInsetRight();}
            drawer.setLayoutParams(drawerLp);return insets;
        });
    }
    private int drawerOffset(){return getResources().getConfiguration().getLayoutDirection()==View.LAYOUT_DIRECTION_RTL?dp(280):-dp(280);}
    private void openDrawer(){
        drawerOpen=true;drawerOverlay.animate().cancel();drawer.animate().cancel();drawerOverlay.setVisibility(View.VISIBLE);drawerOverlay.requestApplyInsets();
        drawer.setTranslationX(drawerOffset());drawer.animate().translationX(0).setDuration(180).start();
        contentScroll.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);navButtons[currentSection].requestFocus();
    }
    private void closeDrawer(){
        drawerOpen=false;drawer.animate().translationX(drawerOffset()).setDuration(180).withEndAction(()->{if(!drawerOpen)drawerOverlay.setVisibility(View.GONE);}).start();
        contentScroll.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_AUTO);
    }
    @Override public void onBackPressed(){if(drawerOpen)closeDrawer();else super.onBackPressed();}
    private Button findButton(View root,String label){
        if(root instanceof Button&&((Button)root).getText().toString().equals(label))return (Button)root;
        if(root instanceof ViewGroup){ViewGroup group=(ViewGroup)root;for(int n=0;n<group.getChildCount();n++){Button found=findButton(group.getChildAt(n),label);if(found!=null)return found;}}
        return null;
    }
    private Button findButton(String label){for(LinearLayout section:sections){Button found=findButton(section,label);if(found!=null)return found;}throw new IllegalStateException(label);}
    private void bindDraft(String key,int section,String label,Supplier<String> draft,View... inputs){
        Button apply=findButton(label);LinearLayout parent=(LinearLayout)apply.getParent();TextView badge=new TextView(this);badge.setTextSize(10);badge.setTextColor(Theme.PINK_INK);badge.setGravity(Gravity.END);parent.addView(badge,parent.indexOfChild(apply));
        draftBindings.add(new DraftBinding(key,section,apply,badge,draft));controlState.edit(key,section,draft.get());
        String scope=key.equals("perf_tuning")?"作用于：红外 + 手势（共享移调与标准音）":section==2||section==4?"作用于：全局混音":key.equals("tone")||key.equals("vibrato")||key.equals("bank")||key.equals("perf_vib")?"作用于：红外 + 手势（共用一套参数）":"作用于：触摸键盘";
        TextView scopeLabel=new TextView(this);scopeLabel.setText(scope);scopeLabel.setTextSize(12);scopeLabel.setTextColor(MUTED);parent.addView(scopeLabel,parent.indexOfChild(apply)+1);
        for(View input:inputs){deviceInputs.add(input);if(input instanceof Spinner){Spinner spinner=(Spinner)input;AdapterView.OnItemSelectedListener previous=spinner.getOnItemSelectedListener();spinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
                public void onItemSelected(AdapterView<?> p,View view,int position,long id){if(previous!=null)previous.onItemSelected(p,view,position,id);refreshControlUi();}
                public void onNothingSelected(AdapterView<?> p){if(previous!=null)previous.onNothingSelected(p);}
            });}else if(input instanceof EditText)((EditText)input).addTextChangedListener(new TextWatcher(){
                public void beforeTextChanged(CharSequence text,int start,int count,int after){}public void onTextChanged(CharSequence text,int start,int before,int count){refreshControlUi();}public void afterTextChanged(Editable text){}
            });}
    }
    private String choice(Spinner spinner){return ""+spinner.getSelectedItemPosition();}
    private String clean(EditText input){return ControlState.numbers(input.getText().toString());}
    private String adsrValue(int target){AdsrProfile p=adsrDrafts[target];return p.attack+","+p.decay+","+p.sustain+","+p.release;}
    private void installDraftBindings(){
        bindDraft("perf_pitch",1,"应用弯音与滑音",this::pitchDraft,performanceBars[0],performanceBars[1]);
        bindDraft("perf_vib",1,"应用颤音参数",this::vibratoDraft,performanceBars[2],performanceBars[3],performanceBars[4]);
        bindDraft("perf_echo",2,"应用回声抽头",()->choice(echoChoice),echoChoice);
        bindDraft("perf_tuning",2,"应用移调与标准音",()->""+tuningDraft(),tuningBar,standardPitch);
        bindDraft("touch",1,"应用 8 / 16 键模式",()->choice(touchMode),touchMode);
        bindDraft("serial",1,"应用串行极性",()->choice(serialPolarity),serialPolarity);
        bindDraft("pressure",1,"应用压力用途",()->choice(pressureChoice),pressureChoice);
        bindDraft("hold",1,"应用延音 / 踏板",()->choice(holdChoice),holdChoice);
        bindDraft("poly",1,"应用复音上限",()->polyChoice.getSelectedItem().toString(),polyChoice);
        bindDraft("effect",2,"应用音效与湿度",()->choice(effectChoice)+","+wetBar.getProgress(),effectChoice,wetBar);
        bindDraft("volume",2,"应用总音量",()->""+volumeBar.getProgress(),volumeBar);
        bindDraft("analog",2,"应用模拟输入用途",()->choice(analogChoice),analogChoice);
        bindDraft("cal",2,"应用滑杆端点标定",()->clean(calibrationInput),calibrationInput);
        bindDraft("mapping",1,"应用七键映射",()->clean(mappingInput),mappingInput,mappingTarget,mappingKeyboard);
        bindDraft("tone",1,"应用音源音色",()->choice(gestureTone),gestureTone);
        bindDraft("vibrato",1,"应用音源颤音",()->choice(gestureVibrato),gestureVibrato);
        bindDraft("bank",1,"应用手势音符组",()->choice(gestureBank),gestureBank);
        bindDraft("xy",4,"应用所选轨迹参数",()->choice(xyRatio)+","+(xyRatio.getSelectedItemPosition()==0?0:xyPhase.getSelectedItemPosition()),xyRatio,xyPhase);
        controlState.edit("page",4,"0");
        adsrApply=findButton("应用 ADSR 到下一次发音");adsrBadge=text(adsrPanel,"",10,Theme.PINK_INK);adsrBadge.setGravity(Gravity.END);
        deviceInputs.addAll(Arrays.asList(adsrBars));deviceInputs.add(adsrCurve);deviceInputs.addAll(Arrays.asList(bendBars));
        for(int target=0;target<2;target++)controlState.edit("adsr"+target,1,adsrValue(target));
        for(int key=0;key<7;key++)controlState.edit("bend"+key,1,""+voiceBend.value(key));
    }
    private void refreshControlUi(){
        if(!uiReady)return;
        boolean connected=link.connected();controlState.connected(connected);controlState.busy(busy);
        for(DraftBinding binding:draftBindings)controlState.edit(binding.key,binding.section,binding.draft.get());
        DeviceControls c=confirmedControls;
        String[] keys={"touch","pressure","hold","poly","effect","volume","analog","serial","cal","mapping"};
        String[] confirmed=c==null?new String[10]:new String[]{""+c.mode16,""+c.pressure,""+c.hold,""+c.poly,c.effect+","+c.wet,""+c.volume,""+c.analog,confirmedSerial,confirmedCalibration,mapping==null?null:join(mapping)};
        if(c==null)confirmed[9]=mapping==null?null:join(mapping);
        for(int n=0;n<keys.length;n++)controlState.confirm(keys[n],connected?confirmed[n]:null);
        for(String key:new String[]{"tone","vibrato","bank"})controlState.confirm(key,connected?acknowledged.get(key):null);
        controlState.confirm("perf_pitch",connected&&confirmedPitch!=null?PerformanceParams.values(Arrays.copyOf(confirmedPitch,3)):null);
        controlState.confirm("perf_vib",connected&&confirmedVibrato!=null?PerformanceParams.values(confirmedVibrato):null);
        controlState.confirm("perf_echo",connected&&confirmedEcho!=null?""+confirmedEcho[0]:null);
        controlState.confirm("perf_tuning",connected&&confirmedPitch!=null?""+confirmedPitch[3]:null);
        for(int target=0;target<2;target++){String key="adsr"+target;controlState.edit(key,1,adsrValue(target));controlState.confirm(key,connected?acknowledged.get(key):null);}
        for(int key=0;key<7;key++){controlState.edit("bend"+key,1,""+voiceBend.value(key));controlState.confirm("bend"+key,connected&&bendConfirmed[key]!=null?""+bendConfirmed[key]:null);}
        for(DraftBinding binding:draftBindings){boolean dirty=controlState.dirty(binding.key);binding.badge.setText(dirty?"•待发送"+(controlState.confirmed(binding.key)==null?" · 设备值未知":" · 设备："+controlState.confirmed(binding.key)):"✓ 已确认");binding.badge.setTextColor(dirty?Theme.PINK_INK:Theme.MUTED);((SegmentButton)binding.apply).selection(dirty?ControlState.Selection.DRAFT:ControlState.Selection.OFF);binding.apply.setEnabled(controlState.enabled());}
        String adsr="adsr"+(currentSource==0?0:1);boolean adsrDirty=controlState.dirty(adsr);adsrBadge.setText(adsrDirty?"•待发送 · 包络草稿":"✓ 包络已确认");((SegmentButton)adsrApply).selection(adsrDirty?ControlState.Selection.DRAFT:ControlState.Selection.OFF);
        adsrApply.setEnabled(controlState.enabled());
        for(int n=0;n<4;n++){((SegmentButton)pageButtons[n]).selection(controlState.selection("page",""+n));pageButtons[n].setEnabled(controlState.enabled());}
        for(int n=0;n<6;n++){((SegmentButton)xyButtons[n]).selection(controlState.selection("xy",XY_RATIOS[n]+","+XY_PHASES[n]));xyButtons[n].setEnabled(controlState.enabled());}
        for(int n=0;n<6;n++){boolean pending=controlState.pending(n);((SegmentButton)navButtons[n]).pending(pending);((SegmentButton)navButtons[n]).selection(n==currentSection?ControlState.Selection.CONFIRMED:ControlState.Selection.OFF);navButtons[n].setContentDescription(SECTION_NAMES[n]+(n==currentSection?"，当前分区":"")+(pending?"，有待发送草稿":""));if(Build.VERSION.SDK_INT>=30)navButtons[n].setStateDescription(n==currentSection?"当前分区":"未选中");}
        connectionDot.setBackground(rounded(connected?Theme.CONNECTED:Theme.DISABLED_FG,8));connectionDot.setContentDescription(connected?"HC-05 已连接":"HC-05 未连接");headerPending.setVisibility(controlState.pending(currentSection)?View.VISIBLE:View.INVISIBLE);
        settingsSummary.setText(!connected?"未连接，以下均为待发送草稿":(c==null?"演奏状态尚未读取":c.summary())+"\n七键："+(mapping==null?"未知":join(mapping))+"\n弯音："+bendSummary()+"\n显示："+(controlState.confirmed("page")==null?"未知":LedState.page(Integer.parseInt(controlState.confirmed("page")),false))+"\nXY："+(controlState.confirmed("xy")==null?"未知":controlState.confirmed("xy")));
        updateTakeWorkflow();
        refreshMappingKeyboard();
        logReason.setText(TakeWorkflow.logBlockReason(c));logStart.setEnabled(controlState.enabled()&&!recording&&!recordDraining&&TakeWorkflow.logBlockReason(c).isEmpty());logStop.setEnabled(controlState.enabled()&&recording&&!recordDraining);
    }
    private String bendSummary(){StringBuilder result=new StringBuilder();for(Integer value:bendConfirmed){if(result.length()>0)result.append('/');result.append(value==null?"?":value);}return result+" 音分";}
    private void editMappedNote(int note){
        try{int[] draft=SongCodec.parseMapping("MAP,"+clean(mappingInput));int key=mappingTarget.getSelectedItemPosition();draft[key]=note;mappingInput.setText(join(draft));setStatus("K"+(key+1)+" 的映射草稿："+ChromaticKeys.name(note)+"；点击应用后发送");}
        catch(IllegalArgumentException e){alert("请先在高级入口填写7个有效 MIDI 音高（60～72），再点琴键修改");}
    }
    private void refreshMappingKeyboard(){
        if(mappingKeyboard==null)return;
        try{int[] draft=SongCodec.parseMapping("MAP,"+clean(mappingInput));mappingKeyboard.highlight(draft[Math.max(0,mappingTarget.getSelectedItemPosition())]);}
        catch(IllegalArgumentException e){mappingKeyboard.highlight(-1);}
    }
    private void updateTakeWorkflow(){
        TakeWorkflow flow=new TakeWorkflow(confirmedControls,confirmedTake);takeReason.setText(!link.connected()?"请先连接 HC-05":flow.reason);
        boolean configure=confirmedControls!=null&&confirmedControls.extended&&(confirmedControls.hold==2||confirmedControls.poly!=16);
        takeConfigure.setVisibility(configure?View.VISIBLE:View.GONE);takeConfigure.setEnabled(controlState.enabled()&&confirmedTake!=null&&!confirmedTake.busy()&&confirmedTake.confirmation()==0);
        TakeWorkflow.Step[] steps={flow.record,flow.stop,flow.play,flow.save};boolean[] enabled={flow.canRecord,flow.canStop,flow.canPlay,flow.canSave};String[] labels={"1 · 开始录制","2 · 停止","3 · 回放","4 · 保存到板上 Flash"};
        for(int n=0;n<4;n++){takeButtons[n].setText((steps[n]==TakeWorkflow.Step.DONE?"✓ ":"")+labels[n]);((SegmentButton)takeButtons[n]).selection(steps[n]==TakeWorkflow.Step.READY?ControlState.Selection.CONFIRMED:ControlState.Selection.OFF);takeButtons[n].setEnabled(controlState.enabled()&&enabled[n]);takeButtons[n].setContentDescription(labels[n]+(steps[n]==TakeWorkflow.Step.DONE?"，已完成":steps[n]==TakeWorkflow.Step.READY?"，可执行":"，尚不可执行"));}
        findButton("删除已录制内容").setEnabled(controlState.enabled()&&flow.canDelete);
    }
    private void configureTake(){
        holdChoice.setSelection(0);polyChoice.setSelection(4);
        task(()->{link.command("HOLD,0","OK");link.command("POLY,16","OK");readControls();TakeStatus value=RecordingSupport.readEvents(link);main.post(()->showTake(value));},"已切到可录配置，请松开琴键后开始板上事件录制");
    }
    private void configureLog(){
        touchMode.setSelection(0);holdChoice.setSelection(0);polyChoice.setSelection(4);analogChoice.setSelection(0);
        task(()->{link.command("HOLD,0","OK");link.command("TOUCH,8","OK");link.command("ANALOG,0","OK");readControls();},"日志配置已确认；若 REC_START 返回 ERR,MISSING，当前固件未启用日志通路");
    }
    private void acceptLedState(LedState value){
        confirmedLed=value;acceptDisplay(value.activeMode,value.shownRatio,value.shownPhase,(value.flags&2)!=0);
        xyInfo.setText("设备实际："+((value.flags&2)!=0?LedState.xy(value.shownRatio,value.shownPhase):"等待首帧")+"；请求："+LedState.xy(value.ratio,value.phase));
    }
    private void acceptDisplay(int mode,int ratio,int phase,boolean xyValid){
        if(!uiReady)return;
        controlState.observe("page",""+mode);
        if(xyValid){String value=ratio+","+(ratio==0?0:phase);boolean follow=controlState.observe("xy",value);
            if(follow){xyRatio.setSelection(ratio);xyPhase.setSelection(ratio==0?0:phase);}}
        refreshControlUi();
    }
    private void scheduleDisplayPoll(){main.removeCallbacks(displayPoll);if(uiReady&&resumed&&currentSection==4&&link.connected())main.postDelayed(displayPoll,2000);}
    private void pollDisplayState(){
        if(!uiReady||currentSection!=4||!link.connected())return;
        if(busy||recording||recordDraining||takePolling||ledPollPending){scheduleDisplayPoll();return;}
        task(this::readLedState,"显示状态已刷新");scheduleDisplayPoll();
    }
    @Override protected void onResume(){super.onResume();resumed=true;if(uiReady)scheduleDisplayPoll();}
    private void buildLedControls(LinearLayout content){
        LinearLayout preview=card(content,"LIVE","手机实时预览","青蓝紫红随演奏幅度变化。");
        buildLedPreview(preview);
        LinearLayout box=card(content,"LED","显示控制与实时预览","需配套新版 FPGA 位流。手机可直接切页，板上 S2 仍可使用。");
        LinearLayout pageGroup=segmentGroup(box);String[] pageNames={"总览 / 曲谱","波形","XY 轨迹","频谱"};
        for(int n=0;n<4;n+=2){LinearLayout pages=row(pageGroup);for(int k=n;k<n+2;k++){final int mode=k;pageButtons[k]=segment(pages,pageNames[k],()->selectLedPage(mode),true);}}
        button(box,"读取设备显示状态",()->task(this::readLedState,"已读取 FPGA 实际显示状态"),true);
        ledStatus=text(box,"显示状态尚未读取；下方选择框为待发送值。",13,MUTED);
        text(box,"李萨如与实际混音轨迹",18,INK);
        String[] names={"八字","多瓣","圆","椭圆","直线","实际混音"};
        int[] ratios=XY_RATIOS,phases=XY_PHASES;
        LinearLayout presetGroup=segmentGroup(box);
        for(int i=0;i<names.length;i+=2){
            LinearLayout presets=row(presetGroup);
            for(int j=i;j<i+2;j++){
                final int ratio=ratios[j],phase=phases[j];
                xyButtons[j]=segment(presets,names[j],()->applyXy(ratio,phase),true);
            }
        }
        xyRatio=choices(box,"轨迹来源 / X:Y 频率比",new String[]{"AUD · 实际混音延时轨迹","REF · 1:1","REF · 1:2","REF · 2:3"});
        xyRatio.setSelection(2);
        xyPhase=choices(box,"Y 相对 X 的相位差（仅 REF）",new String[]{"0°","45°","90°","135°"});
        xyRatio.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){updateXyControls();refreshControlUi();}
            public void onNothingSelected(AdapterView<?> parent){}
        });
        button(box,"应用所选轨迹参数",()->applyXy(xyRatio.getSelectedItemPosition(),xyPhase.getSelectedItemPosition()),true,1);
        xyInfo=text(box,"尚未发送；列表为待发送值，未读取板上当前参数。",13,MUTED);
        xyInfo.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        text(box,"REF 是 FPGA 生成的参考图形；AUD 随实际演奏变化。收到设备 OK 后才显示发送确认；板上 S2 选图或复位后，请重新应用。",12,MUTED);
        text(box,"S2 长按循环切换总览/曲谱、波形、XY、频谱；XY 页短按选图，其他页短按会重启有效曲谱。",12,MUTED);
        updateXyControls();
    }
    private void buildLedPreview(LinearLayout box){
        text(box,"沿用面板的青蓝紫红色环，为频谱与音源幅度配色。下方百分比为各音源相对幅度，与面板总混音 PK 分开显示。",12,MUTED);
        ledPreview=new SpectrumPreviewView(this);box.addView(ledPreview,new LinearLayout.LayoutParams(-1,dp(356)));
        text(box,"数据来自 FPGA，最多每秒更新 5 次；下载、事件录制或其他命令期间暂停。",12,MUTED);
        ledPreviewInfo=text(box,"预览未开启；画面来自 FPGA 回传，不是手机麦克风。",12,MUTED);
        LinearLayout previewButtons=row(box);
        button(previewButtons,"开启实时预览",this::startLedPreview,true);
        button(previewButtons,"停止预览",()->stopLedPreview("预览已停止。"),false);
    }
    private void selectLedPage(int mode){
        controlState.edit("page",4,""+mode);refreshControlUi();
        task(()->{link.command("VIS,"+mode,"OK");readLedState();},"切页已确认并读取状态；以实际显示页为准");
    }
    private void readLedState()throws Exception{
        LedState value=LedState.parse(link.command("VIS?","VIS"));
        main.post(()->{if(!cancelled && link.connected()){ledStatus.setText("最近读取：\n"+value.description());acceptLedState(value);}});
    }
    private void startLedPreview(){
        if(!link.connected()){alert("请先连接 HC-05，并确认已烧录支持 VIS/VIZ 的新版 FPGA 位流");return;}
        if(ledPreviewRunning)return;
        ledPreviewRunning=true;++ledGeneration;ledLastFrameAt=0;
        ledPreviewInfo.setText("正在查询 FPGA 频谱与幅度…");scheduleLedPreview(0);
    }
    private void stopLedPreview(String reason){
        ledPreviewRunning=false;++ledGeneration;
        main.removeCallbacks(ledPoll);main.removeCallbacks(ledStale);
        if(ledPreview!=null)ledPreview.setFrame(null);
        if(ledPreviewInfo!=null)ledPreviewInfo.setText(reason);
    }
    private void scheduleLedPreview(long delay){
        main.removeCallbacks(ledPoll);if(ledPreviewRunning)main.postDelayed(ledPoll,delay);
    }
    private void pollLedPreview(){
        if(!ledPreviewRunning)return;
        if(!link.connected()){stopLedPreview("蓝牙未连接，预览已停止。");return;}
        if(busy || recording || recordDraining || takePolling || ledPollPending){scheduleLedPreview(200);return;}
        ledPollPending=true;
        final int generation=ledGeneration;
        worker.execute(()->{
            try{
                if(!ledPreviewRunning)return;
                LedFrame frame=LedFrame.parse(link.command("VIZ?","V"));
                main.post(()->{
                    if(generation!=ledGeneration || !ledPreviewRunning || !link.connected())return;
                    ledLastFrameAt=SystemClock.uptimeMillis();ledPreview.setFrame(frame);
                    ledPreviewInfo.setText(frame.spectrumValid()?"FPGA 实时数据 · 最多 5 次/秒":"等待 FPGA 首个完整 FFT 结果…");
                    ledStatus.setText("最近预览："+frame.description());acceptDisplay(frame.mode,frame.ratio,frame.phase,(frame.flags&2)!=0);
                    main.removeCallbacks(ledStale);main.postDelayed(ledStale,1500);
                });
            }catch(Exception e){
                main.post(()->{
                    if(generation!=ledGeneration)return;
                    if(!link.connected()){forgetBendConnection();forgetControls();mapping=null;recordingInterrupted();mapInfo.setText("连接已关闭，请重新连接");}
                    stopLedPreview("预览中断："+e.getMessage());setStatus("预览未完成；请核对新版 FPGA 位流与连接");
                });
            }finally{
                main.post(()->{ledPollPending=false;scheduleLedPreview(200);});
            }
        });
    }
    private void updateXyControls(){
        if(xyRatio!=null)xyRatio.setEnabled(!busy);
        if(xyPhase!=null)xyPhase.setEnabled(!busy && xyRatio.getSelectedItemPosition()>0);
    }
    private void applyXy(int ratio,int phase){
        if(busy)return;
        if(!link.connected()){alert("请先连接 HC-05，再设置 LED 轨迹");return;}
        if(ratio==0)phase=0;
        xyRatio.setSelection(ratio);xyPhase.setSelection(phase);refreshControlUi();
        final String command="XY,"+ratio+","+phase;
        final String description=ratio==0?"AUD · 实际混音延时轨迹":"REF · "+(ratio==1?"1:1":ratio==2?"1:2":"2:3")+"，相位 "+(phase*45)+"°";
        task(()->{
            link.command(command,"OK");
            main.post(()->{if(!cancelled && link.connected())xyInfo.setText("命令已确认："+description+"；以设备已发布图形为准。");});readLedState();
        },"LED 轨迹参数已确认；请在板上 XY 页查看");
    }
    private void buildSongLibrary(LinearLayout box){
        text(box,"分级曲库 · 9 首离线曲目",18,INK);
        libraryTier=choices(box,"选择等级",new String[]{"青铜 · 入门（3 首）","白银 · 进阶（3 首）","黄金 · 挑战（3 首）"});
        libraryTier.setSelection(SongLibrary.Tier.SILVER.ordinal());
        libraryTracks=new Spinner(this);libraryTracks.setContentDescription("选择分级曲库曲目");addSpinner(box,libraryTracks);
        libraryInfo=text(box,"",13,MUTED);
        refreshLibrary(SongLibrary.Tier.SILVER.ordinal());libraryTracks.setSelection(2);
        libraryTracks.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){showLibraryEntry();}
            public void onNothingSelected(AdapterView<?> parent){}
        });
        libraryTier.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){
                if(libraryEntries.isEmpty()||libraryEntries.get(0).tier.ordinal()!=position)refreshLibrary(position);
            }
            public void onNothingSelected(AdapterView<?> parent){}
        });
        button(box,"匹配七键并下载所选曲目",()->{
            if(busy)return;
            if(recording||recordDraining){alert("先停止录制并等待 REC_END，再下载曲谱");return;}
            if(!link.connected()){alert("请先连接 HC-05；也可先载入曲目查看音符");return;}
            SongLibrary.Entry entry=selectedLibraryEntry();if(entry==null)return;
            song=entry.song();showSong();downloadScore(true);
        },true,1);
        text(box,"仅补齐本曲缺少的键位，已覆盖的音高保持原位置；修改后会读回核对，再逐条下载。保存于开发板 RAM，掉电后需重下。",12,MUTED);
        text(box,"匹配曲库可能修改前七个扫描键的音高；恢复钢琴半音阶演奏前，请到“演奏 → 触摸 → 音高”恢复默认映射。",12,MUTED);
        button(box,"载入所选曲目 · 查看后再下载",()->{
            SongLibrary.Entry entry=selectedLibraryEntry();if(entry==null)return;
            song=entry.song();showSong();setStatus("已载入《"+entry.title+"》；尚未下载到开发板");
        },true);
        button(box,"保存所选曲目到文件夹 · CSV",this::exportLibraryScore,true);
        button(box,"查看所选曲目的原谱网页",()->{
            SongLibrary.Entry entry=selectedLibraryEntry();if(entry==null)return;
            try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(entry.sourceUrl)));}
            catch(ActivityNotFoundException e){alert("未找到浏览器；曲库选曲和下载仍可离线使用");}
        },true);
        text(box,"曲目参考 PrintableGarden 的传统／公版旋律，按本设备七键音域改编；等级为本 APP 的练习分级。原有文件夹导入入口见下方。",12,MUTED);
    }
    private void refreshLibrary(int tier){
        libraryEntries=SongLibrary.in(SongLibrary.Tier.values()[tier]);
        List<String> titles=new ArrayList<>();for(SongLibrary.Entry e:libraryEntries)titles.add(e.title);
        libraryTracks.setAdapter(options(titles));showLibraryEntry();
    }
    private SongLibrary.Entry selectedLibraryEntry(){
        int n=libraryTracks.getSelectedItemPosition();return n>=0&&n<libraryEntries.size()?libraryEntries.get(n):null;
    }
    private void showLibraryEntry(){
        SongLibrary.Entry entry=selectedLibraryEntry();if(entry==null)return;
        libraryInfo.setText(entry.englishTitle+"\n"+entry.tier.title+" · "+entry.tier.description+"\n"+entry.time+" 拍 · "+entry.bpm+" BPM · "+
            String.format(Locale.ROOT,"%.2f",entry.song().durationMs()/1000.0)+" 秒\n需要音高："+SongCodec.notes(entry.song().requiredMask())+"\n"+entry.edition);
    }
    private void exportLibraryScore(){
        exportingScore=selectedLibraryEntry();if(exportingScore==null)return;
        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("text/csv");
        intent.putExtra(Intent.EXTRA_TITLE,exportingScore.id+".csv");startActivityForResult(intent,EXPORT_SCORE);
    }
    private void buildBendControls(LinearLayout content){
        LinearLayout box=card(content,"06","七声部弯音","弯音是目标音高偏移。按住和弦时分别调节第 1～7 键；已回读设备时，拖动会限制在设备当前弯音范围内。FSR 全局音高比率继续叠加。");
        text(box,"作用于：前七触摸声部。范围与过渡速率在下方弯音 / 滑音卡片调整；缩小范围后，原草稿须重新拖动或回正再发送。",12,MUTED);
        for(int i=0;i<7;i++){
            final int index=i;bendLabels[i]=text(box,"",13,MUTED);
            SeekBar bar=new SeekBar(this);bendBars[i]=bar;bar.setMax(2400);bar.setProgress(1200);
            bar.setContentDescription("第 "+(i+1)+" 个触摸声部独立音高，上下1200音分");
            bar.setProgressTintList(ColorStateList.valueOf(ACCENT));bar.setThumbTintList(ColorStateList.valueOf(ACCENT));
            box.addView(bar,new LinearLayout.LayoutParams(-1,dp(42)));
            bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar b,int p,boolean fromUser){
                    if(!fromUser)return;
                    int cents=confirmedPitch==null?p-1200:PerformanceParams.clampBend(p-1200,confirmedPitch[0],confirmedPitch[1]);
                    if(cents!=p-1200)b.setProgress(cents+1200);
                    voiceBend.edit(index,cents,link.connected());updateBendLabel(index);
                    if(link.connected())scheduleBend();else setStatus("音高为离线草稿；连接后点击发送全部音高");
                }
                public void onStartTrackingTouch(SeekBar b){}
                public void onStopTrackingTouch(SeekBar b){}
            });updateBendLabel(i);
        }
        text(box,"连线时约每 100ms 发送一个最新位置，逐条等 OK；其他任务期间暂存拖动。未连接时只编辑草稿，重连后须手动发送。已确认值是目标音高，FPGA 平滑过渡；改动持续到再次调节、全部回正或板子复位。",12,MUTED);
        button(box,"发送全部音高",()->{
            final int[] values=voiceBend.snapshot();voiceBend.clearPending();
            for(int cents:values)if(!bendWithinDevice(cents))return;
            task(()->{try{for(int i=0;i<7;i++){link.command(VoiceBend.command(i+1,values[i]),"OK");final int key=i;main.post(()->confirmBend(key,values[key]));}}
                catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"七个声部目标音高均已确认");
        },true,1);
        button(box,"全部回正 · 0 半音",()->{
            voiceBend.clearPending();
            for(int i=0;i<7;i++){voiceBend.edit(i,0,false);bendBars[i].setProgress(1200);updateBendLabel(i);}
            task(()->{try{link.command("BEND_RESET","OK");main.post(()->{for(int i=0;i<7;i++)confirmBend(i,0);});}
                catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"七声部弯音已回正；FSR 全局音高比率继续有效");
        },true);
    }
    private void takeAction(String command){
        if("TAKE_REC".equals(command)&&!new TakeWorkflow(confirmedControls,confirmedTake).canRecord){refreshControlUi();return;}
        task(()->{
            RecordingSupport.readEvents(link);
            if(command!=null)link.command(command,"OK");
            TakeStatus value=RecordingSupport.readEvents(link);
            main.post(()->showTake(value));
        },"录制状态已读取");
    }
    private void buildPhoneRecording(LinearLayout content){
        LinearLayout box=card(content,"PHONE","手机音符录制 · 本地保存 · 导出 MIDI","页面琴键在手机本地发声。保存的是音符事件，不是 WAV 音频；无需连接蓝牙，可在“我的录音”回放、改名、删除和导出。");
        phoneInfo=text(box,"开始手机录制 → 弹奏下方琴键 → 停止 → 回放 → 命名保存。录制前先松开琴键。",13,MUTED);
        text(box,"7白键 + 5黑键为 C4～B4；右侧4个独立踏板条暂作 C5 / D5 / E5 / F5。键号与板上串行扫描顺序一致。",12,MUTED);
        box.addView(new PianoKeyboardView(this,127,this::phoneKey),new LinearLayout.LayoutParams(-1,dp(180)));
        button(box,"开始手机录制",this::startPhoneRecording,false,1);LinearLayout controls=row(box);
        button(controls,"停止录制 / 回放",this::stopPhoneRecording,false);button(controls,"回放当前录制",()->{if(phoneRecording){alert("请先停止手机录制");return;}playPhoneTake(phoneDraft,"当前手机录制");},false,1);
        button(box,"命名并保存录制",()->savePhoneRecording(null),false);button(box,"我的录音 · 回放 / 改名 / 删除",this::showPhoneLibrary,false);
        button(box,"导出当前手机 MIDI",()->exportPhoneTake(phoneDraft,"手机演奏"),false);
        text(box,"每次保存新增一份，数量由手机可用空间决定；每份最多10000个音符。记录音符、节奏、按键时长和力度，回放由手机合成。保存后关闭重开仍可在“我的录音”找到。",12,MUTED);
    }
    private PhonePiano phonePiano(){if(phonePiano==null)phonePiano=new PhonePiano();return phonePiano;}
    private int phoneTime(){return (int)Math.min(Integer.MAX_VALUE,Math.max(0,SystemClock.uptimeMillis()-phoneStart));}
    private void phoneKey(int key,boolean on){
        try{if(on){phonePiano().liveKey(key,true);}else if(phonePiano!=null)phonePiano.liveKey(key,false);
            if(phoneRecording){int ms=phoneTime();if(on){if(!phoneDraft.down(key,100,ms)){stopPhoneRecording();alert("已达到10000个音符，本次手机录制已停止，可回放或保存");}else phoneDirty=true;}else phoneDraft.up(key,ms);}}
        catch(Exception e){alert("手机琴键未完成："+e.getMessage());}
    }
    private void startPhoneRecording(){
        if(phoneBusy){alert("手机录制文件正在处理，请稍候");return;}if(phoneRecording)return;
        if(phoneDraft!=null&&phoneDirty&&phoneDraft.notes()>0){new AlertDialog.Builder(this).setTitle("保留当前手机录制？").setMessage("当前录制尚未保存。")
            .setPositiveButton("保存后开始",(d,w)->savePhoneRecording(this::beginPhoneRecording)).setNegativeButton("放弃并开始",(d,w)->beginPhoneRecording()).setNeutralButton("取消",null).show();return;}
        beginPhoneRecording();
    }
    private void beginPhoneRecording(){if(phonePiano!=null)phonePiano.stop();phoneDraft=new PhoneTake();phoneRecording=true;phoneDirty=false;phoneStart=SystemClock.uptimeMillis();getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);updatePhoneRecordingTime(phoneStart);}
    private void updatePhoneRecordingTime(long start){if(!phoneRecording||start!=phoneStart)return;phoneInfo.setText(String.format(Locale.CHINA,"手机录制中 · %.1f秒 · %d音符",phoneTime()/1000.0,phoneDraft.notes()));main.postDelayed(()->updatePhoneRecordingTime(start),250);}
    private void stopPhoneRecording(){
        if(phonePiano!=null)phonePiano.stop();if(phoneRecording){phoneDraft.finish(phoneTime());phoneRecording=false;phoneDirty=phoneDraft.notes()>0;}
        if(phoneDraft!=null)phoneInfo.setText(String.format(Locale.CHINA,"当前手机录制 · %d音符 · %.2f秒%s",phoneDraft.notes(),phoneDraft.duration()/1000.0,phoneDirty?" · 未保存":""));
        if(!busy)getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private void playPhoneTake(PhoneTake take,String name){
        if(take==null||!take.finished()||take.notes()==0){alert("请先完成一段手机录制，或从“我的录音”选择");return;}
        try{phonePiano().play(take,()->main.post(()->phoneInfo.setText("手机回放完成："+name)));phoneInfo.setText("手机回放："+name);}
        catch(Exception e){alert("手机回放失败："+e.getMessage());}
    }
    private PhoneTakeStore phoneStore()throws IOException {if(phoneStore==null)phoneStore=new PhoneTakeStore(new File(getFilesDir(),"phone-recordings"));return phoneStore;}
    private void phoneWork(Work action,String done){if(phoneBusy){alert("手机录制文件正在处理，请稍候");return;}phoneBusy=true;phoneInfo.setText("正在处理手机录制…");phoneWorker.execute(()->{try{action.run();main.post(()->{phoneBusy=false;if(!phoneRecording&&(phonePiano==null||!phonePiano.replaying()))phoneInfo.setText(done);});}catch(Exception e){main.post(()->{phoneBusy=false;phoneInfo.setText("未完成："+e.getMessage()+"；当前录制仍保留");alert(e.getMessage());});}});}
    private void savePhoneRecording(Runnable after){
        if(phoneRecording||phoneDraft==null||phoneDraft.notes()==0){alert("请先停止手机录制，并至少录入一个音符");return;}final PhoneTake take=phoneDraft;
        EditText name=new EditText(this);name.setSingleLine(true);name.setText("手机演奏 "+new java.text.SimpleDateFormat("MM-dd HH:mm:ss",Locale.CHINA).format(new Date()));
        new AlertDialog.Builder(this).setTitle("保存手机录制").setView(name).setPositiveButton("新增保存",(d,w)->{final String title=name.getText().toString();phoneWork(()->{phoneStore().save(title,take);main.post(()->{if(phoneDraft==take)phoneDirty=false;if(after!=null)after.run();});},"手机录制已新增保存，可在“我的录音”查看");}).setNegativeButton("取消",null).show();
    }
    private void showPhoneLibrary(){phoneWork(()->{List<PhoneTakeStore.Entry> entries=phoneStore().list();main.post(()->{if(entries.isEmpty()){alert("暂无已保存的手机录制");return;}String[] labels=new String[entries.size()];for(int n=0;n<labels.length;n++)labels[n]=entries.get(n).toString();new AlertDialog.Builder(this).setTitle("我的录音 · "+entries.size()+"份").setItems(labels,(d,n)->phoneEntryActions(entries.get(n))).setNegativeButton("关闭",null).show();});},"已读取手机录制列表");}
    private void phoneEntryActions(PhoneTakeStore.Entry entry){new AlertDialog.Builder(this).setTitle(entry.name).setItems(new String[]{"手机回放","修改名称","导出 MIDI","删除"},(d,choice)->{
        if(choice==0)phoneWork(()->{PhoneTake take=phoneStore().load(entry);main.post(()->playPhoneTake(take,entry.name));},"已载入手机录制："+entry.name);
        else if(choice==1){EditText name=new EditText(this);name.setSingleLine(true);name.setText(entry.name);new AlertDialog.Builder(this).setTitle("修改录制名称").setView(name).setPositiveButton("保存名称",(a,b)->{final String title=name.getText().toString();phoneWork(()->phoneStore().rename(entry,title),"录制名称已更新");}).setNegativeButton("取消",null).show();}
        else if(choice==2)phoneWork(()->{PhoneTake take=phoneStore().load(entry);main.post(()->exportPhoneTake(take,entry.name));},"已载入待导出的手机录制");
        else new AlertDialog.Builder(this).setTitle("删除这份手机录制？").setMessage(entry.name).setPositiveButton("确认删除",(a,b)->phoneWork(()->phoneStore().delete(entry),"所选手机录制已删除")).setNegativeButton("取消",null).show();
    }).show();}
    private void exportPhoneTake(PhoneTake take,String name){
        if(take==null||!take.finished()||take.notes()==0){alert("请先完成手机录制");return;}
        try{phoneExportMidi=take.midi();Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("audio/midi");intent.putExtra(Intent.EXTRA_TITLE,name.replaceAll("[\\\\/:*?\"<>|]","_")+".mid");startActivityForResult(intent,EXPORT_PHONE);}
        catch(Exception e){alert("MIDI 导出未开始："+e.getMessage());}
    }
    private void showTake(TakeStatus value){
        confirmedTake=value;takeInfo.setText(value.description());refreshControlUi();
        if(value.confirmation()!=0){
            new AlertDialog.Builder(this).setTitle(value.confirmation()==1?"覆盖原录制？":"删除原录制？")
                .setMessage("确认后操作板上的录制内容。新录制只有在 Flash 校验成功后才算保存。")
                .setPositiveButton("确认",(d,w)->takeAction("TAKE_YES"))
                .setNegativeButton("取消",(d,w)->takeAction("TAKE_NO"))
                .setOnCancelListener(d->takeAction("TAKE_NO")).show();
        }else if(value.busy() && !takePolling){
            takePolling=true;
            main.postDelayed(()->{takePolling=false;if(link.connected()){if(!busy)takeAction(null);else showTake(value);}},750);
        }
    }
    private void updateBendLabel(int i){
        if(bendLabels[i]==null)return;
        Integer confirmed=bendConfirmed[i];
        bendLabels[i].setText("声部 "+(i+1)+" / OUT"+(i+1)+" · "+VoiceBend.label(voiceBend.value(i))+"\n"+
            (confirmed==null?"设备目标未确认 · •待发送": "已确认目标："+VoiceBend.label(confirmed)+(confirmed!=voiceBend.value(i)?" · •待发送":"")));
        refreshControlUi();
    }
    private void confirmBend(int key,int cents){if(cancelled||!link.connected())return;bendConfirmed[key]=cents;updateBendLabel(key);}
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
        if(!bendWithinDevice(cents)){voiceBend.clearPending();return;}
        task(()->{try{link.command(VoiceBend.command(key+1,cents),"OK");main.post(()->confirmBend(key,cents));}
            catch(Exception e){main.post(this::forgetBendConnection);throw e;}},"声部 "+(key+1)+" 目标音高已确认："+VoiceBend.label(cents));
        if(voiceBend.hasPending())scheduleBend();
    }
    private boolean bendWithinDevice(int cents){
        if(confirmedPitch==null){setStatus("请先读取设备演奏参数，再发送弯音");return false;}
        if(PerformanceParams.bendAllowed(cents,confirmedPitch[0],confirmedPitch[1]))return true;
        setStatus("弯音草稿超出设备已确认范围，请重新拖动该声部或全部回正");return false;
    }
    private void buildAdsrControls(LinearLayout content){
        LinearLayout box=card(content,"05","ADSR 包络编辑","滑块或拖动曲线控制点编辑；曲线表示待发送参数，点击应用后新发音生效。");
        adsrPanel=box;adsrTarget=new Spinner(this);adsrTarget.setAdapter(options(Arrays.asList("触摸键盘","红外 / 手势")));
        text(box,"作用于当前演奏页签；红外 + 手势共用一套参数。",12,MUTED);
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
        adsrCurve.setProfile(profile);loadingAdsr=false;refreshControlUi();
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
    private void connectSelected(){
        if(recording||recordDraining){alert("请先停止录制并等待 REC_END，再重新连接；也可点断开以中断此次录制。");return;}
        int selected=devices.getSelectedItemPosition();if(selected<0||selected>=paired.size()){alert("请先刷新并选择已配对 HC-05");return;}
        BluetoothDevice device=paired.get(selected);forgetBendConnection();forgetControls();mapping=null;mapInfo.setText("连接中，尚未读取键位");
        task(()->{link.connect(device);link.command("PING","PONG");readMapping();readControls();readPerformance();
            try{TakeStatus take=RecordingSupport.readEvents(link);main.post(()->showTake(take));}
            catch(RecordingSupport.UnsupportedFeatureException e){main.post(()->takeInfo.setText(e.getMessage()));}
            readLedState();main.post(()->{refreshControlUi();scheduleDisplayPoll();});
        },"HC-05 已连接，已读取键位、演奏模式和板上事件功能");
    }
    private void setStatus(String s){status.setText(s);if(workflowStatus!=null)workflowStatus.setText(s);refreshControlUi();}
    private void setBusy(boolean value){
        busy=value;controlState.busy(value);for(Button button:lockedButtons)button.setEnabled(!value);
        libraryTier.setEnabled(!value);libraryTracks.setEnabled(!value);for(View input:deviceInputs)input.setEnabled(!value);
        updateXyControls();refreshControlUi();
        getWindow().setFlags(value||phoneRecording?WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON:0,WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private interface Work {void run()throws Exception;}
    private void task(Work work,String done){if(busy)return;setBusy(true);cancelled=false;setStatus("处理中…");worker.execute(()->{try{work.run();main.post(()->{setBusy(false);if(!cancelled)setStatus(done);});}catch(Exception e){main.post(()->{setBusy(false);if(!cancelled){if(!link.connected()){mapping=null;forgetControls();recordingInterrupted();mapInfo.setText("连接已关闭，请重新连接后重试");}setStatus("未完成："+e.getMessage());alert(e.getMessage());}});}});}
    private void recordingInterrupted(){if(recording||recordDraining){recordingOverflow=true;recordingCompleted=false;}recording=false;recordDraining=false;}
    private void disconnect(){forgetBendConnection();forgetControls();cancelled=true;link.close();mapping=null;recordingInterrupted();mapInfo.setText("尚未连接");setStatus("已断开。下载未提交时旧谱保留；重新连接后可重新下载。");}
    private String pitchDraft(){
        int range=performanceBars[0].getProgress();
        int step=defaultGlide?PerformanceParams.DEFAULT_SLEW:PerformanceParams.glideStep(range,performanceBars[1].getProgress());
        return PerformanceParams.rangeLower(range)+","+PerformanceParams.rangeUpper(range)+","+step;
    }
    private int tuningDraft(){return PerformanceParams.tuningRatio(tuningBar.getProgress()-12,new int[]{415,432,440,442,466}[standardPitch.getSelectedItemPosition()]);}
    private String vibratoDraft(){return PerformanceParams.vibratoValues(performanceBars[2].getProgress()/10.0,performanceBars[3].getProgress(),performanceBars[4].getProgress());}
    private void buildPerformanceControls(){
        LinearLayout pitch=card(sourceGroups[0][1],"PITCH","弯音范围与滑音","作用于：前七个扫描键。滑音时间标定为原音到所选正向弯音上限；距离较短或下行时，实际时间会更短。修改范围前松键并停止曲谱。");
        performanceState=text(pitch,"演奏参数尚未读取；下方均为草稿。需要配套参数版位流。",13,MUTED);
        button(pitch,"读取设备演奏参数",()->task(this::readPerformance,"已读取弯音、滑音与颤音参数"),true);
        performanceTempoLabel=text(pitch,"",13,INK);performanceTempo=new SeekBar(this);performanceTempo.setMin(20);performanceTempo.setMax(300);performanceTempo.setProgress(125);pitch.addView(performanceTempo);
        performanceTempo.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean user){updatePerformanceLabels();}
            public void onStartTrackingTouch(SeekBar bar){}public void onStopTrackingTouch(SeekBar bar){}
        });
        button(pitch,"参考速度恢复 125 BPM",()->performanceTempo.setProgress(125),false);
        LinearLayout tuning=card(sections[2],"TUNE","移调与 A4 标准音","作用于红外与手势（共用一套参数）。为保留四档回声，触摸键移调未保留，触摸键与吉他保持原音高。本版仍与电位器音高用途 ANALOG=2 互斥。");
        tuningLabel=text(tuning,"移调 0 半音（0 音分）",13,INK);tuningBar=new SeekBar(this);tuningBar.setMax(24);tuningBar.setProgress(12);tuning.addView(tuningBar);
        tuningBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar b,int value,boolean user){tuningLabel.setText(String.format(Locale.ROOT,"移调 %+d 半音（%+d 音分）",value-12,(value-12)*100));refreshControlUi();}
            public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}
        });
        standardPitch=choices(tuning,"A4 标准音",new String[]{"415 Hz","432 Hz","440 Hz","442 Hz","466 Hz"});standardPitch.setSelection(2);
        button(tuning,"移调恢复 0 半音并应用当前 A4",()->{tuningBar.setProgress(12);applyPerformance("PITCH,,,,"+tuningDraft());},true);
        button(tuning,"A4 恢复 440 Hz 并应用当前移调",()->{standardPitch.setSelection(2);applyPerformance("PITCH,,,,"+tuningDraft());},true);
        button(tuning,"应用移调与标准音",()->applyPerformance("PITCH,,,,"+tuningDraft()),true);
        button(tuning,"移调 / 标准音同时恢复 0 / 440",()->{tuningBar.setProgress(12);standardPitch.setSelection(2);applyPerformance("PITCH,,,,16384");},true);
        int[] minima={50,5,30,5,0},maxima={1200,500,80,100,800},defaults={1200,21,60,27,0};
        String[] names={"弯音范围","滑音时间","颤音速率","颤音深度","起振延迟"};
        for(int n=0;n<5;n++){
            final int parameter=n;LinearLayout parent=n<2?pitch:sensorExpressionPanel;
            performanceLabels[n]=text(parent,"",13,INK);SeekBar bar=new SeekBar(this);performanceBars[n]=bar;
            bar.setMin(minima[n]);bar.setMax(maxima[n]);bar.setProgress(defaults[n]);bar.setContentDescription(names[n]);parent.addView(bar);
            bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar b,int value,boolean user){if(parameter<2&&user)defaultGlide=false;updatePerformanceLabels();refreshControlUi();}
                public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}
            });
            button(parent,names[n]+" · 恢复默认",()->restorePerformance(parameter),true);
        }
        button(pitch,"应用弯音与滑音",()->applyPerformance("PITCH,"+pitchDraft()),true);
        text(sensorExpressionPanel,"颤音改变音高，震音改变振幅；本栏只调整颤音。全局震音另受资源预算限制，未启用。应用参数会重新计起振延迟，延迟结束后深度逐帧渐入。",12,MUTED);
        button(sensorExpressionPanel,"应用颤音参数",()->applyPerformance("VIB,"+vibratoDraft()),true);
        buildEchoControls();
        text(pitch,"TAKE不保存新增演奏参数；录制前请记下移调和颤音设置，回放前恢复相同值。",12,MUTED);
        updatePerformanceLabels();
    }
    private void buildEchoControls(){
        LinearLayout box=card(sections[2],"ECHO","四档回声","作用于全局混音，需在音效栏启用回声。长三档只降低湿声采样率，干声保持原样；最长档湿声采样上限约4.07 kHz，低通还会削弱高频。切换档位会清除旧尾音。");
        echoState=text(box,"设备回声档位尚未回读",13,MUTED);
        echoChoice=choices(box,"回声名义延时",new String[]{"83.89 ms · 原采样率","167.77 ms · 湿声 1/2 采样率","335.54 ms · 湿声 1/4 采样率","503.32 ms · 湿声 1/6 采样率"});
        echoDivision=choices(box,"目标节拍比例",new String[]{"1/4 拍","3/8 拍","1/2 拍"});
        echoLabel=text(box,"",13,INK);echoTempo=new SeekBar(this);echoTempo.setMin(20);echoTempo.setMax(300);echoTempo.setProgress(125);box.addView(echoTempo);
        echoTempo.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar b,int value,boolean user){updateEchoLabels();}
            public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}
        });
        AdapterView.OnItemSelectedListener listener=new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> p,View view,int position,long id){updateEchoLabels();refreshControlUi();}
            public void onNothingSelected(AdapterView<?> p){}
        };echoChoice.setOnItemSelectedListener(listener);echoDivision.setOnItemSelectedListener(listener);
        button(box,"按 BPM 选择最近抽头（草稿）",()->{echoChoice.setSelection(PerformanceParams.echoTap(echoTempo.getProgress(),echoDivision.getSelectedItemPosition()));updateEchoLabels();},false);
        button(box,"回声抽头恢复默认 83.89 ms",()->{echoChoice.setSelection(0);applyPerformance("EFFECT2,0");},true);
        button(box,"回声参考恢复 125 BPM / 1/4 拍",()->{echoTempo.setProgress(125);echoDivision.setSelection(0);updateEchoLabels();},false);
        button(box,"应用回声抽头",()->applyPerformance("EFFECT2,"+choice(echoChoice)),true);
        text(box,"仅选择最近的四档，不能与任意BPM严格同步；实际误差显示在上方。合唱速率保留旧固定值约0.745 Hz。TAKE不保存新增参数，录制和回放前需使用相同的移调、颤音与回声设置。",12,MUTED);
        updateEchoLabels();
    }
    private void updateEchoLabels(){
        if(echoTempo==null)return;
        int bpm=echoTempo.getProgress(),division=echoDivision.getSelectedItemPosition(),tap=echoChoice.getSelectedItemPosition();
        double target=PerformanceParams.echoTargetMilliseconds(bpm,division),actual=PerformanceParams.echoMilliseconds(tap);
        echoLabel.setText(String.format(Locale.ROOT,"参考 %d BPM（每拍 %.2f ms）；目标 %.2f ms；草稿 %.2f ms（约 %.3f 拍；误差 %+.2f ms）",bpm,60000.0/bpm,target,actual,actual*bpm/60000,actual-target));
    }
    private void updatePerformanceLabels(){
        if(performanceBars[4]==null)return;
        int bpm=performanceTempo.getProgress(),range=performanceBars[0].getProgress();
        performanceTempoLabel.setText(String.format(Locale.ROOT,"参考速度 %d BPM（每拍 %.2f ms；仅用于单位说明）",bpm,60000.0/bpm));
        performanceLabels[0].setText(String.format(Locale.ROOT,"弯音范围 ±%d 音分（±%.2f 半音）",range,range/100.0));
        int step=defaultGlide?PerformanceParams.DEFAULT_SLEW:PerformanceParams.glideStep(range,performanceBars[1].getProgress());
        performanceLabels[1].setText("滑音全程约 "+PerformanceParams.timeLabel(PerformanceParams.glideMilliseconds(range,step),bpm)+(defaultGlide?" · 默认过渡速率":" · 实际全程时间"));
        double hz=performanceBars[2].getProgress()/10.0;
        performanceLabels[2].setText(String.format(Locale.ROOT,"颤音速率 %.1f Hz（每拍约 %.2f 次 @%d BPM）",hz,hz*60/bpm,bpm));
        int cents=performanceBars[3].getProgress();performanceLabels[3].setText(String.format(Locale.ROOT,"颤音深度约 ±%d 音分（约 ±%.2f 半音）",cents,cents/100.0));
        performanceLabels[4].setText("起振延迟 "+PerformanceParams.timeLabel(performanceBars[4].getProgress(),bpm));
    }
    private void restorePerformance(int parameter){
        int[] defaults={1200,21,60,27,0};if(parameter==1)defaultGlide=true;performanceBars[parameter].setProgress(defaults[parameter]);updatePerformanceLabels();
        String[] commands={"PITCH,8192,32768","PITCH,,,4096","VIB,8,3478","VIB,,,256","VIB,,,,0"};applyPerformance(commands[parameter]);
    }
    private void applyPerformance(String command){
        if(command.startsWith("PITCH,")){
            String[] fields=command.split(",",-1);
            if(fields.length==5&&!fields[4].isEmpty()&&confirmedControls!=null&&!PerformanceParams.tuningAllowed(confirmedControls.analog,Integer.parseInt(fields[4]))){
                performanceState.setText("当前为电位器音高 ANALOG=2，不能启用移调 / 非440标准音；请先在模拟用途切到 0 / 1 / 3 / 4。");return;
            }
        }
        task(()->{link.command(command,"OK");readPerformance();},"演奏参数已确认；设备回读显示在弯音与滑音卡片");
    }
    private void readPerformance()throws Exception{
        final int[] pitch=PerformanceParams.parsePitch(link.command("PITCH,?","PITCH"));
        final int[] vibrato=PerformanceParams.parseVibrato(link.command("VIB,?","VIB"));
        final int[] echo=PerformanceParams.parseEcho(link.command("EFFECT2,?","EFFECT2"));
        main.post(()->{
            if(cancelled||!link.connected())return;
            confirmedPitch=pitch;confirmedVibrato=vibrato;confirmedEcho=echo;
            echoState.setText(String.format(Locale.ROOT,"设备已确认：回声 %.5f ms（第%d档）",PerformanceParams.echoMilliseconds(echo[0]),echo[0]+1));
            int range=(int)Math.round(PerformanceParams.bendCents(pitch[1]));
            performanceState.setText(String.format(Locale.ROOT,"设备已确认：弯音 %.2f～%+.2f 音分；本范围正向全程约 %.2f ms；\n红外 / 手势颤音 %.4f Hz，深度约 ±%.2f 音分，整体起振延迟 %.2f ms。",
                PerformanceParams.bendCents(pitch[0]),PerformanceParams.bendCents(pitch[1]),PerformanceParams.glideMilliseconds(range,pitch[2]),
                PerformanceParams.vibratoHz((vibrato[0]<<16)|vibrato[1]),PerformanceParams.depthCents(vibrato[2]),PerformanceParams.delayMilliseconds(vibrato[3]))+"\n红外 / 手势："+PerformanceParams.tuningLabel(pitch[3]));
            refreshControlUi();
        });
    }
    private void buildControls(LinearLayout content){
        LinearLayout box=card(content,"K","键盘模式与演奏控制","切换前松开全部键，停止曲谱并关闭延音。选择只修改草稿，点击应用后才发送。");
        controlsInfo=text(box,"尚未读取设备状态",14,ACCENT);
        text(box,"64×64 LED：空闲显示键态、延音、音色、音量、滑杆/ADC、音效和红外状态；播放曲谱时显示下落指引。长按板上 S2 可切换波形、XY、频谱。",12,MUTED);
        box=sourceGroups[0][0];
        touchMode=choices(box,"TTP229 接口",new String[]{"8 键直连：K1～K7 演奏，K8 切压力","16 键串行：K1～K16 全部演奏 / 和弦"});
        button(box,"应用 8 / 16 键模式",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            applyControl(DeviceControls.touchCommand(touchMode.getSelectedItemPosition()),"模式已确认。切换到串行模式后等待约 0.6 秒校准，再松开并重按触摸键。");
        },true,1);
        text(box,"16 键：7白+5黑一个八度（K1～K12 = C4～B4）+ 4 踏板条（K13～K16 暂作 C5/D5/E5/F5）。前七个扫描键 K1～K7 可自定义，默认 C4/C#4/D4/D#4/E4/F4/F#4。16 键须拆掉 OUT1～OUT8 直连线，只接 SCL/SDO，并配置模块的16键及多键焊盘；App 不会改变芯片焊盘。",12,MUTED);
        serialPolarity=choices(box,"16 键串行极性（匹配模块 TP1 / SAHL）",new String[]{"低有效：参考工程 TP1 开路","高有效：TP1 已装跳帽"});
        button(box,"应用串行极性",()->{if(recording||recordDraining){alert("请先结束事件录制");return;}applyControl("SERIAL,"+serialPolarity.getSelectedItemPosition(),"串行极性已确认；进入串行时重新等待校准");},true);
        box=sourceGroups[0][4];
        text(box,"触摸颤音仍使用 ANALOG,3 电位器档，保留原单向下摆。前七扫描键的弯音范围和滑音时间可在“音高与弯音”分组调整；红外 / 手势颤音参数在对应页签。",12,MUTED);
        pressureChoice=choices(box,"FSR 压力用途（16 键时由手机切换）",new String[]{"控制触摸音量","控制触摸音高"});
        button(box,"应用压力用途",()->applyControl("PRESSURE,"+pressureChoice.getSelectedItemPosition(),"压力用途已确认"),true);
        box=sourceGroups[0][5];
        holdChoice=choices(box,"延音 / 踏板",new String[]{"关闭：松键进入释音","无限锁存：关闭时释放","钢琴踏板：松键尾音约 1.2 秒，抬起时制音"});
        button(box,"应用延音 / 踏板",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            applyControl("HOLD,"+holdChoice.getSelectedItemPosition(),"延音 / 踏板已确认");
        },true);
        polyChoice=choices(box,"复音上限（物理按键优先）",new String[]{"1","2","4","8","16"});polyChoice.setSelection(4);
        button(box,"应用复音上限",()->applyControl("POLY,"+new int[]{1,2,4,8,16}[polyChoice.getSelectedItemPosition()],"复音上限已确认"),true);
        text(box,"超过上限时优先释掉最旧的松键尾音；按住的键始终保留。钢琴踏板与限复音暂不支持演出事件录制 / 回放。",12,MUTED);
        box=card(sections[2],"FX","总音量与效果","作用于：全局混音。音源轨道增益尚未实现，由阶段 E4（低成本）补齐。");
        effectChoice=choices(box,"全局音效",new String[]{"原声","反馈回声 · 约 84 ms","合唱 · 缓慢变延迟"});
        wetLabel=text(box,"音效湿度 · 4 / 8",13,INK);wetBar=new SeekBar(this);wetBar.setMax(8);wetBar.setProgress(4);box.addView(wetBar);
        wetBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int n,boolean user){wetLabel.setText("音效湿度 · "+n+" / 8");refreshControlUi();}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        button(box,"应用音效与湿度",()->applyControl("EFFECT,"+effectChoice.getSelectedItemPosition()+","+wetBar.getProgress(),"音效与湿度已确认"),true);
        volumeLabel=text(box,"总音量 · 16 / 16",13,INK);volumeBar=new SeekBar(this);volumeBar.setMax(16);volumeBar.setProgress(16);box.addView(volumeBar);
        volumeBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int n,boolean user){volumeLabel.setText("总音量 · "+n+" / 16");refreshControlUi();}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        button(box,"应用总音量",()->applyControl("VOLUME,"+volumeBar.getProgress(),"总音量已确认；0 为静音"),true);
        box=card(sections[2],"ADC","模拟输入与标定","作用于：全局混音。模拟音高仅调制触摸；一条 ADC 在各用途之间复用。");
        analogChoice=choices(box,"模拟输入用途",new String[]{"0 · 原 FSR 压力（保持原标定）","1 · 滑动变阻器：总音量","2 · 滑动变阻器：触摸音高 0.5～1 倍","3 · 滑动变阻器：触摸颤音深度","4 · 滑动变阻器：音效湿度"});
        button(box,"应用模拟输入用途",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            if(analogChoice.getSelectedItemPosition()==2&&confirmedPitch!=null&&confirmedPitch[3]!=16384){adcInfo.setText("当前移调 / 标准音基准不是原音，不能切到电位器音高；请先恢复 0 半音 / A4=440。");return;}
            applyControl("ANALOG,"+analogChoice.getSelectedItemPosition(),"模拟输入用途已确认");
        },true);
        text(box,"滑动变阻器复用原 ADC 模拟输入，替换 FSR，不是同时采两路。滑杆音量受手机总音量上限约束；ADC 必须经过分压保持在 0～1V。湿度控制需先开启回声或合唱。",12,MUTED);
        text(box,"滑杆端点标定：先读 ADC，把最小 / 最大端点的十进制值填入（0～1023，跨度至少 32）。",12,MUTED);
        calibrationInput=new EditText(this);calibrationInput.setSingleLine(true);calibrationInput.setText("0,1023");calibrationInput.setTextColor(INK);calibrationInput.setTextSize(15);calibrationInput.setHint("最小值,最大值，例如 0,590");calibrationInput.setContentDescription("滑杆 ADC 最小值和最大值，十进制逗号分隔");box.addView(calibrationInput);
        button(box,"应用滑杆端点标定",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            String[] parts=calibrationInput.getText().toString().trim().split(",",-1);int lo,hi;
            try{if(parts.length!=2)throw new NumberFormatException();lo=Integer.parseInt(parts[0].trim());hi=Integer.parseInt(parts[1].trim());if(lo<0||lo>1023||hi<0||hi>1023||hi-lo<32)throw new NumberFormatException();}
            catch(NumberFormatException e){alert("输入两个十进制 ADC 端点，0～1023 且最大值至少比最小值大 32");return;}
            applyControl("CAL,"+lo+","+hi,"滑杆标定已确认；不修改原 FSR 标定");
        },true);
        box=card(sections[0],"STATE","设备状态与安全静音","作用于：全局混音。");
        adcInfo=text(box,"ADC 尚未读取",13,MUTED);
        button(box,"读取实际模式 / ADC",()->task(()->{readControls();String raw=link.command("ADC?","ADC");String[] fields=raw.split(",",-1);if(fields.length!=3||!fields[1].matches("[0-3][0-9A-F]{2}")||!fields[2].matches("[01]"))throw new IOException("ADC 回报无效");int code=Integer.parseInt(fields[1],16);main.post(()->adcInfo.setText("ADC："+code+" / 1023（0x"+fields[1]+"） · "+(fields[2].equals("0")?"正常":"超时")));},"设备状态与 ADC 已读取"),true);
        button(box,"PANIC · 释放全部声音与延音",()->applyControl("PANIC","声音已释放，曲谱停止，延音关闭；按住的键需松开重按"),true,2);
        text(box,"曲谱下载、屏幕七列指引与逐声部弯音仍针对前七个扫描键；K8～K16 使用固定音高。默认七键只覆盖 C4～F#4，曲库可匹配改键后下载。事件日志仅支持原8键 / FSR模式。",12,MUTED);
    }
    private void applyControl(String command,String done){task(()->{link.command(command,"OK");readControls();},done);}
    private void readControls()throws Exception{
        DeviceControls read;
        try{read=DeviceControls.parse(link.command("CTRL2?","CTRL2"));}
        catch(SppLink.CommandRejectedException e){if(!e.response.equals("ERR,CMD"))throw e;read=DeviceControls.parse(link.command("CTRL?","CTRL"));}
        final DeviceControls state=read;
        String serial=link.command("SERIAL?","SERIAL");if(!serial.equals("SERIAL,0")&&!serial.equals("SERIAL,1"))throw new IOException("串行极性回报无效");
        String[] cal=link.command("CAL?","CAL").split(",",-1);
        if(cal.length!=3||!cal[1].matches("[0-3][0-9A-F]{2}")||!cal[2].matches("[0-3][0-9A-F]{2}"))throw new IOException("滑杆标定回报无效");
        int lo=Integer.parseInt(cal[1],16),hi=Integer.parseInt(cal[2],16);if(hi-lo<32)throw new IOException("滑杆标定范围无效");
        main.post(()->{
            if(cancelled||!link.connected())return;
            confirmedControls=state;confirmedSerial=serial.substring(7);confirmedCalibration=lo+","+hi;
            controlsInfo.setText("设备已确认：\n"+state.summary());
            refreshControlUi();
        });
    }
    private void forgetControls(){
        mapping=null;confirmedControls=null;confirmedPitch=null;confirmedVibrato=null;confirmedEcho=null;confirmedSerial=null;confirmedCalibration=null;confirmedLed=null;confirmedTake=null;acknowledged.clear();controlState.connected(false);
        if(performanceState!=null)performanceState.setText("演奏参数未知，请重新读取设备参数");
        if(echoState!=null)echoState.setText("回声档位未知，请重新读取设备参数");
        if(controlsInfo!=null)controlsInfo.setText("模式未知，请连接并读取设备状态");if(adcInfo!=null)adcInfo.setText("ADC 尚未读取");
        if(xyInfo!=null)xyInfo.setText("轨迹参数未知；列表为待发送草稿。");if(ledStatus!=null)ledStatus.setText("显示状态未知，请重新读取。");
        if(takeInfo!=null)takeInfo.setText("板上事件状态未知，请连接后读取。");
        main.removeCallbacks(displayPoll);stopLedPreview("连接状态改变，预览已停止。");refreshControlUi();
    }
    private void showSong(){scoreInfo.setText(song.name+"\n"+song.events.size()+" 条 · "+String.format(Locale.ROOT,"%.2f",song.durationMs()/1000.0)+" 秒\n需要音高："+SongCodec.notes(song.requiredMask()));progress.setProgress(0);}
    private void preview(){StringBuilder s=new StringBuilder();long at=0;for(int i=0;i<song.events.size();i++){SongCodec.Event e=song.events.get(i);s.append(i).append("  ").append(at).append("ms  ").append(SongCodec.notes(e.mask)).append("  ").append(e.durationMs).append("ms\n");at+=e.durationMs;}new AlertDialog.Builder(this).setTitle(song.name).setMessage(s.toString()).setPositiveButton("关闭",null).show();}
    private void pickScore(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");startActivityForResult(i,PICK_SCORE);}
    private void readMapping()throws Exception {int[] m=SongCodec.parseMapping(link.command("MAP?","MAP"));mapping=m;main.post(()->{if(cancelled||!link.connected())return;mapInfo.setText("设备第 1..7 键："+join(m));refreshControlUi();});}
    private static String join(int[] m){StringBuilder s=new StringBuilder();for(int v:m){if(s.length()>0)s.append(',');s.append(v);}return s.toString();}
    private void download(){downloadScore(false);}
    private void downloadScore(boolean matchKeys){if(recording||recordDraining){alert("先停止录制并等待 REC_END，再下载曲谱");return;}final SongCodec.Song selected=song;
        task(()->{readMapping();
            if(matchKeys){int[] target=SongLibrary.matchingMapping(selected,mapping);boolean changed=false;
                for(int key=0;key<7;key++)if(target[key]!=mapping[key]){if(cancelled)throw new IOException("下载已取消");link.command("MAP,"+(key+1)+","+target[key],"OK");changed=true;}
                if(changed)readMapping();
            }
            selected.checkMapping(mapping);List<String> commands=selected.commands();for(int i=0;i<commands.size();i++){if(cancelled)throw new IOException("下载已取消");String command=commands.get(i);link.command(command,"OK");final int p=(i+1)*100/commands.size();final int n=i+1;main.post(()->{progress.setProgress(p);setStatus("下载 "+n+" / "+commands.size()+"，已确认 "+command);});}},"《"+selected.name+"》已校验并提交。可自动演奏或 PLAY 开始指引；掉电后需重新下载。");}
    private void sendSimple(String command,String done){task(()->{
        link.command(command,"OK");main.post(()->{
            if(cancelled||!link.connected())return;
            if(command.startsWith("TONE,"))acknowledged.put("tone",command.substring(5));
            else if(command.startsWith("VIBRATO,"))acknowledged.put("vibrato",command.substring(8));
            else if(command.startsWith("BANK,"))acknowledged.put("bank",command.substring(5));
            else if(command.startsWith("ADSR,")){String[] fields=command.split(",",3);acknowledged.put("adsr"+(fields[1].equals("TOUCH")?0:1),fields[2]);}
            else if(command.startsWith("ADSR_RESET,"))acknowledged.put("adsr"+(command.endsWith("TOUCH")?0:1),"原始包络（设备确认）");
            if(command.equals("TEST32"))acknowledged.remove("vibrato");refreshControlUi();
        });
    },done);}
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
    private void startRecording(){String reason=TakeWorkflow.logBlockReason(confirmedControls);if(!reason.isEmpty()){logReason.setText(reason);return;}if(recording||recordDraining){alert("正在录制或等待日志排空");return;}recordingText.setLength(0);recordingOverflow=false;recordingCompleted=false;
        // Mark before the command: the FPGA may send MAP/EVT immediately after OK.
        recording=true;task(()->{try{link.command("REC_START","OK");}catch(Exception e){recording=false;recordingOverflow=true;if(e instanceof SppLink.CommandRejectedException&&((SppLink.CommandRejectedException)e).response.equals("ERR,MISSING"))throw new IOException("当前固件未启用事件日志（ERR,MISSING）；请使用板上事件录制或手机音符录制",e);throw e;}},"正在记录演奏事件；保持 App 前台");}
    private void stopRecording(){if(!recording){alert("当前没有正在进行的事件录制");return;}recordDraining=true;task(()->link.command("REC_STOP","OK"),"停止命令已确认；接收窗口 REC_END 为日志结束标记");}
    private void receive(String line){if(line.startsWith("V,"))return;logText.append(line).append('\n');if(logText.length()>12000)logText.delete(0,logText.length()-10000);logs.setText(logText.toString());
        if(recording||recordDraining){if(recordingText.length()+line.length()+1<=2*1024*1024)recordingText.append(line).append('\n');else{recordingOverflow=true;setStatus("App 日志达到 2MB 上限，请停止并导出；此次日志不完整");}if(line.contains("OVF")||line.contains("OVERFLOW")){recordingOverflow=true;setStatus("FIFO 溢出：此次事件日志不完整");}
            if(line.startsWith("REC_END,")){recording=false;recordDraining=false;if(!line.equals("REC_END,0"))recordingOverflow=true;recordingCompleted=line.equals("REC_END,0")&&!recordingOverflow;refreshControlUi();setStatus(recordingOverflow?"录制结束，检测到溢出，日志不完整":"录制结束，事件日志可导出");}}
    }
    private void exportLog(){if(recordingText.length()==0){alert("暂无日志，请先 REC_START 记录演奏事件");return;}Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("text/plain");i.putExtra(Intent.EXTRA_TITLE,"fpga-performance-"+System.currentTimeMillis()+".txt");startActivityForResult(i,EXPORT_LOG);}
    @Override protected void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);if(exportingScore!=null)state.putString("exportingScore",exportingScore.id);}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(appearance.onActivityResult(request,result,data))return;if(result!=RESULT_OK||data==null||data.getData()==null){if(request==EXPORT_SCORE)exportingScore=null;return;}Uri uri=data.getData();
        if(request==EXPORT_PHONE){final byte[] midi=phoneExportMidi;if(midi==null){alert("请重新选择手机录制后导出");return;}phoneWork(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建 MIDI 文件");out.write(midi);}},"手机 MIDI 已导出");
        }else if(request==PICK_SCORE){String display="导入曲谱";try(Cursor c=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(c!=null&&c.moveToFirst())display=c.getString(0);}catch(Exception ignored){}final String name=display;
            task(()->{byte[] bytes;try(InputStream in=getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException("无法打开文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(out.size()+n>2*1024*1024)throw new IOException("文件超过 2MB");out.write(b,0,n);}bytes=out.toByteArray();}SongCodec.Song parsed=SongCodec.parse(name,bytes);main.post(()->{song=parsed;showSong();});},"曲谱已导入；下载前会核对实际键位");
        }else if(request==EXPORT_SCORE){final SongLibrary.Entry selected=exportingScore;exportingScore=null;if(selected==null)return;
            task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建曲谱文件");out.write(selected.csv());}},"《"+selected.title+"》已保存到所选文件夹，可通过 CSV 导入入口再次使用");
        }else if(request==EXPORT_LOG){final byte[] bytes=("# FPGA performance events; audio is not recorded\n# complete="+(recordingCompleted&&!recordingOverflow)+"\n"+recordingText).getBytes(StandardCharsets.UTF_8);task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建日志文件");out.write(bytes);}},"事件日志已导出");
        }
    }
    private void alert(String message){new AlertDialog.Builder(this).setTitle("提示").setMessage(message).setPositiveButton("知道了",null).show();}
    @Override protected void onStop(){resumed=false;main.removeCallbacks(displayPoll);if(ledPreviewRunning)stopLedPreview("App 已离开前台，预览已停止。");if(phoneRecording)stopPhoneRecording();if(phonePiano!=null){phonePiano.close();phonePiano=null;}super.onStop();}
    @Override protected void onDestroy(){stopLedPreview("预览已停止。");voiceBend.clearPending();if(phonePiano!=null)phonePiano.close();main.removeCallbacksAndMessages(null);cancelled=true;link.close();worker.shutdownNow();phoneWorker.shutdownNow();if(appearance!=null)appearance.close();super.onDestroy();}
}
