package cn.fpga.score;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Pure Java score decoder. No Android dependency, no recorded audio. */
public final class SongCodec {
    public static final int MAX_EVENTS = 128;
    public static final class Event {
        public final int mask, durationMs;
        public Event(int mask, int durationMs) {
            if (mask < 0 || mask > 8191) throw new IllegalArgumentException("音高掩码必须为 0..8191");
            if (durationMs < 1 || durationMs > 60000) throw new IllegalArgumentException("每条时长必须为 1..60000ms");
            this.mask = mask; this.durationMs = durationMs;
        }
    }
    public static final class Song {
        public final String name;
        public final List<Event> events;
        public Song(String name, List<Event> events) {
            if (events.isEmpty() || events.size() > MAX_EVENTS) throw new IllegalArgumentException("曲谱必须有 1..128 条记录，当前 " + events.size());
            this.name = name; this.events = Collections.unmodifiableList(new ArrayList<>(events));
        }
        public int requiredMask() { int m=0; for(Event e:events)m|=e.mask; return m; }
        public long durationMs() {long n=0;for(Event e:events)n+=e.durationMs;return n;}
        public List<String> commands() {
            List<String> out = new ArrayList<>(); out.add("SONG_BEGIN,"+events.size());
            for(int i=0;i<events.size();i++) {Event e=events.get(i);out.add("SONG_CHORD,"+i+","+e.mask+","+e.durationMs);}
            out.add("SONG_END"); return out;
        }
        public void checkMapping(int[] mapping) {
            if(mapping==null || mapping.length!=7)throw new IllegalArgumentException("请先连接设备并读取 7 个键位");
            int available=0;for(int n:mapping){checkNote(n);available|=1<<(n-60);}
            int missing=requiredMask() & ~available;
            if(missing!=0)throw new IllegalArgumentException("当前键位缺少："+notes(missing)+"。先在键位配置中修改，再下载。不会丢弃音符。");
        }
    }
    private static void checkNote(int note){if(note<60||note>72)throw new IllegalArgumentException("仅支持 MIDI 60..72，发现 "+note+"。请在制谱软件移调或删去不演奏声部后重新导出。");}
    public static String notes(int mask) {
        if(mask==0)return "休止";
        String[] names={"C4","C#4","D4","D#4","E4","F4","F#4","G4","G#4","A4","A#4","B4","C5"};
        StringBuilder s=new StringBuilder();for(int i=0;i<13;i++)if((mask&(1<<i))!=0){if(s.length()>0)s.append('+');s.append(names[i]);}return s.toString();
    }
    public static Song twinkle() {
        int[] n={60,60,67,67,69,69,67,65,65,64,64,62,62,60}; List<Event> out=new ArrayList<>();
        for(int i=0;i<n.length;i++)out.add(new Event(1<<(n[i]-60),(i==6||i==13)?1000:500));return new Song("小星星（两句）",out);
    }
    /** CSV: pitches,duration_ms. Pitches is REST / 0 / 60 / 60+64+67. */
    public static Song csv(String name, byte[] data) throws IOException {
        String content=new String(data,StandardCharsets.UTF_8).replace("\uFEFF","");
        List<Event> out=new ArrayList<>();String[] lines=content.split("\\r?\\n");int row=0;
        for(String line:lines){row++;line=line.trim();if(line.isEmpty()||line.startsWith("#"))continue;
            if(line.equalsIgnoreCase("pitches,duration_ms"))continue;
            String[] c=line.split(",",-1);if(c.length!=2)throw new IOException("CSV 第 "+row+" 行应为 音符,时长ms");
            try {int mask=0;String p=c[0].trim();if(!p.equals("0")&&!p.equalsIgnoreCase("REST"))for(String ns:p.split("\\+",-1)){int n=Integer.parseInt(ns.trim());checkNote(n);mask|=1<<(n-60);}
                long d=Long.parseLong(c[1].trim());append(out,mask,d);
            }catch(IllegalArgumentException e){throw new IOException("CSV 第 "+row+" 行："+e.getMessage());}
        }return checkedSong(name,out);
    }
    private static void append(List<Event> out,int mask,long duration) {
        if(duration<1)throw new IllegalArgumentException("音符/休止不能短于 1ms");
        if(duration>60000L*MAX_EVENTS)throw new IllegalArgumentException("时长过长，超过 128 条容量");
        while(duration>0){if(out.size()==MAX_EVENTS)throw new IllegalArgumentException("转换后超过 128 条记录；请导出较短的曲谱片段");int d=(int)Math.min(60000,duration);out.add(new Event(mask,d));duration-=d;}
    }
    private static Song checkedSong(String name,List<Event> out) throws IOException {try{return new Song(name,out);}catch(IllegalArgumentException e){throw new IOException(e.getMessage());}}
    private static final class MEvent {
        final long tick;final int kind,a,b,channel,order;
        MEvent(long t,int k,int a,int b,int ch,int o){tick=t;kind=k;this.a=a;this.b=b;channel=ch;order=o;}
    }
    private static final class Cursor {
        final byte[] d;int p,end;
        Cursor(byte[] d,int p,int end){this.d=d;this.p=p;this.end=end;}
        int u8() throws IOException {if(p>=end)throw new IOException("MIDI 数据被截断");return d[p++]&255;}
        int u16() throws IOException{return (u8()<<8)|u8();}
        long u32() throws IOException{return ((long)u16()<<16)|u16();}
        int vlq() throws IOException {int v=0;for(int i=0;i<4;i++){int b=u8();v=(v<<7)|(b&127);if((b&128)==0)return v;}throw new IOException("MIDI 可变长整数超过 4 字节");}
        void skip(long n)throws IOException{if(n<0||n>end-p)throw new IOException("MIDI 区块长度无效");p+=(int)n;}
    }
    /** SMF 0/1, PPQ timing, tempo changes and simultaneous notes. Sustain pedal is rejected. */
    public static Song midi(String name,byte[] data)throws IOException {
        Cursor f=new Cursor(data,0,data.length);
        if(f.u32()!=0x4d546864L)throw new IOException("不是标准 MIDI 文件（缺少 MThd）");
        long header=f.u32();if(header<6||header>data.length-8)throw new IOException("MIDI 头长度无效");
        int format=f.u16(),tracks=f.u16(),division=f.u16();
        if(format>1||tracks<1||(format==0&&tracks!=1))throw new IOException("仅支持 SMF MIDI 类型 0/1");
        if((division&0x8000)!=0||division==0)throw new IOException("仅支持 PPQ MIDI，不支持 SMPTE 时间码");
        f.skip(header-6);List<MEvent> all=new ArrayList<>();int order=0;
        for(int t=0;t<tracks;t++){
            if(f.u32()!=0x4d54726bL)throw new IOException("缺少 MIDI 轨道 MTrk");long len=f.u32();if(len>f.end-f.p)throw new IOException("MIDI 轨道被截断");
            Cursor c=new Cursor(data,f.p,f.p+(int)len);f.skip(len);long tick=0;int running=0;
            while(c.p<c.end){tick+=c.vlq();int status=c.u8();int first=-1;if(status<128){if(running==0)throw new IOException("MIDI running status 无效");first=status;status=running;}
                if(status==255){running=0;int meta=c.u8(),size=c.vlq();if(meta==81){if(size!=3)throw new IOException("MIDI tempo 长度无效");int tempo=(c.u8()<<16)|(c.u8()<<8)|c.u8();if(tempo==0)throw new IOException("MIDI tempo 不能为 0");all.add(new MEvent(tick,2,tempo,0,0,order++));}else c.skip(size);if(meta==47){if(size!=0)throw new IOException("MIDI End Of Track 长度无效");all.add(new MEvent(tick,3,0,0,0,order++));break;}
                }else if(status==240||status==247){running=0;c.skip(c.vlq());}
                else if(status>=128&&status<=239){running=status;int kind=status&240,ch=status&15;int a=first>=0?first:c.u8();int b=(kind==192||kind==208)?0:c.u8();if(a>127||b>127)throw new IOException("MIDI 数据字节无效");
                    if(kind==144||kind==128){if(kind==144&&b>0){if(ch==9)throw new IOException("不支持鼓轨；请只导出旋律/和弦声部");try{checkNote(a);}catch(IllegalArgumentException e){throw new IOException(e.getMessage());}}all.add(new MEvent(tick,(kind==144&&b>0)?1:0,a,b,ch,order++));}
                    if(kind==176&&a==64&&b>=64)throw new IOException("此版不支持 MIDI 延音踏板，请导出展开延音的音符");
                    if(kind==224&&((b<<7)|a)!=8192)throw new IOException("此版曲谱不支持 MIDI 弯音，请先转为固定音高音符");
                }else throw new IOException("不支持的 MIDI 系统消息 "+status);
            }
        }
        Collections.sort(all,(a,b)->{int x=Long.compare(a.tick,b.tick);return x==0?Integer.compare(a.order,b.order):x;});
        int[][] counts=new int[16][128];int active=0,tempo=500000;long previousTick=0,startMs=0;double us=0;List<Event> out=new ArrayList<>();boolean seenNote=false;
        for(int at=0;at<all.size();){long tick=all.get(at).tick;us+=(tick-previousTick)*(double)tempo/division;previousTick=tick;
            if(us/1000.0>60000.0*MAX_EVENTS+1)throw new IOException("曲谱时长超过 RAM 曲谱容量");
            int to=at;boolean boundary=false;while(to<all.size()&&all.get(to).tick==tick){if(all.get(to).kind<=1)boundary=true;to++;}
            long nowMs=Math.round(us/1000.0);
            if(boundary&&nowMs>startMs){try{append(out,active,nowMs-startMs);}catch(IllegalArgumentException e){throw new IOException(e.getMessage());}startMs=nowMs;}
            else if(boundary&&tick>0&&nowMs==startMs)throw new IOException("MIDI 音符边界小于 1ms，无法无损表示");
            for(int i=at;i<to;i++){MEvent e=all.get(i);if(e.kind==2)tempo=e.a;else if(e.kind==1){counts[e.channel][e.a]++;seenNote=true;}else if(e.kind==0&&counts[e.channel][e.a]>0)counts[e.channel][e.a]--;}
            active=0;for(int ch=0;ch<16;ch++)for(int n=60;n<=72;n++)if(counts[ch][n]>0)active|=1<<(n-60);at=to;
        }
        if(active!=0)throw new IOException("MIDI 有未关闭的音符，请确保每个 Note On 都有 Note Off");
        if(!seenNote)throw new IOException("MIDI 没有可演奏音符");long endMs=Math.round(us/1000.0);if(endMs>startMs)try{append(out,0,endMs-startMs);}catch(IllegalArgumentException e){throw new IOException(e.getMessage());}return checkedSong(name,out);
    }
    public static Song parse(String name,byte[] data)throws IOException {
        if(data.length>2*1024*1024)throw new IOException("曲谱文件超过 2MB");
        if(data.length>=4&&data[0]=='M'&&data[1]=='T'&&data[2]=='h'&&data[3]=='d')return midi(name,data);
        if(name.toLowerCase(Locale.ROOT).endsWith(".mid")||name.toLowerCase(Locale.ROOT).endsWith(".midi"))throw new IOException("MIDI 文件头无效");
        return csv(name,data);
    }
    public static int[] parseMapping(String line) {
        String[] p=line.split(",",-1);if(p.length!=8||!p[0].equals("MAP"))throw new IllegalArgumentException("键位响应格式错误");
        int[] m=new int[7];for(int i=0;i<7;i++){m[i]=Integer.parseInt(p[i+1]);checkNote(m[i]);}return m;
    }
}
