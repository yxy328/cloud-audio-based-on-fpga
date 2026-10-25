package cn.fpga.score;

/** Same 33 RGB5 hue anchors as the panel; App inputs use their own amplitude scale. */
public final class LedHue {
    private LedHue() { }
    public static final int SILENT=0xff424d60;
    public static int rgb5(int peak64){
        int q=Math.max(0,Math.min(32,peak64))*6;
        int d=((q&63)*7)>>4;
        if(q>=192)return (31<<10)|(3<<5)|3;
        if(q<64)return (3<<10)|((31-d)<<5)|31;
        if(q<128)return ((3+d)<<10)|(3<<5)|31;
        return (31<<10)|(3<<5)|(31-d);
    }
    public static int color(int step){
        int c=rgb5(step);
        return 0xff000000|((((c>>10)&31)*255+15)/31<<16)
            |((((c>>5)&31)*255+15)/31<<8)|((c&31)*255+15)/31;
    }
    public static int[] colors(){
        int[] result=new int[33];
        for(int p=0;p<result.length;p++)result[p]=color(p);
        return result;
    }
    public static int amplitudeColor(int value,int fullScale){
        if(value<=0 || fullScale<=0)return SILENT;
        int bounded=Math.min(value,fullScale);
        return color((bounded*32+fullScale/2)/fullScale);
    }
}
