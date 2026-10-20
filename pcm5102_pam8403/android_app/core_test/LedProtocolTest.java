package cn.fpga.score;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

public final class LedProtocolTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("check "+checks);}
    private interface Attempt{void run()throws Exception;}
    private static void rejects(Attempt a)throws Exception{checks++;try{a.run();}catch(IOException expected){return;}throw new AssertionError("Invalid protocol accepted");}
    private static void checkLive(String line)throws Exception{
        LedFrame f=LedFrame.parse(line);
        yes(f.mode==3 && f.ratio==2 && f.phase==1 && f.flags==7);
        yes(f.touch==56 && f.sensor==17 && f.guitar==0 && f.spectrumValid());
        for(int i=0;i<16;i++)yes(f.level(i)==i*2);
    }
    public static void main(String[] args)throws Exception{
        checkLive("V,17E78440F7358B52507314831040");
        LedFrame silent=LedFrame.parse("V,1000000000000000000000000000");
        yes(!silent.spectrumValid() && silent.flags==0 && silent.touch==0);
        for(int i=0;i<16;i++)yes(silent.level(i)==0);
        for(int m=0;m<4;m++)for(int r=0;r<4;r++)for(int p=0;p<4;p++){
            LedState s=LedState.parse("VIS,"+m+",3,"+r+","+p+",1,2,7");
            yes(s.requestedMode==m && s.activeMode==3 && s.ratio==r && s.phase==p);
            yes(s.shownRatio==1 && s.shownPhase==2 && s.flags==7 && !s.description().isEmpty());
        }
        for(String bad:new String[]{"","VIS,0,0,0,0,0,0","VIS,0,0,0,0,0,0,8","VIS,4,0,0,0,0,0,0","VIS,00,0,0,0,0,0,0","VIS,0,0,0,0,0,0,-1","VIS,0,0,0,0,0,0,1,","VIS,0,0,0,0,0,0, 1"})rejects(()->LedState.parse(bad));
        for(String bad:new String[]{"","V,0","V,2000000000000000000000000000","V,1800000000000000000000000000","V,1003F00000000000000000000000","V,17e78440F7358B52507314831040","X,1000000000000000000000000000","V,1000000000000000000000000000\n","V,100000000000000000000000000Z"})rejects(()->LedFrame.parse(bad));
        if(args.length>0){
            List<String> lines=Files.readAllLines(Paths.get(args[0]),StandardCharsets.US_ASCII);
            yes(lines.size()==3);
            LedState state=LedState.parse(lines.get(0));yes(state.requestedMode==3 && state.activeMode==3 && state.ratio==2 && state.phase==0 && state.shownPhase==1);
            checkLive(lines.get(1));LedFrame empty=LedFrame.parse(lines.get(2));yes(!empty.spectrumValid() && empty.touch==0);
            System.out.println("PASS RTL UART -> Java LED state/spectrum: atomic live and reset snapshots");
        }
        if(args.length>1){
            List<String> lines=Files.readAllLines(Paths.get(args[1]),StandardCharsets.US_ASCII);
            yes(lines.size()==1);LedFrame f=LedFrame.parse(lines.get(0));
            yes(f.mode==3 && f.spectrumValid() && f.level(4)>0);
            System.out.println("PASS top live C4 -> UART -> Java spectrum: frequency band and frame metadata");
        }
        System.out.println("PASS LedProtocol: "+checks+" checks");
    }
}
