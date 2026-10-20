package cn.fpga.score;

import java.io.IOException;
import java.math.BigInteger;

/** VIZ? -> V,<28 uppercase hex>; exactly 32 UART bytes including CRLF. */
public final class LedFrame {
    public final int mode,ratio,phase,flags,touch,sensor,guitar;
    private final int[] levels;
    private LedFrame(BigInteger n)throws IOException{
        if(bits(n,108,15)!=1 || (bits(n,104,15)&8)!=0)throw new IOException("预览协议版本或标志错误");
        flags=bits(n,104,7);mode=bits(n,102,3);ratio=bits(n,100,3);phase=bits(n,98,3);
        touch=bits(n,92,63);sensor=bits(n,86,63);guitar=bits(n,80,63);
        if(touch>56 || sensor>56 || guitar>56)throw new IOException("预览幅度超出范围");
        levels=new int[16];for(int i=0;i<16;i++)levels[i]=bits(n,i*5,31);
    }
    private static int bits(BigInteger n,int shift,int mask){return n.shiftRight(shift).intValue()&mask;}
    public static LedFrame parse(String line)throws IOException{
        if(line.length()!=30 || !line.startsWith("V,") || !line.substring(2).matches("[0-9A-F]{28}"))throw new IOException("预览数据格式错误");
        return new LedFrame(new BigInteger(line.substring(2),16));
    }
    public boolean spectrumValid(){return (flags&1)!=0;}
    public int level(int band){return levels[band];}
    public String description(){return "实际页："+LedState.page(mode,(flags&4)!=0)+" · "+((flags&2)==0?"XY 等待首帧":LedState.xy(ratio,phase));}
}
