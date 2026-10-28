package cn.fpga.score;
import java.io.IOException;
import java.math.BigInteger;

/** FPGA-clocked game results, carried in the version-two VIZ snapshot. */
public final class RhythmState {
    public final int settings,score,combo,best,miss,judgement;
    public final boolean session,playing,holding;
    private static int bits(BigInteger n,int shift,int mask){return n.shiftRight(shift).intValue()&mask;}
    private static int bcd(int n,int digits)throws IOException{
        int result=0,mul=1;
        for(int i=0;i<digits;i++){int d=n&15;if(d>9)throw new IOException("计分数据含非法数字");result+=mul*d;mul*=10;n>>>=4;}
        return result;
    }
    private RhythmState(BigInteger n)throws IOException{
        if(bits(n,108,15)!=2)throw new IOException("请使用配套音游固件并切到曲谱页");
        settings=bits(n,100,255);int flags=bits(n,96,15);
        session=(flags&8)!=0;playing=(flags&4)!=0;holding=(flags&2)!=0;
        judgement=bits(n,92,15);if(judgement>3)throw new IOException("判定数据错误");
        score=bcd(bits(n,68,0xffffff),6);combo=bcd(bits(n,56,4095),3);
        best=bcd(bits(n,44,4095),3);miss=bcd(bits(n,32,4095),3);
        if(bits(n,0,0xffffff)!=0)throw new IOException("计分保留字段错误");
    }
    public static boolean isGame(String line){return line!=null&&line.startsWith("V,2");}
    public static RhythmState parse(String line)throws IOException{
        if(line==null||!line.matches("V,[0-9A-F]{28}"))throw new IOException("计分数据格式错误");
        return new RhythmState(new BigInteger(line.substring(2),16));
    }
    public static int settings(int difficulty,int theme,boolean longNotes,boolean effects,boolean wide){
        if(difficulty<0||difficulty>3||theme<0||theme>2)throw new IllegalArgumentException("音游设置超出范围");
        return 128|(longNotes?64:0)|(effects?32:0)|(wide?16:0)|(difficulty<<2)|theme;
    }
    public String description(){return (!session?"等待开始":playing?(holding?"长按保持中":"演奏中"):"本次结果")+
        "\n得分 "+score+"　连击 "+combo+"　最高连击 "+best+"　Miss "+miss+
        "\n最近判定："+new String[]{"—","Perfect","Good","Miss"}[judgement];}
}
