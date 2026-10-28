from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8');assert old in s,(name,old[:50]);p.write_text(s.replace(old,new),encoding='utf-8')
P='android_app/app/src/main/java/cn/fpga/score/MainActivity.java'
edit(P,'    private TextView ledStatus,ledPreviewInfo;','    private TextView ledStatus,ledPreviewInfo,rhythmStatus;\n    private Spinner rhythmDifficulty,rhythmTheme,rhythmLong,rhythmFx,rhythmWidth;')
edit(P,'        buildLedControls(sections[4]);','        buildRhythmControls(content);\n        buildLedControls(sections[4]);')
edit(P,'    private void buildLedControls(LinearLayout content){','''    private void buildRhythmControls(LinearLayout content){
        LinearLayout box=card(content,"GAME","十二键音游","屏幕从左到右对应 K1～K12，跟随自定义音高映射。计分使用 FPGA 时钟。");
        text(box,"单点与重复音需要重新按下；和弦各键须在判定窗内到位。开启长按后，时长 ≥500 ms 的事件须持续按到下一条；休止不计分。Perfect 1000、Good 500，长按完成额外 500；漏击或断按清连击。",12,MUTED);
        rhythmDifficulty=choices(box,"判定窗口（在相邻事件边界截断）",new String[]{"严格 · ±80 ms","标准 · ±120 ms","宽松 · ±160 ms","练习 · ±200 ms"});rhythmDifficulty.setSelection(1);
        rhythmTheme=choices(box,"音符配色",new String[]{"霓虹青蓝","暖金","简洁白"});
        rhythmLong=choices(box,"长音玩法",new String[]{"仅点按","长音持续保持"});rhythmLong.setSelection(1);
        rhythmFx=choices(box,"击打闪光",new String[]{"关闭","开启"});rhythmFx.setSelection(1);
        rhythmWidth=choices(box,"薄音符宽度（均为 1 像素高）",new String[]{"1 像素","2 像素"});
        rhythmStatus=text(box,"尚未读取音游状态；选择框为设置草稿。",14,ACCENT);
        button(box,"应用音游设置",()->{
            final int config=RhythmState.settings(rhythmDifficulty.getSelectedItemPosition(),rhythmTheme.getSelectedItemPosition(),rhythmLong.getSelectedItemPosition()==1,rhythmFx.getSelectedItemPosition()==1,rhythmWidth.getSelectedItemPosition()==1);
            task(()->{link.command("VIS,0,"+config,"OK");RhythmState state=RhythmState.parse(link.command("VIZ?","V"));
                if(state.settings!=config)throw new IOException("设置回读不一致，请重新读取");
                main.post(()->{if(!cancelled&&link.connected())rhythmStatus.setText("设备设置已确认\\n"+state.description());});},"音游设置已应用并回读确认；开始曲谱后计分");
        },true);
        button(box,"读取得分 / 本次结果",()->task(this::readRhythmState,"音游状态已读取"),true);
        text(box,"播放中不能改音游设置。自动演奏不计分。下方“实时预览”也可持续读取分数，手机显示延迟不影响板上判定。长按以当前曲谱事件为单位；此版不含下落尾条。",12,MUTED);
    }
    private void readRhythmState()throws Exception{
        RhythmState state=RhythmState.parse(link.command("VIZ?","V"));
        main.post(()->{if(!cancelled&&link.connected())rhythmStatus.setText("设备最近回读：\\n"+state.description());});
    }
    private void buildLedControls(LinearLayout content){''')
edit(P,'                LedFrame frame=LedFrame.parse(link.command("VIZ?","V"));','''                String line=link.command("VIZ?","V");
                if(RhythmState.isGame(line)){
                    RhythmState game=RhythmState.parse(line);
                    main.post(()->{
                        if(generation!=ledGeneration || !ledPreviewRunning || !link.connected())return;
                        ledLastFrameAt=SystemClock.uptimeMillis();ledPreview.setFrame(null);
                        ledPreviewInfo.setText(game.description());rhythmStatus.setText("FPGA 实时计分：\\n"+game.description());
                        main.removeCallbacks(ledStale);main.postDelayed(ledStale,1500);
                    });return;
                }
                LedFrame frame=LedFrame.parse(line);''')
edit('android_app/app/build.gradle',"versionCode 40; versionName '1.39-control12'","versionCode 41; versionName '1.40-rhythm-candidate'")
edit('android_app/app/src/main/AndroidManifest.xml','android:versionCode="40" android:versionName="1.39-control12"','android:versionCode="41" android:versionName="1.40-rhythm-candidate"')
print('App candidate prepared')
