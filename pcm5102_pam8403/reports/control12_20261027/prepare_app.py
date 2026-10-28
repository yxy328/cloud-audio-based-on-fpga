from pathlib import Path
import shutil, re

R=Path(__file__).resolve().parent
BASE=R.parents[1]/'android_app'
A=R/'app_candidate'
if A.exists():raise RuntimeError('App candidate already exists')
for folder in ['app','core_test']:
    shutil.copytree(BASE/folder,A/folder,ignore=shutil.ignore_patterns('build','.gradle'))
for name in ['build-apk.ps1','test-core.ps1']:
    shutil.copy2(BASE/name,A/name)
(A/'tools').mkdir()
shutil.copy2(BASE/'tools/debug.keystore',A/'tools/debug.keystore')
J=A/'app/src/main/java/cn/fpga/score'

def change(file,pairs):
    p=J/file;s=p.read_text(encoding='utf-8')
    for old,new in pairs:
        if old not in s:raise RuntimeError(f'{file}: {old}')
        s=s.replace(old,new)
    p.write_text(s,encoding='utf-8')

change('VoiceBend.java',[
    ('public static final int LIMIT=1200;', 'public static final int LIMIT=1200, KEYS=12;'),
    ('[7]','[KEYS]'),('key>7','key>KEYS'),('1～7','1～12'),
    ('i<7','i<KEYS'),('%7','%KEYS')])
change('SongCodec.java',[
    ('mapping.length!=7','(mapping.length!=7&&mapping.length!=12)'),
    ('读取 7 个键位','读取完整键位'),
    ('p.length!=8||','(p.length!=8&&p.length!=13)||'),
    ('int[] m=new int[7];for(int i=0;i<7;i++)','int[] m=new int[p.length-1];for(int i=0;i<m.length;i++)')])
change('SongLibrary.java',[
    ('current.length!=7','(current.length!=7&&current.length!=12)'),
    ('请先读取七键映射','请先读取键位映射'),
    ('Integer.bitCount(required)>7','Integer.bitCount(required)>current.length'),
    ('曲谱超过七种音高，不能自动匹配','曲谱需要的音高种类超过当前可映射键数，不能自动匹配'),
    ('i<7;i++','i<current.length;i++')])
p=J/'MainActivity.java';s=p.read_text(encoding='utf-8')
for old,new in [
    ('new SeekBar[7]','new SeekBar[12]'),('new TextView[7]','new TextView[12]'),('new Integer[7]','new Integer[12]'),
    ('key<7','key<12'),('i<7','i<12'),('new int[7]','new int[12]'),('p.length!=7','p.length!=12'),
    ('七键音高映射','十二键音高映射'),('七声部','十二声部'),('七个声部','十二个声部'),('七个音高','十二个音高'),
    ('前七触摸声部','前十二触摸声部'),('前七个扫描键','前十二个扫描键'),('前七扫描键','前十二扫描键'),
    ('前七个扫描键','前十二个扫描键'),('七键映射','十二键映射'),('七键 MIDI 文本','十二键 MIDI 文本'),
    ('应用七键','应用十二键'),('匹配七键','匹配十二键'),('七键：','十二键：'),('七声部','十二声部'),
    ('第 1～7 键','第 1～12 键'),('第1到第7键','第1到第12键'),('第 1..7 键','第 1..12 键'),
    ('K1～K7','K1～K12'),('请输入 7 个 MIDI','请输入 12 个 MIDI'),
    ('60,61,62,63,64,65,66','60,61,62,63,64,65,66,67,68,69,70,71'),
    ('"K7 · 黑3"','"K7 · 黑3","K8 · 白5","K9 · 黑4","K10 · 白6","K11 · 黑5","K12 · 白7"'),
    ('C4/C#4/D4/D#4/E4/F4/F#4','C4～B4'),
    ('屏幕七列指引','屏幕十二列指引'),('K8～K16 使用固定音高','K13～K16 使用固定高音'),
    ('默认七键只覆盖 C4～F#4','默认十二键覆盖 C4～B4'),
    ('曲库可匹配改键后下载','需要 C5 的曲库可匹配改键后下载'),
]:s=s.replace(old,new)
# Require the complete mapping response before treating this as a paired
# twelve-control device. Seven-key parsers remain available for old log files.
s=s.replace('int[] m=SongCodec.parseMapping(link.command("MAP?","MAP"));mapping=m;',
    'int[] m=SongCodec.parseMapping(link.command("MAP?","MAP"));if(m.length!=12)throw new IOException("请使用配套十二声部 FPGA 码流；当前设备仅返回七键映射");mapping=m;')
p.write_text(s,encoding='utf-8')
for p in [A/'app/build.gradle',A/'app/src/main/AndroidManifest.xml']:
    s=p.read_text(encoding='utf-8').replace('versionCode 39','versionCode 40').replace('versionCode="39"','versionCode="40"').replace('1.38-scorebend','1.39-control12')
    p.write_text(s,encoding='utf-8')
p=A/'core_test/VoiceBendTest.java';s=p.read_text().replace('new int[]{0,8}','new int[]{0,13}')
s=s.replace('System.out.println(', '''for(int i=0;i<12;i++)q.edit(i,100+i,true);
        boolean[] seen=new boolean[12];for(int i=0;i<12;i++){int key=q.take();yes(key>=0&&key<12&&!seen[key]);seen[key]=true;}
        yes(q.take()==-1);yes(VoiceBend.command(12,1200).equals("BEND,12,32768"));
        System.out.println(''')
p.write_text(s)
(A/'core_test/Control12Test.java').write_text('''package cn.fpga.score;
public final class Control12Test {
    public static void main(String[] args)throws Exception {
        int[] m=SongCodec.parseMapping("MAP,60,61,62,63,64,65,66,67,68,69,70,71");
        if(m.length!=12||m[11]!=71)throw new AssertionError("twelve mapping");
        SongCodec.Song all=SongCodec.csv("twelve.csv","pitches,duration_ms\\n60+61+62+63+64+65+66+67+68+69+70+71,100\\n".getBytes("UTF-8"));
        all.checkMapping(m);
        SongCodec.Song high=SongCodec.csv("high.csv","pitches,duration_ms\\n72,100\\n".getBytes("UTF-8"));
        int[] matched=SongLibrary.matchingMapping(high,m);high.checkMapping(matched);
        try {SongLibrary.matchingMapping(SongCodec.csv("thirteen.csv","pitches,duration_ms\\n60+61+62+63+64+65+66+67+68+69+70+71+72,100\\n".getBytes("UTF-8")),m);throw new AssertionError("lost note");}catch(IllegalArgumentException expected){}
        ScoreBends bend=ScoreBends.csv("bend.csv","pitches,duration_ms,bend_target_cents\\n60+61+62+63+64+65+66+67+68+69+70+71,100,200\\n".getBytes("UTF-8"));
        bend.song.checkMapping(m);
        if(!bend.csv().contains("200"))throw new AssertionError("bend export");
        System.out.println("PASS Control12: twelve-note chord, high-note remap, thirteen-note rejection, score bend CSV");
    }
}
''',encoding='utf-8')
print(A)
