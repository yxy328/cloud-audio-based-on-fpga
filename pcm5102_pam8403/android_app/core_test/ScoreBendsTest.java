package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class ScoreBendsTest {
    private static int checks;
    static void yes(boolean value){checks++;if(!value)throw new AssertionError("Bend CSV "+checks);}
    interface Check {void run()throws Exception;}
    static void bad(Check action){try{action.run();throw new AssertionError("Expected rejection");}catch(IOException|IllegalArgumentException expected){checks++;}catch(Exception e){throw new AssertionError(e);}}
    static ScoreBends parse(String content)throws Exception{return ScoreBends.parse("test.csv",content.getBytes(StandardCharsets.UTF_8));}
    public static void main(String[] args)throws Exception {
        ScoreBends old=parse("pitches,duration_ms\n60+64,500\nREST,250\n");yes(!old.hasBends());yes(old.commands().equals(old.song.commands()));
        ScoreBends s=parse(ScoreBends.HEADER+"\n60+64,500,100\n62,500,-200\nREST,250,\n60,70000,0\n61,20,\n");
        yes(s.song.events.size()==6&&s.hasBends());yes(s.target(0)==100&&s.target(1)==-200&&s.target(2)==null);
        yes(s.target(3)==0&&s.target(4)==0&&s.target(5)==null);yes(s.song.durationMs()==71270);
        yes(s.commands().get(1).endsWith(","+VoiceBend.ratio(100)));yes(s.commands().get(3).equals("SONG_CHORD,2,0,250"));
        yes(s.commands().get(4).endsWith(",16384"));yes(s.commands().get(6).equals("SONG_CHORD,5,2,20"));
        ScoreBends copy=ScoreBends.parse("copy.csv",s.csv());yes(copy.commands().equals(s.commands()));
        s.checkRange(8192,32768);checks++;bad(()->s.checkRange(16384,32768));
        ScoreBends.checkCapability("SONGBEND,1");checks++;bad(()->ScoreBends.checkCapability("SONGBEND,0"));
        for(String line:new String[]{"60,500,1201","60,500,-1201","REST,500,0","60+64,500,100|200","60,500,1,2","60,0,100"})bad(()->parse(ScoreBends.HEADER+"\n"+line));
        StringBuilder dense=new StringBuilder(ScoreBends.HEADER+"\n");for(int n=0;n<128;n++)dense.append("60,60000,").append(n%2==0?-1200:1200).append('\n');
        ScoreBends full=parse(dense.toString());yes(full.song.events.size()==128&&full.song.durationMs()==7680000);yes(parse(new String(full.csv(),StandardCharsets.UTF_8)).commands().equals(full.commands()));
        bad(()->parse(dense+"60,1,0\n"));
        for(int cents=-1200;cents<=1200;cents++){
            ScoreBends one=parse(ScoreBends.HEADER+"\n60,1,"+cents);yes(one.commands().get(1).equals("SONG_CHORD,0,1,1,"+VoiceBend.ratio(cents)));
            yes(parse(new String(one.csv(),StandardCharsets.UTF_8)).target(0)==cents);
        }
        yes(ScoreBends.plain(SongCodec.twinkle()).commands().equals(SongCodec.twinkle().commands()));
        System.out.println("PASS bend target CSV, all2401 cents, explicit zero/null, chord rejection, old commands, 128x60000ms and export roundtrip: "+checks+" checks");
    }
}
