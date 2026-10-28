package cn.fpga.score;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
public final class RhythmStateTest {
    private static void check(boolean ok){if(!ok)throw new AssertionError();}
    private static void rejects(String line)throws Exception{
        try{RhythmState.parse(line);throw new AssertionError("accepted "+line);}catch(java.io.IOException expected){}
    }
    public static void main(String[] args)throws Exception{
        for(int d=0;d<4;d++)for(int t=0;t<3;t++)for(int flags=0;flags<8;flags++){
            int config=RhythmState.settings(d,t,(flags&1)!=0,(flags&2)!=0,(flags&4)!=0);
            check((config&128)!=0 && ((config>>2)&3)==d && (config&3)==t);
            check(((config&64)!=0)==((flags&1)!=0));check(((config&32)!=0)==((flags&2)!=0));check(((config&16)!=0)==((flags&4)!=0));
        }
        String line=args.length==0 ? "V,2E4F100100000100100000000000" : new String(Files.readAllBytes(Paths.get(args[0])),StandardCharsets.US_ASCII).trim().toUpperCase(Locale.ROOT);
        RhythmState s=RhythmState.parse(line);
        check(s.settings==228&&s.session&&s.playing&&s.holding);
        check(s.score==1000&&s.combo==1&&s.best==1&&s.miss==0&&s.judgement==1);
        check(s.description().contains("1000")&&RhythmState.isGame(line));
        rejects("V,1000000000000000000000000000");rejects(line+"0");rejects(line.replace('V','X'));
        rejects(line.substring(0,13)+"A"+line.substring(14));
        if(args.length>1){
            RhythmState top=RhythmState.parse(new String(Files.readAllBytes(Paths.get(args[1])),StandardCharsets.US_ASCII).trim());
            check(top.score==2500&&top.combo==2&&top.best==2&&top.miss==0&&top.session&&!top.playing&&!top.holding);
        }
        System.out.println("PASS RhythmState: 96 settings combinations, actual RTL score snapshot, strict format/version/BCD");
    }
}
