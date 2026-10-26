package cn.fpga.score;

import java.util.Locale;

/** Confirmed configuration and actually applied (slider/replay) effect state. */
public final class FxState {
    public final int mask,settings,mix,appliedMask,appliedSettings,appliedMix;
    private FxState(int m,int s,int w,int am,int as,int aw){
        validate(m,s,w);validate(am,as,aw);
        mask=m;settings=s;mix=w;appliedMask=am;appliedSettings=as;appliedMix=aw;
    }
    private static void check(boolean ok){if(!ok)throw new IllegalArgumentException("三效果状态或参数无效");}
    private static void validate(int m,int s,int w){
        check(m>=0&&m<=7&&s>=0&&s<=255&&w>=0&&w<=4095);
        for(int b=0;b<3;b++)check(((w>>(b*4))&15)<=8);
    }
    public static FxState parse(String text){
        check(text!=null);String[] p=text.split(",",-1);check(p.length==7&&p[0].equals("EFFECT3"));
        int[] widths={1,2,3,1,2,3},v=new int[6];
        for(int i=0;i<v.length;i++){
            check(p[i+1].matches("[0-9A-F]{"+widths[i]+"}"));v[i]=Integer.parseInt(p[i+1],16);
        }
        return new FxState(v[0],v[1],v[2],v[3],v[4],v[5]);
    }
    public boolean enabled(int block,boolean actual){block(block);return (((actual?appliedMask:mask)>>block)&1)!=0;}
    public int wet(int block,boolean actual){block(block);return ((actual?appliedMix:mix)>>(4*block))&15;}
    public int preset(int block,boolean actual){
        block(block);int s=actual?appliedSettings:settings;return block==0?s&3:block==1?(s>>2)&3:(s>>6)&3;
    }
    public int feedback(boolean actual){return ((actual?appliedSettings:settings)>>4)&3;}
    private static void block(int b){check(b>=0&&b<3);}
    public FxState withBlock(int b,boolean enable,int preset,int feedback,int wet){
        block(b);check(preset>=0&&preset<4&&feedback>=0&&feedback<4&&wet>=0&&wet<=8);
        int m=enable?mask|(1<<b):mask&~(1<<b),s=settings;
        if(b==0)s=(s&~3)|preset;
        else if(b==1)s=(s&~60)|(preset<<2)|(feedback<<4);
        else s=(s&~192)|(preset<<6);
        int w=(mix&~(15<<(b*4)))|(wet<<(b*4));
        return new FxState(m,s,w,appliedMask,appliedSettings,appliedMix);
    }
    public String command(){return "EFFECT,3,"+mask+","+settings+","+mix;}
    public String blockValue(int b){return (enabled(b,false)?1:0)+","+preset(b,false)+","+(b==1?feedback(false):0)+","+wet(b,false);}
    public String describe(int b,boolean actual){
        String p=b==0?new String[]{"32","64","128","256"}[preset(b,actual)]+" 采样深度":
            b==1?String.format(Locale.ROOT,"%.2f ms / 反馈 %.1f%%",PerformanceParams.echoMilliseconds(preset(b,actual)),new double[]{25,50,62.5,75}[feedback(actual)]):
            "尾音约 "+new String[]{"0.40","0.66","0.91","1.40"}[preset(b,actual)]+" s";
        return (enabled(b,actual)?"开启":"旁路")+" · "+p+String.format(Locale.ROOT," · 湿声 %.2f%%",wet(b,actual)*6.25);
    }
    public String summary(){return "实际三效果：合唱"+(enabled(0,true)?"开":"关")+" → 延迟"+(enabled(1,true)?"开":"关")+" → 混响"+(enabled(2,true)?"开":"关");}
}
