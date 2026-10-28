package cn.fpga.score;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
public final class RhythmTypesTest {
    static void check(boolean condition){if(!condition)throw new AssertionError();}
    static ScoreBends parse(String text)throws IOException{return ScoreBends.parse("typed.csv",text.getBytes(StandardCharsets.UTF_8));}
    public static void main(String[] args)throws Exception{
        String header="pitches,duration_ms,bend_target_cents,note_type\n";
        ScoreBends score=parse(header+"60,900,,TAP\n61,200,0,HOLD\n62+64,100,,DRAG\n65,300,100,FLICK\nREST,50,,\n");
        check(score.hasTypes()&&score.hasBends());
        for(int n=0;n<4;n++)check(score.type(n)==n+1);
        check(score.commands().get(1).equals("SONG_CHORD,0,8193,900"));
        check(score.commands().get(2).equals("SONG_CHORD,1,16386,200,16384"));
        check(score.commands().get(3).equals("SONG_CHORD,2,24596,100"));
        check(score.commands().equals(ScoreBends.parse("round.csv",score.csv()).commands()));
        ScoreBends simple=parse("pitches,duration_ms,note_type\n60,100,drag\n62,100,flick\nREST,20,AUTO\n");
        check(simple.hasTypes()&&!simple.hasBends());
        check(simple.commands().equals(ScoreBends.parse("round.csv",simple.csv()).commands()));
        for(String invalid:new String[]{"60,10,,FICK","REST,100,,TAP","60,10,,5","60,10,HOLD"}){
            try{parse(header+invalid+"\n");throw new AssertionError(invalid);}catch(IOException expected){}
        }
        check(!ScoreBends.plain(SongCodec.twinkle()).hasTypes());
        check(!parse("pitches,duration_ms,bend_target_cents\n60,500,0\n").hasTypes());
        System.out.println("PASS typed CSV: all four codes, independent durations, chord mask, optional bend, rest/rejection, legacy and export roundtrips");
    }
}
