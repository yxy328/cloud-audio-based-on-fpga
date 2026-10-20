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
import android.media.MediaPlayer;
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
    // Current phone/FPGA transport is HC-05 only. Keep USB audio as backup;
    // do not create its receiver, permission handler or worker at startup.
    private static final boolean USB_AUDIO_BACKUP_ENABLED=false;
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
    private TextView controlsInfo,volumeLabel,wetLabel,adcInfo;
    private Spinner touchMode,serialPolarity,effectChoice,holdChoice,analogChoice,pressureChoice;
    private SeekBar volumeBar,wetBar;
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
    private UsbAudioLink audioUsb;
    private TextView audioInfo;
    private TextView takeInfo;
    private boolean takePolling;
    private volatile boolean audioTakeActive;
    private File lastAudioFile;
    private boolean lastAudioComplete;
    private int audioGeneration;
    private AudioRecording hc05Audio;
    private long audioLastProgress;
    private MediaPlayer audioPlayer;
    private int audioStartGeneration;
    private PhonePiano phonePiano;
    private PhoneTake phoneDraft;
    private PhoneTakeStore phoneStore;
    private TextView phoneInfo;
    private boolean phoneRecording,phoneDirty,phoneBusy;
    private long phoneStart;
    private byte[] phoneExportMidi;
    private static final int PICK_SCORE=10,EXPORT_LOG=11,PERMISSION=12,EXPORT_AUDIO=13,EXPORT_SCORE=14,EXPORT_PHONE=15;
    @Override public void onCreate(Bundle state){super.onCreate(state);
        if(state!=null){String id=state.getString("exportingScore");for(SongLibrary.Entry entry:SongLibrary.all())if(entry.id.equals(id)){exportingScore=entry;break;}}
        link=new SppLink(new SppLink.Listener(){
            public void line(String line){main.post(()->receive(line));}
            public void disconnected(String reason){main.post(()->{forgetBendConnection();mapping=null;recordingInterrupted();forgetControls();mapInfo.setText("键位未知，请重新连接");setStatus("蓝牙断开："+reason);});}
            public void audioProgress(AudioRecording take){main.post(()->{audioLastProgress=SystemClock.uptimeMillis();audioInfo.setText(String.format(Locale.CHINA,"HC-05回传中：%.1fKB；30秒录音约需54分钟，请保持前台",take.bytesWritten()/1024.0));});}
            public void audioFinished(AudioRecording take){main.post(()->finishHc05Audio(take));}
        });
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);adapter=manager==null?null:manager.getAdapter();
        buildUi();showSong();setStatus("先在系统蓝牙设置配对 HC-05，再刷新设备");
        File[] savedAudio=getFilesDir().listFiles((dir,name)->name.startsWith("fpga-hc05-")&&name.endsWith(".wav"));
        if(savedAudio!=null)for(File f:savedAudio)if(lastAudioFile==null||f.lastModified()>lastAudioFile.lastModified())lastAudioFile=f;
        if(lastAudioFile!=null){lastAudioComplete=!lastAudioFile.getName().contains(".INCOMPLETE.");audioInfo.setText("已恢复手机文件："+lastAudioFile.getName());}
        if(USB_AUDIO_BACKUP_ENABLED){audioUsb=new UsbAudioLink(this,new UsbAudioLink.Listener(){
            public void state(String text){main.post(()->audioInfo.setText(text));}
            public void progress(long bytes,boolean started){main.post(()->audioInfo.setText(started?
                String.format(Locale.CHINA,"正在录制：%.2f秒，%.1fKB；保持App前台",bytes/97656.25,bytes/1024.0):"等待FPGA录音开始包…"));}
            public void result(AudioRecording take){main.post(()->{
                audioTakeActive=false;++audioGeneration;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                lastAudioFile=take.file();lastAudioComplete=take.complete();
                audioInfo.setText(take.complete()?"完整录音已保存，可导出WAV（"+take.bytesWritten()+"字节音频）":
                    "录音不完整，仅保留已验证前缀："+take.problem());
            });}
            public void failure(String reason){main.post(()->{
                boolean wasActive=audioTakeActive;audioTakeActive=false;++audioGeneration;
                getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);audioInfo.setText(reason);
                if(wasActive)abortAudioCommand();
            });}
        });}
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
        Button b=new Button(this);b.setText(value);b.setTextSize(14);b.setAllCaps(false);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setMinHeight(dp(50));b.setMinimumHeight(dp(50));b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(12),dp(10),dp(12),dp(10));b.setLetterSpacing(0.01f);
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
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.setVerticalScrollBarEnabled(false);root.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
        scroll.setOnApplyWindowInsetsListener((v,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()|WindowInsets.Type.ime());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);topBarLp.height=bars.top;bottomBarLp.height=bars.bottom;}
            else{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());topBarLp.height=insets.getSystemWindowInsetTop();bottomBarLp.height=insets.getSystemWindowInsetBottom();}
            topBar.setLayoutParams(topBarLp);bottomBar.setLayoutParams(bottomBarLp);return insets;
        });
        LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(18),dp(18),dp(18),dp(24));scroll.addView(content);setContentView(root);scroll.requestApplyInsets();
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
        status=text(statusBox,"",14,ACCENT);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout box=card(content,"01","蓝牙连接","先在系统蓝牙设置中配对 HC-05，再选择设备。");devices=new Spinner(this);devices.setContentDescription("已配对蓝牙设备");addSpinner(box,devices);
        LinearLayout connectionRow=row(box);button(connectionRow,"刷新设备",()->ensurePermission(this::refreshDevices),true);button(connectionRow,"连接设备",()->ensurePermission(this::connectSelected),true,1);
        button(box,"断开 / 取消下载",this::disconnect,false,2);
        text(box,"当前手机与FPGA仅通过HC-05通信，无需USB串口模块或OTG。",12,MUTED);
        buildControls(content);
        box=card(content,"02","曲谱与播放","从分级曲库选曲，或从文件夹导入；下载后可自动演奏或跟随屏幕练习。");
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
        buildLedControls(content);
        box=card(content,"03","七键音高","按第 1～7 键填写 MIDI 音高，范围 60～72。");
        mapInfo=text(box,"尚未读取键位",14,MUTED);
        button(box,"读取设备键位 MAP?",()->task(()->readMapping(),"键位已读取"),true);
        mappingInput=new EditText(this);mappingInput.setSingleLine(true);mappingInput.setText("60,62,64,65,67,69,71");mappingInput.setTextColor(INK);mappingInput.setTextSize(15);mappingInput.setMinHeight(dp(54));mappingInput.setPadding(dp(12),dp(12),dp(12),dp(12));mappingInput.setBackground(rounded(Theme.SURFACE_ALT,Theme.R_CHIP));mappingInput.setContentDescription("第1到第7键的 MIDI 音高，用英文逗号分隔");box.addView(mappingInput,new LinearLayout.LayoutParams(-1,-2));
        button(box,"应用七键映射",this::applyMapping,true,1);
        button(box,"恢复默认映射",()->{if(recording||recordDraining){alert("先停止并等待日志结束，再修改键位");return;}task(()->{link.command("MAP_RESET","OK");readMapping();},"默认映射已恢复");},true);
        box=card(content,"04","红外 / 手势音源与吉他","红外与手势共享 32 复音音源，音色和颤音同时生效；音符组仅作用于手势。");
        gestureTone=choices(box,"红外 / 手势音色",new String[]{"正弦","钢琴","长笛","尤克里里","鼓","电钢琴","钟声","弦乐"});
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
        box=card(content,"07","HC-05 原音质录音","录制 FPGA 最终数字混音，停止并读回 CRC 校验后保存到板上 Flash，再经现有 HC-05 回传 WAV。");
        audioInfo=text(box,"先准备空闲录音槽；准备会擦除非当前槽，上一条有效录音仍保留。",13,MUTED);
        button(box,"1 · 准备 30 秒录音槽",this::prepareHc05Audio,true,1);
        LinearLayout audioRow=row(box);
        button(audioRow,"2 · 开始录制",this::startHc05Audio,true,1);
        button(audioRow,"3 · 停止并校验",this::stopHc05Audio,true);
        button(box,"4 · 经 HC-05 回传 WAV",this::downloadHc05Audio,true,1);
        button(box,"中止回传并保留不完整 WAV",()->{if(link.audioActive())link.close();else alert("当前没有音频回传");},false,2);
        audioRow=row(box);button(audioRow,"播放手机 WAV",this::playAudio,false);button(audioRow,"导出 WAV",this::exportAudio,false);
        button(box,"读取录音状态",()->task(this::readHc05AudioStatus,"录音状态已读取"),true);
        text(box,"格式固定为 50MHz/1024 = 48.828125kHz、16位单声道，不降采样、不压缩。30秒约2.79MiB；9600bps并逐包ACK时约54分钟。断线、CRC错误或10秒无进度时手机文件明确标记为不完整。",12,MUTED);
        box=card(content,"EVT","事件录制与板上重放（不是音频）","统一版由下面按钮控制事件录制，16 个实体键保留演奏。独立事件版还可用 K13～K16 控制。");
        takeInfo=text(box,"连接新版 FPGA 固件后读取录制状态。",13,MUTED);
        button(box,"开始录制",()->takeAction("TAKE_REC"),true,1);
        LinearLayout takeRow=row(box);
        button(takeRow,"停止",()->takeAction("TAKE_STOP"),true);
        button(takeRow,"回放",()->takeAction("TAKE_PLAY"),true,1);
        button(box,"保存到板上 Flash",()->takeAction("TAKE_SAVE"),true);
        button(box,"删除已录制内容",()->takeAction("TAKE_DEL"),true,2);
        button(box,"读取录制状态",()->takeAction(null),true);
        text(box,"等待显示 Flash 保存并读回校验成功后才能断电。容量为 1024 条事件；连续音量或音高变化会较快用满。覆盖与删除均需再次确认。",12,MUTED);
        buildPhoneRecording(content);
        logs=text(box,"接收窗口\n",12,Theme.PANEL_TEXT);logs.setTextIsSelectable(true);logs.setTypeface(Typeface.MONOSPACE);logs.setPadding(dp(14),dp(13),dp(14),dp(13));logs.setBackground(rounded(Theme.PANEL,Theme.R_PANEL));logs.setLineSpacing(dp(2),1);
        TextView footer=text(content,"FPGA MUSIC LAB  ·  孤独摇滚 · 让灵感在指尖发声",11,MUTED);footer.setGravity(Gravity.CENTER);footer.setLetterSpacing(0.06f);footer.setBackground(rounded(0x8cfff6fb,Theme.R_CHIP));
    }
    private void buildLedControls(LinearLayout content){
        LinearLayout box=card(content,"LED","显示控制与实时预览","需配套新版 FPGA 位流。手机可直接切页，板上 S2 仍可使用。");
        LinearLayout pages=row(box);
        button(pages,"总览 / 曲谱",()->selectLedPage(0),true);button(pages,"波形",()->selectLedPage(1),true);
        pages=row(box);button(pages,"XY 轨迹",()->selectLedPage(2),true);button(pages,"频谱",()->selectLedPage(3),true);
        button(box,"读取设备显示状态",()->task(this::readLedState,"已读取 FPGA 实际显示状态"),true);
        ledStatus=text(box,"显示状态尚未读取；下方选择框为待发送值。",13,MUTED);
        text(box,"李萨如与实际混音轨迹",18,INK);
        String[] names={"八字","多瓣","圆","椭圆","直线","实际混音"};
        int[] ratios={2,3,1,1,1,0},phases={0,0,2,1,0,0};
        for(int i=0;i<names.length;i+=2){
            LinearLayout presets=row(box);
            for(int j=i;j<i+2;j++){
                final int ratio=ratios[j],phase=phases[j];
                button(presets,names[j],()->applyXy(ratio,phase),true);
            }
        }
        xyRatio=choices(box,"轨迹来源 / X:Y 频率比",new String[]{"AUD · 实际混音延时轨迹","REF · 1:1","REF · 1:2","REF · 2:3"});
        xyRatio.setSelection(2);
        xyPhase=choices(box,"Y 相对 X 的相位差（仅 REF）",new String[]{"0°","45°","90°","135°"});
        xyRatio.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){updateXyControls();}
            public void onNothingSelected(AdapterView<?> parent){}
        });
        button(box,"应用所选轨迹参数",()->applyXy(xyRatio.getSelectedItemPosition(),xyPhase.getSelectedItemPosition()),true,1);
        xyInfo=text(box,"尚未发送；列表为待发送值，未读取板上当前参数。",13,MUTED);
        xyInfo.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        text(box,"REF 是 FPGA 生成的参考图形；AUD 随实际演奏变化。收到设备 OK 后才显示发送确认；板上 S2 选图或复位后，请重新应用。",12,MUTED);
        text(box,"S2 长按循环切换总览/曲谱、波形、XY、频谱；XY 页短按选图，其他页短按会重启有效曲谱。",12,MUTED);
        text(box,"手机实时预览 · FPGA 数据",18,INK);
        text(box,"16 段频谱约 0～3.05kHz，下方为三组音源幅度。最多每秒查询 5 次，下载、事件录制或其他命令期间暂停。",12,MUTED);
        ledPreview=new SpectrumPreviewView(this);box.addView(ledPreview,new LinearLayout.LayoutParams(-1,dp(220)));
        ledPreviewInfo=text(box,"预览未开启；画面来自 FPGA 回传，不是手机麦克风。",12,MUTED);
        LinearLayout previewButtons=row(box);
        button(previewButtons,"开启实时预览",this::startLedPreview,true);
        button(previewButtons,"停止预览",()->stopLedPreview("预览已停止。"),false);
        updateXyControls();
    }
    private void selectLedPage(int mode){
        task(()->{link.command("VIS,"+mode,"OK");readLedState();},"切页已确认并读取状态；以实际显示页为准");
    }
    private void readLedState()throws Exception{
        LedState value=LedState.parse(link.command("VIS?","VIS"));
        main.post(()->{if(!cancelled && link.connected())ledStatus.setText("最近读取：\n"+value.description());});
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
        if(busy || link.audioActive() || recording || recordDraining || takePolling || ledPollPending){scheduleLedPreview(200);return;}
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
                    ledStatus.setText("最近预览："+frame.description());
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
        xyRatio.setSelection(ratio);xyPhase.setSelection(phase);
        final String command="XY,"+ratio+","+phase;
        final String description=ratio==0?"AUD · 实际混音延时轨迹":"REF · "+(ratio==1?"1:1":ratio==2?"1:2":"2:3")+"，相位 "+(phase*45)+"°";
        task(()->{
            link.command(command,"OK");
            main.post(()->{if(!cancelled && link.connected())xyInfo.setText("最近确认发送："+description+"。板上切图或复位后请重新应用。");});
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
    private void takeAction(String command){
        task(()->{
            RecordingSupport.readEvents(link);
            if(command!=null)link.command(command,"OK");
            TakeStatus value=RecordingSupport.readEvents(link);
            main.post(()->showTake(value));
        },"录制状态已读取");
    }
    private void buildPhoneRecording(LinearLayout content){
        LinearLayout box=card(content,"PHONE","手机琴键与我的录音","页面琴键在手机本地发声。手机录制与上方板上 Flash 录制分别保存，无需连接蓝牙即可使用。");
        phoneInfo=text(box,"开始手机录制 → 弹奏下方琴键 → 停止 → 回放 → 命名保存。录制前先松开琴键。",13,MUTED);
        String[] names={"C4","D4","E4","F4","G4","A4","B4","C5","D5","E5","F5","G5","A5","B5","C6","D6"};
        for(int r=0;r<4;r++){LinearLayout keys=row(box);for(int c=0;c<4;c++){final int key=r*4+c;Button pad=button(keys,names[key],()->{},false,1);pad.setOnTouchListener((view,event)->{
            int action=event.getActionMasked();if(action==MotionEvent.ACTION_DOWN){phoneKey(key,true);pad.setPressed(true);return true;}
            if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){phoneKey(key,false);pad.setPressed(false);return true;}return true;});}}
        button(box,"开始手机录制",this::startPhoneRecording,false,1);LinearLayout controls=row(box);
        button(controls,"停止录制 / 回放",this::stopPhoneRecording,false);button(controls,"回放当前录制",()->{if(phoneRecording){alert("请先停止手机录制");return;}playPhoneTake(phoneDraft,"当前手机录制");},false,1);
        button(box,"命名并保存录制",()->savePhoneRecording(null),false);button(box,"我的录音 · 回放 / 改名 / 删除",this::showPhoneLibrary,false);
        button(box,"导出当前手机 MIDI",()->exportPhoneTake(phoneDraft,"手机演奏"),false);
        text(box,"每次保存新增一份，数量由手机可用空间决定；每份最多10000个音符。记录音符、节奏、按键时长和力度，回放由手机合成。保存后关闭重开仍可在“我的录音”找到。",12,MUTED);
    }
    private PhonePiano phonePiano(){if(phonePiano==null)phonePiano=new PhonePiano();return phonePiano;}
    private int phoneTime(){return (int)Math.min(Integer.MAX_VALUE,Math.max(0,SystemClock.uptimeMillis()-phoneStart));}
    private void phoneKey(int key,boolean on){
        try{if(on){PhonePiano piano=phonePiano();if(piano.replaying())piano.stop();piano.key(key,true);}else if(phonePiano!=null)phonePiano.key(key,false);
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
        if(!busy&&!link.audioActive())getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private void playPhoneTake(PhoneTake take,String name){
        if(take==null||!take.finished()||take.notes()==0){alert("请先完成一段手机录制，或从“我的录音”选择");return;}
        try{if(audioPlayer!=null){audioPlayer.release();audioPlayer=null;}phonePiano().play(take,()->main.post(()->phoneInfo.setText("手机回放完成："+name)));phoneInfo.setText("手机回放："+name);}
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
        takeInfo.setText(value.description());
        if(value.confirmation()!=0){
            new AlertDialog.Builder(this).setTitle(value.confirmation()==1?"覆盖原录制？":"删除原录制？")
                .setMessage("确认后操作板上的录制内容。新录制只有在 Flash 校验成功后才算保存。")
                .setPositiveButton("确认",(d,w)->takeAction("TAKE_YES"))
                .setNegativeButton("取消",(d,w)->takeAction("TAKE_NO"))
                .setOnCancelListener(d->takeAction("TAKE_NO")).show();
        }else if(value.busy() && !takePolling){
            takePolling=true;
            main.postDelayed(()->{takePolling=false;if(link.connected()&&!busy)takeAction(null);},750);
        }
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
        adsrTarget=choices(box,"作用音源",new String[]{"触摸键盘（8 / 16 键）","红外 / 手势 32 复音"});
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
    private void connectSelected(){if(recording||recordDraining){alert("请先停止录制并等待 REC_END，再重新连接；也可点断开以中断此次录制。");return;}int selected=devices.getSelectedItemPosition();if(selected<0||selected>=paired.size()){alert("请先刷新并选择已配对 HC-05");return;}BluetoothDevice d=paired.get(selected);forgetBendConnection();forgetControls();mapping=null;mapInfo.setText("连接中，尚未读取键位");task(()->{link.connect(d);link.command("PING","PONG");readMapping();readControls();RecordingSupport support=RecordingSupport.probe(link);if(support.audio!=null){audioTakeActive=support.audio.busy&&(support.audio.state==4||support.audio.state==6);audioStartGeneration=support.audio.generation;}else audioTakeActive=false;main.post(()->{audioInfo.setText(support.audio==null?RecordingSupport.AUDIO_UNAVAILABLE:support.audio.description());takeInfo.setText(support.events==null?RecordingSupport.EVENTS_UNAVAILABLE:support.events.description());});},"HC-05 已连接，已读取键位、演奏模式和录制功能");}
    private void setStatus(String s){status.setText(s);}
    private void setBusy(boolean value){busy=value;for(Button b:lockedButtons)b.setEnabled(!value);libraryTier.setEnabled(!value);libraryTracks.setEnabled(!value);updateXyControls();getWindow().setFlags(value||link.audioActive()||phoneRecording?WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON:0,WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}
    private interface Work {void run()throws Exception;}
    private void task(Work work,String done){if(busy)return;setBusy(true);cancelled=false;setStatus("处理中…");worker.execute(()->{try{work.run();main.post(()->{setBusy(false);if(!cancelled)setStatus(done);});}catch(Exception e){main.post(()->{setBusy(false);if(!cancelled){if(!link.connected()){mapping=null;forgetControls();recordingInterrupted();mapInfo.setText("连接已关闭，请重新连接后重试");}setStatus("未完成："+e.getMessage());alert(e.getMessage());}});}});}
    private void recordingInterrupted(){if(recording||recordDraining){recordingOverflow=true;recordingCompleted=false;}recording=false;recordDraining=false;}
    private void disconnect(){forgetBendConnection();forgetControls();cancelled=true;link.close();mapping=null;recordingInterrupted();mapInfo.setText("尚未连接");setStatus("已断开。下载未提交时旧谱保留；重新连接后可重新下载。");}
    private void buildControls(LinearLayout content){
        LinearLayout box=card(content,"K","键盘模式与演奏控制","切换前松开全部键，停止曲谱并关闭延音。选择只修改草稿，点击应用后才发送。");
        controlsInfo=text(box,"尚未读取设备状态",14,ACCENT);
        text(box,"64×64 LED：空闲显示键态、延音、音色、音量、滑杆/ADC、音效和红外状态；播放曲谱时显示下落指引。长按板上 S2 可切换波形、XY、频谱。",12,MUTED);
        touchMode=choices(box,"TTP229 接口",new String[]{"8 键直连：K1～K7 演奏，K8 切压力","16 键串行：K1～K16 全部演奏 / 和弦"});
        button(box,"应用 8 / 16 键模式",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            applyControl(DeviceControls.touchCommand(touchMode.getSelectedItemPosition()),"模式已确认。切换到串行模式后等待约 0.6 秒校准，再松开并重按触摸键。");
        },true,1);
        text(box,"16 键：C4 D4 E4 F4 G4 A4 B4 C5 / D5 E5 F5 G5 A5 B5 C6 D6。前七键仍可自定义。16 键须拆掉 OUT1～OUT8 直连线，只接 SCL/SDO，并配置模块的 16 键及多键焊盘；App 不会改变芯片焊盘。",12,MUTED);
        serialPolarity=choices(box,"16 键串行极性（匹配模块 TP1 / SAHL）",new String[]{"低有效：参考工程 TP1 开路","高有效：TP1 已装跳帽"});
        button(box,"应用串行极性",()->{if(recording||recordDraining){alert("请先结束事件录制");return;}applyControl("SERIAL,"+serialPolarity.getSelectedItemPosition(),"串行极性已确认；进入串行时重新等待校准");},true);
        pressureChoice=choices(box,"FSR 压力用途（16 键时由手机切换）",new String[]{"控制触摸音量","控制触摸音高"});
        button(box,"应用压力用途",()->applyControl("PRESSURE,"+pressureChoice.getSelectedItemPosition(),"压力用途已确认"),true);
        holdChoice=choices(box,"延音锁存",new String[]{"关闭：松键进入释音","开启：松键后继续保持，关闭时释放"});
        button(box,"应用延音锁存",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
            applyControl("HOLD,"+holdChoice.getSelectedItemPosition(),"延音锁存已确认");
        },true);
        effectChoice=choices(box,"全局音效",new String[]{"原声","反馈回声 · 约 84 ms","合唱 · 缓慢变延迟"});
        wetLabel=text(box,"音效湿度 · 4 / 8",13,INK);wetBar=new SeekBar(this);wetBar.setMax(8);wetBar.setProgress(4);box.addView(wetBar);
        wetBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int n,boolean user){wetLabel.setText("音效湿度 · "+n+" / 8");}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        button(box,"应用音效与湿度",()->applyControl("EFFECT,"+effectChoice.getSelectedItemPosition()+","+wetBar.getProgress(),"音效与湿度已确认"),true);
        volumeLabel=text(box,"总音量 · 16 / 16",13,INK);volumeBar=new SeekBar(this);volumeBar.setMax(16);volumeBar.setProgress(16);box.addView(volumeBar);
        volumeBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int n,boolean user){volumeLabel.setText("总音量 · "+n+" / 16");}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        button(box,"应用总音量",()->applyControl("VOLUME,"+volumeBar.getProgress(),"总音量已确认；0 为静音"),true);
        analogChoice=choices(box,"模拟输入用途",new String[]{"0 · 原 FSR 压力（保持原标定）","1 · 滑动变阻器：总音量","2 · 滑动变阻器：触摸音高 0.5～1 倍","3 · 滑动变阻器：触摸颤音深度","4 · 滑动变阻器：音效湿度"});
        button(box,"应用模拟输入用途",()->{
            if(recording||recordDraining){alert("请先结束事件录制");return;}
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
        adcInfo=text(box,"ADC 尚未读取",13,MUTED);
        button(box,"读取实际模式 / ADC",()->task(()->{readControls();String raw=link.command("ADC?","ADC");String[] fields=raw.split(",",-1);if(fields.length!=3||!fields[1].matches("[0-3][0-9A-F]{2}")||!fields[2].matches("[01]"))throw new IOException("ADC 回报无效");int code=Integer.parseInt(fields[1],16);main.post(()->adcInfo.setText("ADC："+code+" / 1023（0x"+fields[1]+"） · "+(fields[2].equals("0")?"正常":"超时")));},"设备状态与 ADC 已读取"),true);
        button(box,"PANIC · 释放全部声音与延音",()->applyControl("PANIC","声音已释放，曲谱停止，延音关闭；按住的键需松开重按"),true,2);
        text(box,"曲谱下载、屏幕七列指引与逐声部滑音仍针对前七键；K8～K16 使用上述固定高音。事件日志仅支持原 8 键 / FSR 模式。",12,MUTED);
    }
    private void applyControl(String command,String done){task(()->{link.command(command,"OK");readControls();},done);}
    private void readControls()throws Exception{
        DeviceControls state=DeviceControls.parse(link.command("CTRL?","CTRL"));
        String serial=link.command("SERIAL?","SERIAL");if(!serial.equals("SERIAL,0")&&!serial.equals("SERIAL,1"))throw new IOException("串行极性回报无效");
        String[] cal=link.command("CAL?","CAL").split(",",-1);
        if(cal.length!=3||!cal[1].matches("[0-3][0-9A-F]{2}")||!cal[2].matches("[0-3][0-9A-F]{2}"))throw new IOException("滑杆标定回报无效");
        int lo=Integer.parseInt(cal[1],16),hi=Integer.parseInt(cal[2],16);if(hi-lo<32)throw new IOException("滑杆标定范围无效");
        main.post(()->{confirmedControls=state;controlsInfo.setText("设备已确认：\n"+state.summary());touchMode.setSelection(state.mode16);serialPolarity.setSelection(serial.equals("SERIAL,1")?1:0);
            effectChoice.setSelection(state.effect);wetBar.setProgress(state.wet);holdChoice.setSelection(state.hold);
            analogChoice.setSelection(state.analog);volumeBar.setProgress(state.volume);pressureChoice.setSelection(state.pressure);calibrationInput.setText(lo+","+hi);});
    }
    private void forgetControls(){confirmedControls=null;if(controlsInfo!=null)controlsInfo.setText("模式未知，请连接并读取设备状态");if(adcInfo!=null)adcInfo.setText("ADC 尚未读取");if(xyInfo!=null)xyInfo.setText("轨迹参数未知；连接后请重新应用，列表仅为待发送值。");if(ledStatus!=null)ledStatus.setText("显示状态未知，请重新读取。");stopLedPreview("连接状态改变，预览已停止。");}
    private void showSong(){scoreInfo.setText(song.name+"\n"+song.events.size()+" 条 · "+String.format(Locale.ROOT,"%.2f",song.durationMs()/1000.0)+" 秒\n需要音高："+SongCodec.notes(song.requiredMask()));progress.setProgress(0);}
    private void preview(){StringBuilder s=new StringBuilder();long at=0;for(int i=0;i<song.events.size();i++){SongCodec.Event e=song.events.get(i);s.append(i).append("  ").append(at).append("ms  ").append(SongCodec.notes(e.mask)).append("  ").append(e.durationMs).append("ms\n");at+=e.durationMs;}new AlertDialog.Builder(this).setTitle(song.name).setMessage(s.toString()).setPositiveButton("关闭",null).show();}
    private void pickScore(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");startActivityForResult(i,PICK_SCORE);}
    private void readMapping()throws Exception {int[] m=SongCodec.parseMapping(link.command("MAP?","MAP"));mapping=m;main.post(()->{mapInfo.setText("第 1..7 键："+join(m));mappingInput.setText(join(m));});}
    private static String join(int[] m){StringBuilder s=new StringBuilder();for(int v:m){if(s.length()>0)s.append(',');s.append(v);}return s.toString();}
    private void download(){downloadScore(false);}
    private void downloadScore(boolean matchKeys){if(recording||recordDraining){alert("先停止录制并等待 REC_END，再下载曲谱");return;}final SongCodec.Song selected=song;
        task(()->{readMapping();
            if(matchKeys){int[] target=SongLibrary.matchingMapping(selected,mapping);boolean changed=false;
                for(int key=0;key<7;key++)if(target[key]!=mapping[key]){if(cancelled)throw new IOException("下载已取消");link.command("MAP,"+(key+1)+","+target[key],"OK");changed=true;}
                if(changed)readMapping();
            }
            selected.checkMapping(mapping);List<String> commands=selected.commands();for(int i=0;i<commands.size();i++){if(cancelled)throw new IOException("下载已取消");String command=commands.get(i);link.command(command,"OK");final int p=(i+1)*100/commands.size();final int n=i+1;main.post(()->{progress.setProgress(p);setStatus("下载 "+n+" / "+commands.size()+"，已确认 "+command);});}},"《"+selected.name+"》已校验并提交。可自动演奏或 PLAY 开始指引；掉电后需重新下载。");}
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
    private void startRecording(){if(confirmedControls==null||confirmedControls.mode16!=0||confirmedControls.hold!=0||confirmedControls.analog!=0){alert("事件日志支持 8 键、关闭延音锁存、FSR 模式；请先设置并读取设备状态。16 键仍可正常演奏。");return;}if(recording||recordDraining){alert("正在录制或等待日志排空");return;}recordingText.setLength(0);recordingOverflow=false;recordingCompleted=false;
        // Mark before the command: the FPGA may send MAP/EVT immediately after OK.
        recording=true;task(()->{try{link.command("REC_START","OK");}catch(Exception e){recording=false;recordingOverflow=true;throw e;}},"正在记录演奏事件；保持 App 前台");}
    private void stopRecording(){if(!recording){alert("当前没有正在进行的事件录制");return;}recordDraining=true;task(()->link.command("REC_STOP","OK"),"停止命令已确认；接收窗口 REC_END 为日志结束标记");}
    private void receive(String line){if(line.startsWith("V,"))return;logText.append(line).append('\n');if(logText.length()>12000)logText.delete(0,logText.length()-10000);logs.setText(logText.toString());
        if(recording||recordDraining){if(recordingText.length()+line.length()+1<=2*1024*1024)recordingText.append(line).append('\n');else{recordingOverflow=true;setStatus("App 日志达到 2MB 上限，请停止并导出；此次日志不完整");}if(line.contains("OVF")||line.contains("OVERFLOW")){recordingOverflow=true;setStatus("FIFO 溢出：此次事件日志不完整");}
            if(line.startsWith("REC_END,")){recording=false;recordDraining=false;if(!line.equals("REC_END,0"))recordingOverflow=true;recordingCompleted=line.equals("REC_END,0")&&!recordingOverflow;setStatus(recordingOverflow?"录制结束，检测到溢出，日志不完整":"录制结束，事件日志可导出");}}
    }
    private void exportLog(){if(recordingText.length()==0){alert("暂无日志，请先 REC_START 记录演奏事件");return;}Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("text/plain");i.putExtra(Intent.EXTRA_TITLE,"fpga-performance-"+System.currentTimeMillis()+".txt");startActivityForResult(i,EXPORT_LOG);}
    private AudioTakeStatus readHc05AudioStatus()throws Exception {
        AudioTakeStatus state=RecordingSupport.readAudio(link);
        main.post(()->audioInfo.setText(state.description()));return state;
    }
    private void prepareHc05Audio(){task(()->{
        AudioTakeStatus before=readHc05AudioStatus();
        if(before.prepared&&!before.busy&&before.error==0)return;
        if(before.busy)throw new IOException("板上录音正在忙，请稍后读取状态："+before.description());
        link.command("AREC_PREP","OK");main.post(()->audioInfo.setText("正在擦除备用槽；上一条有效录音保持不变。典型约30～60秒，器件最坏情况可能更久。"));
        for(int n=0;n<360;n++){Thread.sleep(1000);AudioTakeStatus s=readHc05AudioStatus();if(s.error!=0)throw new IOException(s.description());if(s.prepared)return;if(!s.busy)throw new IOException("Flash准备失败："+s.description());}
        throw new IOException("Flash准备超过6分钟，请检查供电、JEDEC型号和状态码");
    },"30秒录音槽已准备；现在可以开始录制");}
    private void startHc05Audio(){if(audioTakeActive){alert("已有录制或回传正在进行");return;}task(()->{
        AudioTakeStatus s=readHc05AudioStatus();if(!s.prepared||s.busy||s.error!=0)throw new IOException("请先准备录音槽："+s.description());audioStartGeneration=s.generation;
        link.command("AREC_START,0","OK");audioTakeActive=true;main.post(()->audioInfo.setText("正在板上录制最终数字混音；上限30秒，实时声音和LED继续运行。"));
    },"现场PCM录制已开始");}
    private void stopHc05Audio(){if(!audioTakeActive){alert("当前没有正在进行的板上PCM录制");return;}task(()->{
        link.command("AREC_STOP","OK");main.post(()->audioInfo.setText("已停止采样，正在排空FIFO并从Flash读回CRC校验…"));
        for(int n=0;n<30;n++){Thread.sleep(1000);AudioTakeStatus s=readHc05AudioStatus();if(!s.busy){audioTakeActive=false;if(s.error!=0||s.overflow||!s.valid||s.generation==audioStartGeneration)throw new IOException("本次录音未确认提交："+s.description());return;}}
        throw new IOException("停止校验超过30秒；录音未确认提交");
    },"板上录音已完成读回校验，可开始HC-05回传");}
    private void downloadHc05Audio(){if(audioTakeActive||link.audioActive()){alert("请先结束当前录制或回传");return;}
        final int session=new java.security.SecureRandom().nextInt(65536),generation=++audioGeneration;
        final File file=new File(getFilesDir(),"fpga-hc05-"+System.currentTimeMillis()+".INCOMPLETE.wav");
        task(()->{AudioRecording take=new AudioRecording(file,session);hc05Audio=take;
            try{AudioTakeStatus available=readHc05AudioStatus();if(available.busy||!available.valid)throw new IOException("请先完成板上PCM录制并校验："+available.description());stopLedPreviewForAudio();audioTakeActive=true;link.downloadAudio(take);audioLastProgress=SystemClock.uptimeMillis();
                main.post(()->{getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);audioInfo.setText("等待FAR1开始包；随后每包CRC并ACK。请保持App前台。 ");watchHc05Audio(generation);});
            }catch(Exception e){take.close();hc05Audio=null;audioTakeActive=false;throw e;}
        },"HC-05音频回传已启动");
    }
    private void watchHc05Audio(int generation){main.postDelayed(()->{
        if(generation!=audioGeneration||!audioTakeActive||!link.audioActive())return;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if(SystemClock.uptimeMillis()-audioLastProgress>10000){link.close();audioInfo.setText("10秒未收到可校验数据，连接已关闭；WAV标记为INCOMPLETE");}
        else watchHc05Audio(generation);
    },2000);}
    private void finishHc05Audio(AudioRecording take){if(take==null)return;
        hc05Audio=null;audioTakeActive=false;++audioGeneration;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        lastAudioFile=take.file();lastAudioComplete=take.complete();
        audioInfo.setText(take.complete()?"完整WAV已保存（"+take.bytesWritten()+"字节PCM），可播放或导出":"INCOMPLETE WAV仅保留已验证前缀："+take.problem());
    }
    private void stopLedPreviewForAudio(){
        main.post(()->{stopLedPreview("音频回传占用HC-05，预览已暂停");voiceBend.clearPending();});
    }
    private void playAudio(){if(lastAudioFile==null||!lastAudioFile.isFile()){alert("暂无手机WAV，请先完成回传");return;}
        try{if(audioPlayer!=null)audioPlayer.release();audioPlayer=new MediaPlayer();audioPlayer.setDataSource(lastAudioFile.getAbsolutePath());audioPlayer.prepare();audioPlayer.start();audioInfo.setText("正在播放 "+(lastAudioComplete?"完整":"INCOMPLETE前缀")+" WAV");}
        catch(Exception e){alert("无法播放WAV："+e.getMessage());}
    }
    private void connectAudioUsb(){
        if(!USB_AUDIO_BACKUP_ENABLED||audioUsb==null){alert("USB高速录音保留备用，当前仅启用HC-05通信");return;}
        if(audioTakeActive){alert("请先停止或中止当前音频录制");return;}
        List<UsbAudioLink.Choice> choices=audioUsb.choices();
        if(choices.isEmpty()){alert("未发现USB串口模块，请检查OTG、USB Host和模块接线");return;}
        String[] labels=new String[choices.size()];for(int n=0;n<labels.length;n++)labels[n]=choices.get(n).toString();
        new AlertDialog.Builder(this).setTitle("选择录音USB串口").setItems(labels,(d,n)->audioUsb.connect(choices.get(n))).show();
    }
    private void startAudioRecording(){
        if(!USB_AUDIO_BACKUP_ENABLED||audioUsb==null){alert("USB高速录音保留备用，当前仅启用HC-05通信");return;}
        if(busy)return;
        if(audioTakeActive){alert("音频正在录制或等待排空");return;}
        if(!audioUsb.connected()||!link.connected()){alert("请同时连接HC-05控制与USB录音通道");return;}
        final int session=new java.security.SecureRandom().nextInt(65536),generation=++audioGeneration;
        final File file=new File(getCacheDir(),"fpga-live-"+System.currentTimeMillis()+".wav");
        audioTakeActive=true;getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        task(()->{
            try{
                link.command("AREC_ABORT","OK");audioUsb.begin(file,session);
                link.command("AREC_START,"+session,"OK");
                main.post(()->{audioInfo.setText("开始命令已确认，等待USB音频…");
                    main.postDelayed(()->{if(audioTakeActive&&generation==audioGeneration&&!audioUsb.started()){
                        cancelAudioRecording();audioInfo.setText("未收到录音开始包，请检查TX/RXD、RTS、2Mbps设置和供电");
                    }},5000);
                });
            }catch(Exception e){audioUsb.cancel();abortAudioCommand();main.post(()->{audioTakeActive=false;++audioGeneration;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);});throw e;}
        },"现场音频录制已启动");
    }
    private void stopAudioRecording(){
        if(busy)return;
        if(!audioTakeActive){alert("当前没有正在进行的音频录制");return;}
        if(!link.connected()){alert("USB录音仍在继续，请重连HC-05后停止；也可中止并保留不完整前缀");return;}
        final int generation=audioGeneration;
        task(()->{link.command("AREC_STOP","OK");main.post(()->{
            audioInfo.setText("停止命令已确认，正在排空音频并校验结束包…");
            main.postDelayed(()->{if(audioTakeActive&&generation==audioGeneration){cancelAudioRecording();audioInfo.setText("结束包超时，此次录音不完整");}},5000);
        });},"已停止采集，等待USB录音结束标记");
    }
    private void abortAudioCommand(){
        if(!link.connected()||worker.isShutdown())return;
        worker.execute(()->{try{link.command("AREC_ABORT","OK");}catch(Exception ignored){}});
    }
    private void cancelAudioRecording(){
        audioTakeActive=false;++audioGeneration;if(audioUsb!=null){audioUsb.cancel();abortAudioCommand();}
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private void exportAudio(){
        if(audioTakeActive){alert("请先停止录制并等待结束包");return;}
        if(lastAudioFile==null||!lastAudioFile.isFile()){alert("暂无可导出的音频录音");return;}
        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("audio/wav");
        intent.putExtra(Intent.EXTRA_TITLE,"fpga-live-"+(lastAudioComplete?"":"INCOMPLETE-")+System.currentTimeMillis()+".wav");
        startActivityForResult(intent,EXPORT_AUDIO);
    }
    @Override protected void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);if(exportingScore!=null)state.putString("exportingScore",exportingScore.id);}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(appearance.onActivityResult(request,result,data))return;if(result!=RESULT_OK||data==null||data.getData()==null){if(request==EXPORT_SCORE)exportingScore=null;return;}Uri uri=data.getData();
        if(request==EXPORT_PHONE){final byte[] midi=phoneExportMidi;if(midi==null){alert("请重新选择手机录制后导出");return;}phoneWork(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建 MIDI 文件");out.write(midi);}},"手机 MIDI 已导出");
        }else if(request==PICK_SCORE){String display="导入曲谱";try(Cursor c=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)){if(c!=null&&c.moveToFirst())display=c.getString(0);}catch(Exception ignored){}final String name=display;
            task(()->{byte[] bytes;try(InputStream in=getContentResolver().openInputStream(uri);ByteArrayOutputStream out=new ByteArrayOutputStream()){if(in==null)throw new IOException("无法打开文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(out.size()+n>2*1024*1024)throw new IOException("文件超过 2MB");out.write(b,0,n);}bytes=out.toByteArray();}SongCodec.Song parsed=SongCodec.parse(name,bytes);main.post(()->{song=parsed;showSong();});},"曲谱已导入；下载前会核对实际键位");
        }else if(request==EXPORT_SCORE){final SongLibrary.Entry selected=exportingScore;exportingScore=null;if(selected==null)return;
            task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建曲谱文件");out.write(selected.csv());}},"《"+selected.title+"》已保存到所选文件夹，可通过 CSV 导入入口再次使用");
        }else if(request==EXPORT_LOG){final byte[] bytes=("# FPGA performance events; audio is not recorded\n# complete="+(recordingCompleted&&!recordingOverflow)+"\n"+recordingText).getBytes(StandardCharsets.UTF_8);task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建日志文件");out.write(bytes);}},"事件日志已导出");
        }else if(request==EXPORT_AUDIO){final File source=lastAudioFile;task(()->{
            try(InputStream in=new FileInputStream(source);OutputStream out=getContentResolver().openOutputStream(uri)){
                if(out==null)throw new IOException("无法创建导出文件");byte[] buffer=new byte[65536];int n;
                while((n=in.read(buffer))!=-1)out.write(buffer,0,n);
            }
        },"录音WAV已导出");}
    }
    private void alert(String message){new AlertDialog.Builder(this).setTitle("提示").setMessage(message).setPositiveButton("知道了",null).show();}
    @Override protected void onStop(){if(ledPreviewRunning)stopLedPreview("App 已离开前台，预览已停止。");if(phoneRecording)stopPhoneRecording();if(phonePiano!=null){phonePiano.close();phonePiano=null;}super.onStop();}
    @Override protected void onDestroy(){stopLedPreview("预览已停止。");voiceBend.clearPending();if(audioUsb!=null)audioUsb.destroy();if(audioPlayer!=null)audioPlayer.release();if(phonePiano!=null)phonePiano.close();main.removeCallbacksAndMessages(null);cancelled=true;link.close();worker.shutdownNow();phoneWorker.shutdownNow();if(appearance!=null)appearance.close();super.onDestroy();}
}
