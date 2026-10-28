package cn.fpga.score;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Explicit CSV glide targets; normal scores and MIDI keep the original codec. */
public final class ScoreBends {
    public static final String HEADER="pitches,duration_ms,bend_target_cents";
    public final SongCodec.Song song;
    private final Integer[] targets;
    private final int[] types;
    private final boolean extendedCsv,typedCsv;
    private ScoreBends(SongCodec.Song song,Integer[] targets,boolean extended){
        this(song,targets,extended,new int[song.events.size()],false);
    }
    private ScoreBends(SongCodec.Song song,Integer[] targets,boolean extended,int[] types,boolean typed){
        this.song=song;this.targets=targets.clone();this.extendedCsv=extended;
        this.types=types.clone();this.typedCsv=typed;
        if(targets.length!=song.events.size()||types.length!=targets.length)throw new IllegalArgumentException("元数据数量与事件数不同");
    }
    public static ScoreBends plain(SongCodec.Song song){return new ScoreBends(song,new Integer[song.events.size()],false);}
    public boolean hasBends(){for(Integer value:targets)if(value!=null)return true;return false;}
    public boolean hasTypes(){return typedCsv;}
    public int type(int event){return types[event];}
    public Integer target(int event){return targets[event];}
    public String describe(int event){return (typedCsv?new String[]{"AUTO","TAP","HOLD","DRAG","FLICK"}[types[event]]+" · ":"")+
        (targets[event]==null?"沿用手动弯音目标":String.format(Locale.ROOT,"滑入目标 %+d 音分",targets[event]));}
    public static ScoreBends parse(String name,byte[] data)throws IOException {
        if(data.length>2*1024*1024)throw new IOException("曲谱文件超过 2MB");
        // The legacy MIDI decoder explicitly rejects non-centre bend messages.
        if((data.length>=4&&data[0]=='M'&&data[1]=='T'&&data[2]=='h'&&data[3]=='d')||name.toLowerCase(Locale.ROOT).matches(".*\\.midi?"))
            return plain(SongCodec.parse(name,data));
        String text=new String(data,StandardCharsets.UTF_8).replace("\uFEFF","");String header="";
        for(String line:text.split("\\r?\\n")){line=line.trim();if(line.isEmpty()||line.startsWith("#"))continue;header=line.toLowerCase(Locale.ROOT);break;}
        boolean extended=header.equals(HEADER)||header.equals(HEADER+",note_type");
        boolean typed=header.equals("pitches,duration_ms,note_type")||header.equals(HEADER+",note_type");
        if(!extended&&!typed)return plain(SongCodec.parse(name,data));
        List<SongCodec.Event> events=new ArrayList<>();List<Integer> bends=new ArrayList<>(),noteTypes=new ArrayList<>();int row=0;
        for(String line:text.split("\\r?\\n")){
            row++;line=line.trim();if(line.isEmpty()||line.startsWith("#")||line.equalsIgnoreCase(header))continue;
            String[] fields=line.split(",",-1);
            if(fields.length!=2+(extended?1:0)+(typed?1:0))throw new IOException("CSV 第 "+row+" 行列数与表头不一致");
            try{
                String value=extended?fields[2].trim():"";Integer cents=null;int type=0;
                if(typed){String kind=fields[extended?3:2].trim().toUpperCase(Locale.ROOT);
                    if(!kind.isEmpty())type=Arrays.asList("AUTO","TAP","HOLD","DRAG","FLICK").indexOf(kind);
                    if(type<0)throw new IllegalArgumentException("note_type 只能为 AUTO / TAP / HOLD / DRAG / FLICK");}
                if(!value.isEmpty()){
                    if(!value.matches("[+-]?[0-9]{1,4}"))throw new IllegalArgumentException("同一和弦只接受一个整数弯音目标，不支持各音独立偏移");
                    cents=Integer.valueOf(value);VoiceBend.ratio(cents);
                }
                SongCodec.Song parsed=SongCodec.csv(name,(fields[0]+","+fields[1]).getBytes(StandardCharsets.UTF_8));
                for(SongCodec.Event event:parsed.events){
                    if(event.mask==0&&cents!=null)throw new IllegalArgumentException("休止行的弯音目标应留空");
                    if(event.mask==0&&type!=0)throw new IllegalArgumentException("休止行的 note_type 应留空或 AUTO");
                    if(events.size()>=SongCodec.MAX_EVENTS)throw new IllegalArgumentException("转换后超过 "+SongCodec.MAX_EVENTS+" 条记录，不会丢弃弯音事件");
                    events.add(event);bends.add(cents);noteTypes.add(type);
                }
            }catch(IllegalArgumentException e){throw new IOException("CSV 第 "+row+" 行："+e.getMessage(),e);}
        }
        int[] parsedTypes=new int[noteTypes.size()];for(int n=0;n<parsedTypes.length;n++)parsedTypes[n]=noteTypes.get(n);
        try{return new ScoreBends(new SongCodec.Song(name,events),bends.toArray(new Integer[0]),extended,parsedTypes,typed);}
        catch(IllegalArgumentException e){throw new IOException(e.getMessage(),e);}
    }
    public void checkRange(int minimum,int maximum)throws IOException {
        for(int n=0;n<targets.length;n++)if(targets[n]!=null){int ratio=VoiceBend.ratio(targets[n]);
            if(ratio<minimum||ratio>maximum)throw new IOException("第 "+(n+1)+" 条弯音目标超出设备当前范围，请先扩大弯音范围再下载 / 演奏");}
    }
    public static void checkCapability(String response)throws IOException {
        if(!"SONGBEND,1".equals(response))throw new IOException("设备未确认曲谱弯音格式，未发送曲谱数据");
    }
    public List<String> commands(){
        List<String> result=new ArrayList<>();result.add("SONG_BEGIN,"+song.events.size());
        for(int n=0;n<song.events.size();n++){SongCodec.Event event=song.events.get(n);
            result.add("SONG_CHORD,"+n+","+(event.mask|(types[n]<<13))+","+event.durationMs+(targets[n]==null?"":","+VoiceBend.ratio(targets[n])));}
        result.add("SONG_END");return result;
    }
    public byte[] csv(){
        StringBuilder result=new StringBuilder(extendedCsv?HEADER:"pitches,duration_ms");if(typedCsv)result.append(",note_type");result.append('\n');
        for(int n=0;n<song.events.size();n++){SongCodec.Event event=song.events.get(n);boolean first=true;
            if(event.mask==0)result.append("REST");else for(int note=60;note<=72;note++)if((event.mask&(1<<(note-60)))!=0){if(!first)result.append('+');result.append(note);first=false;}
            result.append(',').append(event.durationMs);
            if(extendedCsv){result.append(',');if(targets[n]!=null)result.append(targets[n]);}
            if(typedCsv){result.append(',');if(types[n]!=0)result.append(new String[]{"AUTO","TAP","HOLD","DRAG","FLICK"}[types[n]]);}result.append('\n');
        }
        return result.toString().getBytes(StandardCharsets.UTF_8);
    }
}
