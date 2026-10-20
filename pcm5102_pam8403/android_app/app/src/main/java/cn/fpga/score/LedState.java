package cn.fpga.score;

import java.io.IOException;

/** VIS? distinguishes requested settings from frame-latched display state. */
public final class LedState {
    public final int requestedMode,activeMode,ratio,phase,shownRatio,shownPhase,flags;
    private LedState(int[] v){requestedMode=v[0];activeMode=v[1];ratio=v[2];phase=v[3];shownRatio=v[4];shownPhase=v[5];flags=v[6];}
    public static LedState parse(String line)throws IOException{
        String[] p=line.split(",",-1);
        if(p.length!=8 || !p[0].equals("VIS"))throw new IOException("显示状态格式错误");
        int[] v=new int[7];
        for(int i=0;i<7;i++){
            if(p[i+1].length()!=1 || p[i+1].charAt(0)<'0' || p[i+1].charAt(0)>(i==6?'7':'3'))throw new IOException("显示状态超出范围");
            v[i]=p[i+1].charAt(0)-'0';
        }
        return new LedState(v);
    }
    public static String page(int mode,boolean dashboard){
        switch(mode){case 0:return dashboard?"状态总览":"曲谱指引";case 1:return "波形";case 2:return "XY";case 3:return "频谱";default:throw new IllegalArgumentException("显示页超出范围");}
    }
    public static String xy(int ratio,int phase){return ratio==0?"AUD 实际混音":"REF "+(ratio==1?"1:1":ratio==2?"1:2":"2:3")+" / "+(phase*45)+"°";}
    public String description(){
        String requested=requestedMode==0?"总览/曲谱":page(requestedMode,false);
        return "请求页："+requested+"；实际页："+page(activeMode,(flags&4)!=0)+
            "\nXY 请求："+xy(ratio,phase)+"；已发布："+((flags&2)==0?"等待首帧":xy(shownRatio,shownPhase));
    }
}
