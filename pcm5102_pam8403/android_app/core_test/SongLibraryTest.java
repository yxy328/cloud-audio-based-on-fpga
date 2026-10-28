package cn.fpga.score;

import java.util.*;

public final class SongLibraryTest {
    private static int checks;
    private static void check(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private static SongLibrary.Entry find(String id){for(SongLibrary.Entry e:SongLibrary.all())if(e.id.equals(id))return e;throw new AssertionError(id);}
    private static void rejects(Runnable work){boolean rejected=false;try{work.run();}catch(IllegalArgumentException expected){rejected=true;}check(rejected,"invalid mapping must fail");}
    public static void main(String[] args)throws Exception{
        check(SongLibrary.all().size()==120,"120 distinct offline scores");
        for(SongLibrary.Tier tier:SongLibrary.Tier.values())check(SongLibrary.in(tier).size()==40,"40 scores per tier");
        long[] durations={9600,17778,30000,41739,18462,17778,38400,32000,17143};
        Set<String> ids=new HashSet<>(),melodies=new HashSet<>();Random random=new Random(29);int index=0;
        for(SongLibrary.Entry entry:SongLibrary.all()){
            SongCodec.Song score=entry.song();
            check(ids.add(entry.id),"unique id");
            if(index<durations.length)check(score.durationMs()==durations[index],"original melody and tempo unchanged: "+entry.id);
            index++;
            check(score.durationMs()>0,"nonempty duration");
            check(score.events.size()<=SongCodec.MAX_EVENTS,"FPGA RAM capacity");check(Integer.bitCount(score.requiredMask())<=12,"twelve mapped pitches maximum");
            if(entry.id.startsWith("oneill-")){
                check(entry.sourceUrl.startsWith("https://github.com/folkies/oneill/blob/23ff756d9b41fde178147ff2f8f736db340f5ddf/1850/abc/"),"pinned original source");
                check(entry.edition.contains("练习版")&&entry.edition.contains("整体移调"),"honest edition metadata");
            }else check(entry.sourceUrl.equals("https://www.printablegarden.com/sheet-music/"+entry.id+"/"),"original source link");
            int firstPitch=Integer.numberOfTrailingZeros(score.requiredMask());
            int firstDuration=score.events.get(0).durationMs;
            StringBuilder melody=new StringBuilder();
            for(SongCodec.Event e:score.events)melody.append(e.mask==0?-1:Integer.numberOfTrailingZeros(e.mask)-firstPitch)
                .append(':').append(Math.round(e.durationMs*1000.0/firstDuration)).append(' ');
            check(melodies.add(melody.toString()),"no duplicate melody disguised as a tempo or transposition variant: "+entry.id);
            List<String> commands=score.commands();check(commands.get(0).equals("SONG_BEGIN,"+score.events.size()),"transaction start");
            check(commands.get(commands.size()-1).equals("SONG_END"),"atomic commit");
            for(String command:commands)check(command.length()+2<=64,"UART line limit");
            check(commands.equals(ScoreBends.plain(score).commands()),"audition and rhythm download identical events");
            SongCodec.Song fromFile=SongCodec.parse(entry.id+".csv",entry.csv());
            check(fromFile.events.size()==score.events.size(),"CSV record count");
            for(int i=0;i<score.events.size();i++){
                check(fromFile.events.get(i).mask==score.events.get(i).mask,"CSV preserves pitch/rest");
                check(fromFile.events.get(i).durationMs==score.events.get(i).durationMs,"CSV preserves rhythm");
            }
            // Real boards can have arbitrary mappings, including seven identical keys.
            // Keep the first existing key for each required pitch, and never mutate the readback.
            for(int trial=0;trial<80;trial++){
                int keys=trial%2==0&&Integer.bitCount(score.requiredMask())<=7?7:12;
                int[] current=new int[keys];for(int k=0;k<keys;k++)current[k]=trial<2?60:60+random.nextInt(13);
                int[] before=current.clone(),matched=SongLibrary.matchingMapping(score,current);score.checkMapping(matched);
                check(Arrays.equals(before,current),"readback must remain unchanged");
                Set<Integer> seen=new HashSet<>();for(int k=0;k<keys;k++)if((score.requiredMask()&(1<<(current[k]-60)))!=0&&seen.add(current[k]))
                    check(matched[k]==current[k],"preserve existing required key positions");
                check(Arrays.equals(matched,SongLibrary.matchingMapping(score,matched)),"matching again does not change keys");
            }
        }
        SongCodec.Song london=find("london-bridge-is-falling-down").song();
        check(find("london-bridge-is-falling-down").tier==SongLibrary.Tier.SILVER,"London Bridge is silver");
        check(london.events.size()==25,"London Bridge complete eight bars");
        check(london.events.get(0).mask==(1<<7)&&london.events.get(0).durationMs==833,"dotted opening G");
        check(london.events.get(1).mask==(1<<9)&&london.events.get(1).durationMs==278,"short opening A");
        check(london.events.get(24).mask==0&&london.events.get(24).durationMs==556,"final quarter rest");
        SongCodec.Song row=find("row-row-row-your-boat").song();
        check((row.requiredMask()&4096)!=0,"keep high C5 at its actual pitch");
        check(row.events.get(0).durationMs==1071,"6/8 tempo counts dotted quarter beats");
        int[] diatonic={60,62,64,65,67,69,71},defaults={60,61,62,63,64,65,66};
        check(Arrays.equals(diatonic,SongLibrary.matchingMapping(london,diatonic)),"London Bridge preserves an existing diatonic mapping");
        int[] matched=SongLibrary.matchingMapping(row,diatonic);check(matched[5]==72&&matched[6]==71,"replace only first unused key with high C");
        for(SongLibrary.Entry entry:SongLibrary.all()){
            int[] available=Integer.bitCount(entry.song().requiredMask())<=7?defaults:new int[]{60,61,62,63,64,65,66,67,68,69,70,71};
            int[] adapted=SongLibrary.matchingMapping(entry.song(),available);entry.song().checkMapping(adapted);
            if(Integer.bitCount(entry.song().requiredMask())>7)rejects(()->SongLibrary.matchingMapping(entry.song(),defaults));
            check(Arrays.equals(defaults,new int[]{60,61,62,63,64,65,66}),"chromatic defaults are not mutated");
        }
        check(!Arrays.equals(defaults,SongLibrary.matchingMapping(london,defaults)),"B1 defaults require matching before London Bridge downloads");
        check(SongCodec.twinkle().events.size()==14,"original short example remains available");
        SongCodec.Song oldFile=SongCodec.csv("local.csv","60+64+67,500\nREST,250\n".getBytes("UTF-8"));
        check(oldFile.events.get(0).mask==145&&oldFile.events.get(1).mask==0,"folder CSV chords and rests still import");
        rejects(()->SongLibrary.matchingMapping(london,null));
        rejects(()->SongLibrary.matchingMapping(london,new int[]{59,62,64,65,67,69,71}));
        rejects(()->SongLibrary.matchingMapping(new SongCodec.Song("eight pitches",Arrays.asList(new SongCodec.Event(255,500))),defaults));
        System.out.println("PASS SongLibrary: "+checks+" assertions");
    }
}
