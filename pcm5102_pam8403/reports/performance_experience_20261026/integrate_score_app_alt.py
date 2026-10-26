"""Apply the staged D phone adapter only after the final hardware admission audit."""
from work import *
import re
audits=json.loads((HERE/'build_audit.json').read_text(encoding='utf-8'))
assert audits['score_bend_alt']['can_integrate_resource_and_timing_only'], 'D admission not yet passed'
for name, required in [('score_alt_regression.log','PASS tb_score_legacy'),('score_bend_words.log','PASS D target words'),
                       ('score_bend_frame_take.log','PASS score bend target'),('score_app_alt_tests.log','4827 checks')]:
    assert required in (HERE/name).read_text(encoding='utf-8',errors='replace'),name
app=PROJECT/'android_app';java=app/'app/src/main/java/cn/fpga/score'
path=java/'MainActivity.java';s=path.read_text(encoding='utf-8-sig')
assert 'private ScoreBends scoreFile;' not in s, 'Do not apply twice'
def replace(old,new):
    global s
    assert old in s,old[:120]
    s=s.replace(old,new,1)
replace('private SongCodec.Song song=SongCodec.twinkle();','private SongCodec.Song song=SongCodec.twinkle();\n    private ScoreBends scoreFile;\n    private byte[] scoreExportCsv;')
replace('EXPORT_PHONE=15;', 'EXPORT_PHONE=15,EXPORT_BEND=16;')
replace('if(state!=null){String id=', 'if(state!=null){scoreExportCsv=state.getByteArray("scoreExportCsv");String id=')
replace('button(box,"查看全部音符与休止",this::preview,true);','''button(box,"查看全部音符与休止",this::preview,true);
        button(box,"导出当前曲谱 CSV",this::exportCurrentScore,true);
        text(box,"带弯音的 CSV 使用 bend_target_cents：每事件一个和弦共用目标，按当前滑音速率靠近；空白沿用手动目标，0 回正。即时静态偏移、和弦各音不同目标和 MIDI 弯音导入暂不支持。",12,MUTED);''')
replace('private void showSong(){', '''private ScoreBends currentScore(){return scoreFile!=null&&scoreFile.song==song?scoreFile:ScoreBends.plain(song);}
    private void checkScoreSupport(ScoreBends selected)throws Exception{
        if(!selected.hasBends())return;
        int[] pitch=PerformanceParams.parsePitch(link.command("PITCH,?","PITCH"));selected.checkRange(pitch[0],pitch[1]);
    }
    private void exportCurrentScore(){
        scoreExportCsv=currentScore().csv();Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("text/csv");
        intent.putExtra(Intent.EXTRA_TITLE,"fpga-score-"+System.currentTimeMillis()+".csv");startActivityForResult(intent,EXPORT_BEND);
    }
    private void showSong(){''')
replace('SongCodec.notes(song.requiredMask()));progress.setProgress(0);}', 'SongCodec.notes(song.requiredMask())+(currentScore().hasBends()?"\\n含弯音目标：按当前滑音速率滑入；设备会核对弯音范围":""));progress.setProgress(0);}')
replace('private void preview(){StringBuilder s=', 'private void preview(){ScoreBends metadata=currentScore();StringBuilder s=')
replace('.append(e.durationMs).append("ms\\n");at+=e.durationMs;', '.append(e.durationMs).append("ms");if(metadata.hasBends())s.append(" · ").append(metadata.describe(i));s.append("\\n");at+=e.durationMs;')
replace('final SongCodec.Song selected=song;\n        task(()->{readMapping();', 'final ScoreBends selectedFile=currentScore();final SongCodec.Song selected=selectedFile.song;\n        task(()->{checkScoreSupport(selectedFile);readMapping();')
replace('List<String> commands=selected.commands();','List<String> commands=selectedFile.commands();')
replace('String command=commands.get(i);link.command(command,"OK");',
        'String command=commands.get(i);try{link.command(command,"OK");}catch(SppLink.CommandRejectedException e){if(i==0&&selectedFile.hasBends()&&e.response.equals("ERR,CMD"))throw new IOException("设备未确认曲谱弯音格式，曲谱数据尚未发送，请使用配套码流");throw e;}')

replace('private void audition(){','private void audition(){final ScoreBends selected=currentScore();')
replace('task(()->{try{link.command("AUDITION","OK");}', 'task(()->{checkScoreSupport(selected);try{link.command("AUDITION","OK");}')
replace('super.onSaveInstanceState(state);if(exportingScore!=null)', 'super.onSaveInstanceState(state);if(scoreExportCsv!=null)state.putByteArray("scoreExportCsv",scoreExportCsv);if(exportingScore!=null)')
replace('if(request==EXPORT_SCORE)exportingScore=null;return;}Uri uri=', 'if(request==EXPORT_SCORE)exportingScore=null;if(request==EXPORT_BEND)scoreExportCsv=null;return;}Uri uri=')
replace('if(request==EXPORT_PHONE){', '''if(request==EXPORT_BEND){final byte[] csv=scoreExportCsv;scoreExportCsv=null;if(csv==null){alert("请重新选择当前曲谱后导出");return;}
            task(()->{try(OutputStream out=getContentResolver().openOutputStream(uri)){if(out==null)throw new IOException("无法创建曲谱文件");out.write(csv);}},"当前曲谱 CSV 已导出，弯音目标已保留");
        }else if(request==EXPORT_PHONE){''')
replace('SongCodec.Song parsed=SongCodec.parse(name,bytes);main.post(()->{song=parsed;showSong();});','ScoreBends parsed=ScoreBends.parse(name,bytes);main.post(()->{scoreFile=parsed;song=parsed.song;showSong();});')
# Only the affected files are changed; concurrent artwork and other app changes stay in place.
path.write_text(s,encoding='utf-8')
shutil.copy2(HERE/'score_app_alt/ScoreBends.java',java/'ScoreBends.java')
shutil.copy2(HERE/'score_app_alt/ScoreBendsTest.java',app/'core_test/ScoreBendsTest.java')
path=app/'test-core.ps1';s=path.read_text(encoding='utf-8-sig');anchor="    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }"
assert anchor in s
s=s.replace(anchor,anchor+r'''
    & javac --release 8 -encoding UTF-8 -cp build\core -d build\core app\src\main\java\cn\fpga\score\ScoreBends.java core_test\ScoreBendsTest.java
    if ($LASTEXITCODE -ne 0) { throw 'Score bend compilation failed' }
    & java -cp build\core cn.fpga.score.ScoreBendsTest
    if ($LASTEXITCODE -ne 0) { throw 'Score bend tests failed' }
''');path.write_text(s,encoding='utf-8')
save(HERE/'score_app_integration.json',{'stage':'phone adapter integrated after final D admission','hardware':'score_bend_alt','old_MIDI_behavior':'unchanged; noncenter bend rejected explicitly','tests':4827})
print('Integrated curve CSV adapter and export; preserved all current artwork')
