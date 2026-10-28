from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'android_app/app/src/main/java/cn/fpga/score/MainActivity.java';s=p.read_text(encoding='utf-8')
s=s.replace('        rhythmDifficulty=choices(box,','        text(box,"同一音高若映射到多个键，会同时提示这些列并按和弦处理；单键对应请设置不同音高。",12,MUTED);\n        rhythmDifficulty=choices(box,')
s=s.replace('        button(box,"读取得分 / 本次结果",()->task(this::readRhythmState,"音游状态已读取"),true);','''        button(box,"读取得分 / 本次结果",()->task(this::readRhythmState,"音游状态已读取"),true);
        LinearLayout liveScore=row(box);
        button(liveScore,"开始刷新分数",this::startLedPreview,true);
        button(liveScore,"停止刷新",()->stopLedPreview("自动刷新已停止，可手动读取最新结果。"),false);''')
s=s.replace('ledPreviewInfo.setText("数据已过期，等待设备；其他命令执行期间预览暂停。");','ledPreviewInfo.setText("数据已过期，等待设备；其他命令执行期间预览暂停。");\n            if(rhythmStatus!=null)rhythmStatus.setText("计分回读已过期，等待设备；板上判定继续运行。");')
s=s.replace('        if(ledPreviewInfo!=null)ledPreviewInfo.setText(reason);','        if(ledPreviewInfo!=null)ledPreviewInfo.setText(reason);\n        if(rhythmStatus!=null)rhythmStatus.setText(reason+"\\n此前回读仅供参考。");')
p.write_text(s,encoding='utf-8')
p=R/'android_app/core_test/RhythmStateTest.java';s=p.read_text(encoding='utf-8')
s=s.replace('String line=new String(Files.readAllBytes(Paths.get(args[0])),StandardCharsets.US_ASCII).trim().toUpperCase(Locale.ROOT);','String line=args.length==0 ? "V,2E4F100100000100100000000000" : new String(Files.readAllBytes(Paths.get(args[0])),StandardCharsets.US_ASCII).trim().toUpperCase(Locale.ROOT);')
s=s.replace('        System.out.println("PASS RhythmState:', '''        if(args.length>1){
            RhythmState top=RhythmState.parse(new String(Files.readAllBytes(Paths.get(args[1])),StandardCharsets.US_ASCII).trim());
            check(top.score==2500&&top.combo==2&&top.best==2&&top.miss==0&&top.session&&!top.playing&&!top.holding);
        }
        System.out.println("PASS RhythmState:''')
p.write_text(s,encoding='utf-8')
p=R/'android_app/test-core.ps1';s=p.read_text(encoding='utf-8')
s=s.replace('} finally { Pop-Location }','''    & javac --release 8 -encoding UTF-8 -d build/core app/src/main/java/cn/fpga/score/RhythmState.java core_test/RhythmStateTest.java
    if($LASTEXITCODE -ne 0){throw 'Rhythm state compilation failed'}
    $rhythmFixtures=@()
    if(Test-Path -LiteralPath ../sim/build/rhythm_snapshot.txt){$rhythmFixtures+= '../sim/build/rhythm_snapshot.txt';if(Test-Path -LiteralPath ../sim/build/rhythm_top_reply.txt){$rhythmFixtures+= '../sim/build/rhythm_top_reply.txt'}}
    & java -cp build/core cn.fpga.score.RhythmStateTest @rhythmFixtures
    if($LASTEXITCODE -ne 0){throw 'Rhythm state tests failed'}
} finally { Pop-Location }''');p.write_text(s,encoding='utf-8')
ref=R/'sim/sensor_staging_reference.v';dest=R/'sim/reference/sensor_staging_reference.v';ref.rename(dest)
p=R/'tools/run_sim.ps1';s=p.read_text(encoding='utf-8').replace("'sim/sensor_staging_reference.v'","'sim/reference/sensor_staging_reference.v'")
s=s.replace('    $selectedTests = if ($Tests)',"    if(!$Netlist){$defaultTests+=@('tb_rhythm_game','tb_rhythm_panel','tb_rhythm_protocol','tb_rhythm_top','tb_sensor_staging_equivalence')}\n    $selectedTests = if ($Tests)")
p.write_text(s,encoding='utf-8')
print('App score refresh/stale status and reproducible tests prepared')
