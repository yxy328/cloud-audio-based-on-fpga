package cn.fpga.score;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;

/** Offline, seven-key editions of public-domain melodies. No audio or network dependency. */
public final class SongLibrary {
    private static final Pattern NOTE=Pattern.compile("(r|[A-G](?:#|b)?[0-8])([whqe])(\\.)?");
    public enum Tier {
        BRONZE("青铜", "入门 · 稳定节拍与短旋律"),
        SILVER("白银", "进阶 · 八分音符与附点节奏"),
        GOLD("黄金", "挑战 · 长乐句与复合节拍");
        public final String title, description;
        Tier(String title, String description) { this.title=title; this.description=description; }
    }

    public static final class Entry {
        public final String id, title, englishTitle, time, edition, sourceUrl;
        public final Tier tier;
        public final int bpm;
        private final SongCodec.Song score;
        private Entry(String id, String title, String englishTitle, Tier tier, String time,
                      int bpm, String edition, String notation) {
            this.id=id; this.title=title; this.englishTitle=englishTitle; this.tier=tier;
            this.time=time; this.bpm=bpm; this.edition=edition;
            sourceUrl="https://www.printablegarden.com/sheet-music/"+id+"/";
            score=decode(title+"（"+tier.title+" · 七键版）",time,bpm,notation);
            if(Integer.bitCount(score.requiredMask())>7)throw new IllegalArgumentException("曲库曲目超过七种音高："+id);
        }
        public SongCodec.Song song() { return score; }
        public byte[] csv() {
            StringBuilder out=new StringBuilder("# ").append(title).append(" / ").append(tier.title)
                .append("\n# ").append(sourceUrl).append("\n# ").append(edition).append("\npitches,duration_ms\n");
            for(SongCodec.Event e:score.events) {
                if(e.mask==0)out.append("REST");
                else {boolean first=true;for(int n=60;n<=72;n++)if((e.mask&(1<<(n-60)))!=0){if(!first)out.append('+');out.append(n);first=false;}}
                out.append(',').append(e.durationMs).append('\n');
            }
            return out.toString().getBytes(StandardCharsets.UTF_8);
        }
    }

    private static Entry entry(String id, String title, String english, Tier tier, String time,
                               int bpm, String edition, String notation) {
        return new Entry(id,title,english,tier,time,bpm,edition,notation);
    }
    private static final List<Entry> ALL=Collections.unmodifiableList(Arrays.asList(
        entry("hot-cross-buns","十字面包","Hot Cross Buns",Tier.BRONZE,"4/4",100,
            "G 大调单旋律；使用 G4、A4、B4。",
            "B4q A4q G4h | B4q A4q G4h | G4e G4e G4e G4e A4e A4e A4e A4e | B4q A4q G4h"),
        entry("mary-had-a-little-lamb","玛丽有只小羊羔","Mary Had a Little Lamb",Tier.BRONZE,"4/4",108,
            "C 大调单旋律；练习重复音与稳定节拍。",
            "E4q D4q C4q D4q | E4q E4q E4h | D4q D4q D4h | E4q G4q G4h | E4q D4q C4q D4q | E4q E4q E4q E4q | D4q D4q E4q D4q | C4w"),
        entry("twinkle-twinkle-little-star","小星星","Twinkle, Twinkle, Little Star",Tier.BRONZE,"4/4",96,
            "C 大调完整旋律，共 12 小节。",
            "C4q C4q G4q G4q | A4q A4q G4h | F4q F4q E4q E4q | D4q D4q C4h | G4q G4q F4q F4q | E4q E4q D4h | G4q G4q F4q F4q | E4q E4q D4h | C4q C4q G4q G4q | A4q A4q G4h | F4q F4q E4q E4q | D4q D4q C4h"),
        entry("au-clair-de-la-lune","月光下","Au Clair de la Lune",Tier.SILVER,"4/4",92,
            "原 G 大调旋律整体下移 2 个半音至 F 大调，保持音程与节奏，适配七键音域。",
            "F4q F4q F4q G4q | A4h G4h | F4q A4q G4q G4q | F4w | F4q F4q F4q G4q | A4h G4h | F4q A4q G4q G4q | F4w | G4q G4q G4q G4q | D4h D4h | G4q F4q E4q D4q | C4w | F4q F4q F4q G4q | A4h G4h | F4q A4q G4q G4q | F4w"),
        entry("frere-jacques","两只老虎","Frère Jacques (Are You Sleeping?)",Tier.SILVER,"4/4",104,
            "C 大调七键改编；末两小节的低音 G3 上移八度为 G4，其余旋律与节奏保留。",
            "C4q D4q E4q C4q | C4q D4q E4q C4q | E4q F4q G4h | E4q F4q G4h | G4e A4e G4e F4e E4q C4q | G4e A4e G4e F4e E4q C4q | C4q G4q C4h | C4q G4q C4h"),
        entry("london-bridge-is-falling-down","伦敦桥要塌了","London Bridge Is Falling Down",Tier.SILVER,"4/4",108,
            "C 大调单旋律；保留开头附点四分音符、八分音符和结尾一拍休止。",
            "G4q. A4e G4q F4q | E4q F4q G4h | D4q E4q F4h | E4q F4q G4h | G4q. A4e G4q F4q | E4q F4q G4h | D4h G4h | E4q C4h rq"),
        entry("ode-to-joy","欢乐颂","Ode to Joy",Tier.GOLD,"4/4",100,
            "C 大调七键改编；第 12 小节低音 G3 上移八度为 G4，保留附点与八分音符。",
            "E4q E4q F4q G4q | G4q F4q E4q D4q | C4q C4q D4q E4q | E4q. D4e D4h | E4q E4q F4q G4q | G4q F4q E4q D4q | C4q C4q D4q E4q | D4q. C4e C4h | D4q D4q E4q C4q | D4q E4e F4e E4q C4q | D4q E4e F4e E4q D4q | C4q D4q G4h | E4q E4q F4q G4q | G4q F4q E4q D4q | C4q C4q D4q E4q | D4q. C4e C4h"),
        entry("jingle-bells","铃儿响叮当","Jingle Bells",Tier.GOLD,"4/4",120,
            "C 大调副歌，共 16 小节；练习连续重复音与附点节奏。",
            "E4q E4q E4h | E4q E4q E4h | E4q G4q C4q. D4e | E4w | F4q F4q F4q. F4e | F4q E4q E4q E4e E4e | E4q D4q D4q E4q | D4h G4h | E4q E4q E4h | E4q E4q E4h | E4q G4q C4q. D4e | E4w | F4q F4q F4q. F4e | F4q E4q E4q E4e E4e | G4q G4q F4q D4q | C4w"),
        entry("row-row-row-your-boat","划小船","Row, Row, Row Your Boat",Tier.GOLD,"6/8",56,
            "C 大调单旋律；6/8 拍以附点四分音符为一拍。需要高音 C5，下载按钮会匹配七键。",
            "C4q. C4q. | C4q D4e E4q. | E4q D4e E4q F4e | G4h. | C5e C5e C5e G4e G4e G4e | E4e E4e E4e C4e C4e C4e | G4q F4e E4q D4e | C4h.")
    ));

