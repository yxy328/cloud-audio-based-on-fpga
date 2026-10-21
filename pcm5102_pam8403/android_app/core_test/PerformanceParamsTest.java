package cn.fpga.score;

public final class PerformanceParamsTest {
    private static int checks;
    private static void yes(boolean valid){checks++;if(!valid)throw new AssertionError("演奏参数检查 "+checks);}
    private static void invalid(Runnable action){try{action.run();throw new AssertionError("应拒绝非法输入");}catch(IllegalArgumentException e){yes(e.getMessage()!=null&&!e.getMessage().isEmpty());}}
    public static void main(String[] args){
        yes(PerformanceParams.bendRatio(-1200)==8192);yes(PerformanceParams.bendRatio(1200)==32768);
        for(int cents=-1200;cents<=1200;cents++)yes(Math.abs(PerformanceParams.bendCents(PerformanceParams.bendRatio(cents))-cents)<0.11);
        for(int range:new int[]{50,200,1200})for(int ms:new int[]{5,60,200,500}){
            int step=PerformanceParams.glideStep(range,ms);double actual=PerformanceParams.glideMilliseconds(range,step);
            yes(step>=1&&step<=65535);yes(Math.abs(actual/ms-1)<0.11);
            if(actual>=5&&actual<=500)yes(PerformanceParams.glideStep(range,actual)==step);
        }
        for(int range:new int[]{50,200,1200})for(int cents=-1200;cents<=1200;cents+=17){
            int clamped=PerformanceParams.clampBend(cents,PerformanceParams.rangeLower(range),PerformanceParams.rangeUpper(range));
            yes(clamped==Math.max(-range,Math.min(range,cents)));
            yes(PerformanceParams.bendAllowed(clamped,PerformanceParams.rangeLower(range),PerformanceParams.rangeUpper(range)));
        }
        invalid(()->PerformanceParams.clampBend(0,8191,32768));invalid(()->PerformanceParams.bendAllowed(0,8192,32769));
        yes(PerformanceParams.DEFAULT_SLEW==4096);yes(Math.abs(PerformanceParams.glideMilliseconds(1200,4096)-20.97152)<0.00001);
        for(int rate=30;rate<=80;rate++){int inc=PerformanceParams.vibratoIncrement(rate/10.0);yes(Math.abs(PerformanceParams.vibratoHz(inc)-rate/10.0)<0.000006);}
        yes(PerformanceParams.vibratoIncrement(6)==527766);
        for(int cents=5;cents<=100;cents++)yes(Math.round(PerformanceParams.depthCents(PerformanceParams.depthValue(cents)))==cents);
        yes(PerformanceParams.depthValue(27)==256);yes(PerformanceParams.depthValue(100)==948);
        for(int ms=0;ms<=800;ms++)yes(Math.round(PerformanceParams.delayMilliseconds(PerformanceParams.delayFrames(ms)))==ms);
        yes(PerformanceParams.delayFrames(800)==39063);
        yes(PerformanceParams.values(PerformanceParams.parsePitch("PITCH,2000,8000,1000,4000")).equals("8192,32768,4096,16384"));
        yes(PerformanceParams.values(PerformanceParams.parseVibrato("VIB,0008,0D96,100,0000")).equals("8,3478,256,0"));
        yes(PerformanceParams.vibratoValues(6,27,0).equals("8,3478,256,0"));
        java.util.Set<Integer> ratios=new java.util.HashSet<>();
        for(int semitone=-12;semitone<=12;semitone++)for(int a4:new int[]{415,432,440,442,466}){
            int ratio=PerformanceParams.tuningRatio(semitone,a4);int[] back=PerformanceParams.tuningParameters(ratio);
            yes(back[0]==semitone&&back[1]==a4);yes(ratios.add(ratio));
            double ideal=Math.pow(2,semitone/12.0)*a4/440;
            yes(Math.abs(1200*Math.log(ratio/(16384*ideal))/Math.log(2))<0.12);
            for(int analog=0;analog<=4;analog++)yes(PerformanceParams.tuningAllowed(analog,ratio)==(analog!=2||ratio==16384));
        }
        yes(PerformanceParams.tuningRatio(-12,415)==7727);yes(PerformanceParams.tuningRatio(12,466)==34704);yes(PerformanceParams.tuningRatio(3,442)==19573);
        invalid(()->PerformanceParams.tuningRatio(-13,440));invalid(()->PerformanceParams.tuningRatio(13,440));invalid(()->PerformanceParams.tuningRatio(0,441));
        invalid(()->PerformanceParams.tuningParameters(7726));invalid(()->PerformanceParams.tuningParameters(34705));invalid(()->PerformanceParams.tuningAllowed(5,16384));
        yes(PerformanceParams.timeLabel(60,125).contains("0.125 拍"));
        invalid(()->PerformanceParams.bendRatio(-1201));invalid(()->PerformanceParams.bendRatio(1201));invalid(()->PerformanceParams.bendCents(8191));invalid(()->PerformanceParams.bendCents(32769));
        invalid(()->PerformanceParams.rangeLower(49));invalid(()->PerformanceParams.rangeUpper(1201));
        for(double ms:new double[]{4,501,Double.NaN,Double.POSITIVE_INFINITY})invalid(()->PerformanceParams.glideStep(200,ms));
        invalid(()->PerformanceParams.glideMilliseconds(200,0));invalid(()->PerformanceParams.glideMilliseconds(200,65536));
        for(double hz:new double[]{2.9,8.1,Double.NaN,Double.NEGATIVE_INFINITY})invalid(()->PerformanceParams.vibratoIncrement(hz));
        invalid(()->PerformanceParams.vibratoHz(263882));invalid(()->PerformanceParams.vibratoHz(703688));
        invalid(()->PerformanceParams.depthValue(4));invalid(()->PerformanceParams.depthValue(101));invalid(()->PerformanceParams.depthCents(-1));invalid(()->PerformanceParams.depthCents(1024));
        invalid(()->PerformanceParams.delayFrames(-1));invalid(()->PerformanceParams.delayFrames(801));invalid(()->PerformanceParams.delayMilliseconds(39064));
        for(String text:new String[]{"PITCH,2000,8000,0000,4000","PITCH,1FFF,8000,1000,4000","PITCH,2000,8001,1000,4000","PITCH,2000,8000,1000,0","PITCH,2000,8000,1fff,4000",null})invalid(()->PerformanceParams.parsePitch(text));
        for(String text:new String[]{"VIB,0000,0000,100,0000","VIB,0008,0D96,400,0000","VIB,0008,0D96,100,9898","VIB,0008,0D96,100"})invalid(()->PerformanceParams.parseVibrato(text));
        invalid(()->PerformanceParams.timeLabel(-1,125));invalid(()->PerformanceParams.timeLabel(60,0));
        yes(PerformanceParams.values(PerformanceParams.parseEcho("EFFECT2,3")).equals("3"));
        for(int tap=0;tap<4;tap++)for(int division=0;division<3;division++){
            double bpm=PerformanceParams.echoBpm(tap,division);
            yes(Math.abs(60000/bpm*new double[]{0.25,0.375,0.5}[division]-PerformanceParams.echoMilliseconds(tap))<0.000001);
        }
        for(int bpm=20;bpm<=300;bpm++)for(int division=0;division<3;division++){
            int nearest=PerformanceParams.echoTap(bpm,division);double target=PerformanceParams.echoTargetMilliseconds(bpm,division);
            for(int tap=0;tap<4;tap++)yes(Math.abs(PerformanceParams.echoMilliseconds(nearest)-target)<=Math.abs(PerformanceParams.echoMilliseconds(tap)-target));
        }
        invalid(()->PerformanceParams.echoMilliseconds(-1));invalid(()->PerformanceParams.echoMilliseconds(4));
        invalid(()->PerformanceParams.echoTap(19,0));invalid(()->PerformanceParams.echoTap(301,0));invalid(()->PerformanceParams.echoTap(125,3));
        for(String text:new String[]{"EFFECT2,4","EFFECT2,-1","EFFECT2,03","EFFECT2,0,0100","effect2,0",null})invalid(()->PerformanceParams.parseEcho(text));
        System.out.println("PASS PerformanceParams: "+checks+" checks; unit conversions, quantized round trips, firmware bounds, query parsing, Chinese errors");
    }
}
