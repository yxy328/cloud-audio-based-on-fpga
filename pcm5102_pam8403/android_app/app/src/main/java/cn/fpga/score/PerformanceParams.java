package cn.fpga.score;

import java.util.Locale;

public final class PerformanceParams {
    public static final double SAMPLE_RATE=50000000.0/1024;
    public static final int DEFAULT_SLEW=4096,DEFAULT_VIBRATO_INC=527766,DEFAULT_DEPTH=256;
    private PerformanceParams(){}
    private static void check(boolean valid,String message){if(!valid)throw new IllegalArgumentException(message);}
    public static int bendRatio(int cents){
        check(cents>=-1200&&cents<=1200,"弯音范围为 −1200～+1200 音分");
        return (int)Math.round(16384*Math.pow(2,cents/1200.0));
    }
    public static double bendCents(int ratio){
        check(ratio>=8192&&ratio<=32768,"弯音倍率必须为 8192～32768（Q2.14）");
        return 1200*Math.log(ratio/16384.0)/Math.log(2);
    }
    public static int rangeLower(int cents){range(cents);return bendRatio(-cents);}
    public static int rangeUpper(int cents){range(cents);return bendRatio(cents);}
    public static boolean bendAllowed(int cents,int lower,int upper){
        check(lower>=8192&&lower<=15918&&upper>=16864&&upper<=32768,"设备弯音上下界超出范围");
        int ratio=bendRatio(cents);return ratio>=lower&&ratio<=upper;
    }
    public static int clampBend(int cents,int lower,int upper){
        bendAllowed(cents,lower,upper);
        while(!bendAllowed(cents,lower,upper))cents+=bendRatio(cents)<lower?1:-1;
        return cents;
    }
    private static void range(int cents){check(cents>=50&&cents<=1200,"弯音幅度为 ±50～±1200 音分");}
    public static int glideStep(int rangeCents,double milliseconds){
        range(rangeCents);check(Double.isFinite(milliseconds)&&milliseconds>=5&&milliseconds<=500,"滑音时间为 5～500 ms");
        int step=(int)Math.round((rangeUpper(rangeCents)-16384)*256/(milliseconds*SAMPLE_RATE/1000));
        check(step>=1&&step<=65535,"滑音步进超出固件范围");return step;
    }
    public static double glideMilliseconds(int rangeCents,int step){
        range(rangeCents);check(step>=1&&step<=65535,"滑音步进必须为 1～65535（Q8.8）");
        return (rangeUpper(rangeCents)-16384)*256000.0/(step*SAMPLE_RATE);
    }
    public static int vibratoIncrement(double hz){
        check(Double.isFinite(hz)&&hz>=3&&hz<=8,"颤音速率为 3.0～8.0 Hz");
        return (int)Math.round(hz*4294967296.0/SAMPLE_RATE);
    }
    public static double vibratoHz(int increment){
        check(increment>=263883&&increment<=703687,"颤音相位增量必须为 263883～703687");
        return increment*SAMPLE_RATE/4294967296.0;
    }
    public static int depthValue(int cents){
        check(cents>=5&&cents<=100,"颤音深度为 ±5～±100 音分");return (int)Math.round(cents*256.0/27);
    }
    public static double depthCents(int depth){
        check(depth>=0&&depth<=1023,"颤音深度寄存器必须为 0～1023");return depth*27.0/256;
    }
    public static int delayFrames(int milliseconds){
        check(milliseconds>=0&&milliseconds<=800,"起振延迟为 0～800 ms");return (int)Math.round(milliseconds*SAMPLE_RATE/1000);
    }
    public static double delayMilliseconds(int frames){
        check(frames>=0&&frames<=39063,"起振延迟采样数必须为 0～39063");return frames*1000/SAMPLE_RATE;
    }
    public static int tuningRatio(int semitones,int a4){
        check(semitones>=-12&&semitones<=12,"移调范围为 −12～+12 半音");
        check(a4==415||a4==432||a4==440||a4==442||a4==466,"A4 标准音为 415 / 432 / 440 / 442 / 466 Hz");
        return (int)Math.round(16384*Math.pow(2,semitones/12.0)*a4/440);
    }
    public static int[] tuningParameters(int ratio){
        check(ratio>=7727&&ratio<=34704,"基准倍率必须为 7727～34704（Q2.14）");
        for(int semitone=-12;semitone<=12;semitone++)for(int a4:new int[]{415,432,440,442,466})
            if(tuningRatio(semitone,a4)==ratio)return new int[]{semitone,a4};
        return null;
    }
    public static boolean tuningAllowed(int analog,int ratio){
        check(analog>=0&&analog<=4,"模拟输入用途必须为 0～4");tuningParameters(ratio);return analog!=2||ratio==16384;
    }
    public static String tuningLabel(int ratio){
        int[] parameters=tuningParameters(ratio);
        return parameters==null?String.format(Locale.ROOT,"自定义基准倍率 %.6f",ratio/16384.0):
            String.format(Locale.ROOT,"移调 %+d 半音（%+d 音分），A4=%d Hz",parameters[0],parameters[0]*100,parameters[1]);
    }
    public static String pitchValues(int range,int step,int tuning){
        glideMilliseconds(range,step);tuningParameters(tuning);return rangeLower(range)+","+rangeUpper(range)+","+step+","+tuning;
    }
    public static String vibratoValues(double hz,int cents,int milliseconds){
        int inc=vibratoIncrement(hz);return (inc>>>16)+","+(inc&65535)+","+depthValue(cents)+","+delayFrames(milliseconds);
    }
    public static int[] parsePitch(String text){
        int[] v=parse(text,"PITCH",new int[]{4,4,4,4});
        check(v[0]>=8192&&v[0]<=15918&&v[1]>=16864&&v[1]<=32768&&v[2]>=1,"设备弯音 / 滑音回报超出合法范围");tuningParameters(v[3]);return v;
    }
    public static int[] parseVibrato(String text){
        int[] v=parse(text,"VIB",new int[]{4,4,3,4});
        vibratoHz((v[0]<<16)|v[1]);depthCents(v[2]);delayMilliseconds(v[3]);return v;
    }
    public static double echoMilliseconds(int tap){
        check(tap>=0&&tap<=3,"回声档位必须为 0～3");return 4096000.0*new int[]{1,2,4,6}[tap]/SAMPLE_RATE;
    }
    private static double beatFraction(int division){
        check(division>=0&&division<=2,"节拍比例必须为 1/4、3/8 或 1/2 拍");return new double[]{0.25,0.375,0.5}[division];
    }
    public static double echoTargetMilliseconds(int bpm,int division){
        check(bpm>=20&&bpm<=300,"回声参考速度为 20～300 BPM");return 60000.0/bpm*beatFraction(division);
    }
    public static int echoTap(int bpm,int division){
        double target=echoTargetMilliseconds(bpm,division);int nearest=0;
        for(int tap=1;tap<4;tap++)if(Math.abs(echoMilliseconds(tap)-target)<Math.abs(echoMilliseconds(nearest)-target))nearest=tap;
        return nearest;
    }
    public static double echoBpm(int tap,int division){return 60000*beatFraction(division)/echoMilliseconds(tap);}
    public static int[] parseEcho(String text){
        int[] v=parse(text,"EFFECT2",new int[]{1});echoMilliseconds(v[0]);return v;
    }
    private static int[] parse(String text,String prefix,int[] widths){
        check(text!=null,"设备参数回报为空");String[] fields=text.split(",",-1);
        check(fields.length==widths.length+1&&fields[0].equals(prefix),"设备参数回报格式错误："+prefix);
        int[] values=new int[widths.length];
        for(int i=0;i<values.length;i++){
            check(fields[i+1].matches("[0-9A-F]{"+widths[i]+"}"),"设备参数必须为定长大写十六进制："+prefix);
            values[i]=Integer.parseInt(fields[i+1],16);
        }
        return values;
    }
    public static String values(int[] v){StringBuilder s=new StringBuilder();for(int n:v){if(s.length()>0)s.append(',');s.append(n);}return s.toString();}
    public static String timeLabel(double milliseconds,int bpm){
        check(Double.isFinite(milliseconds)&&milliseconds>=0,"时间必须为非负毫秒数");
        check(bpm>=20&&bpm<=300,"参考速度为 20～300 BPM");
        return String.format(Locale.ROOT,"%.2f ms（约 %.3f 拍 @%d BPM）",milliseconds,milliseconds*bpm/60000,bpm);
    }
}