    public static List<Entry> all() { return ALL; }
    public static List<Entry> in(Tier tier) {
        List<Entry> out=new ArrayList<>();for(Entry e:ALL)if(e.tier==tier)out.add(e);
        return Collections.unmodifiableList(out);
    }

    /** Keep existing required keys; replace only unused pitches or duplicate slots. */
    public static int[] matchingMapping(SongCodec.Song song, int[] current) {
        if(current==null||current.length!=7)throw new IllegalArgumentException("请先读取七键映射");
        int required=song.requiredMask();
        if(Integer.bitCount(required)>7)throw new IllegalArgumentException("曲谱超过七种音高，不能自动匹配");
        int[] out=current.clone();int covered=0;List<Integer> spare=new ArrayList<>();
        for(int i=0;i<7;i++) {
            if(out[i]<60||out[i]>72)throw new IllegalArgumentException("键位超出 MIDI 60..72");
            int bit=1<<(out[i]-60);
            if((required&bit)!=0&&(covered&bit)==0)covered|=bit;else spare.add(i);
        }
        int slot=0;
        for(int n=60;n<=72;n++)if((required&(1<<(n-60)))!=0&&(covered&(1<<(n-60)))==0)
            out[spare.get(slot++)]=n;
        song.checkMapping(out);return out;
    }

    private static SongCodec.Song decode(String title, String time, int bpm, String notation) {
        List<SongCodec.Event> events=new ArrayList<>();int ticks=0,barTicks=0;
        int perBar=time.equals("6/8")?12:16,perBeat=time.equals("6/8")?6:4;
        long previousMs=0;
        for(String token:notation.split("\\s+")) {
            if(token.equals("|")) {if(barTicks!=perBar)throw new IllegalArgumentException("小节时值错误："+title);barTicks=0;continue;}
            Matcher m=NOTE.matcher(token);if(!m.matches())throw new IllegalArgumentException("曲库音符格式错误："+token);
            int length=new int[]{16,8,4,2}["whqe".indexOf(m.group(2))];
            if(m.group(3)!=null)length=length*3/2;
            int mask=0;String pitch=m.group(1);
            if(!pitch.equals("r")) {
                int n=12*(pitch.charAt(pitch.length()-1)-'0'+1)+new int[]{0,2,4,5,7,9,11}["CDEFGAB".indexOf(pitch.charAt(0))];
                if(pitch.length()==3)n+=pitch.charAt(1)=='#'?1:-1;
                if(n<60||n>72)throw new IllegalArgumentException("曲库音域超出 C4..C5："+token);
                mask=1<<(n-60);
            }
            ticks+=length;barTicks+=length;
            long endMs=Math.round(ticks*60000.0/(bpm*perBeat));
            events.add(new SongCodec.Event(mask,(int)(endMs-previousMs)));previousMs=endMs;
        }
        if(barTicks!=perBar)throw new IllegalArgumentException("末小节时值错误："+title);
        return new SongCodec.Song(title,events);
    }
    private SongLibrary() {}
}
