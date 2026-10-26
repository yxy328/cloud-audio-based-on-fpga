package cn.fpga.score;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;

public final class FxStateTest {
    static int checks;
    static void yes(boolean ok){checks++;if(!ok)throw new AssertionError("FX "+checks);}
    static void bad(String s){checks++;try{FxState.parse(s);}catch(IllegalArgumentException expected){return;}throw new AssertionError(s);}
    public static void main(String[] args)throws Exception{
        for(int mask=0;mask<8;mask++)for(int preset=0;preset<4;preset++)for(int wet=0;wet<=8;wet++){
            int s=preset*85,mix=wet*273;
            FxState f=FxState.parse(String.format("EFFECT3,%X,%02X,%03X,%X,%02X,%03X",mask,s,mix,mask,s,mix));
            yes(f.mask==mask&&f.settings==s&&f.mix==mix);
            for(int b=0;b<3;b++){
                yes(f.enabled(b,true)==((mask&(1<<b))!=0));yes(f.preset(b,true)==preset&&f.wet(b,true)==wet);
                FxState next=f.withBlock(b,!f.enabled(b,false),3-preset,3-preset,8-wet);
                yes(next.command().equals("EFFECT,3,"+next.mask+","+next.settings+","+next.mix));
                for(int other=0;other<3;other++)if(other!=b)yes(next.blockValue(other).equals(f.blockValue(other)));
                yes(next.appliedMask==f.appliedMask&&next.appliedMix==f.appliedMix);
            }
        }
        FxState replay=FxState.parse("EFFECT3,0,52,444,7,FF,888");yes(!replay.enabled(2,false)&&replay.enabled(2,true));
        yes(replay.wet(2,false)==4&&replay.wet(2,true)==8);yes(replay.summary().contains("混响开"));
        for(String s:new String[]{"EFFECT3,8,52,444,0,52,444","EFFECT3,0,52,449,0,52,444","EFFECT3,0,52,444,0,52,944",
            "EFFECT3,0,5a,444,0,52,444","EFFECT3,00,52,444,0,52,444","EFFECT3,0,52,444","EFFECT3,0,52,444,0,52,444,","EFFECT3,0,100,444,0,52,444"})bad(s);
        for(String path:args)for(String line:Files.readAllLines(Paths.get(path),StandardCharsets.US_ASCII))if(line.startsWith("EFFECT3,")){FxState.parse(line.trim());checks++;}
        System.out.println("PASS FX configuration/applied state, independent block updates and RTL replies: "+checks+" checks");
    }
}
