package cn.fpga.score;

/** Editable draft, with time in ms and sustain in percent. */
public final class AdsrProfile {
    public final int attack,decay,sustain,release;
    public AdsrProfile(int a,int d,int s,int r){
        if(a<0||a>1000||d<0||d>1000||s<0||s>100||r<0||r>1000)
            throw new IllegalArgumentException("A/D/R: 0-1000 ms; S: 0-100%");
        attack=a;decay=d;sustain=s;release=r;
    }
    public String command(String target){
        if(!target.equals("TOUCH")&&!target.equals("SENSOR"))throw new IllegalArgumentException("Unknown ADSR target");
        return "ADSR,"+target+","+attack+","+decay+","+sustain+","+release;
    }
    public float[][] points(int hold){
        if(hold<0)throw new IllegalArgumentException("Negative hold");
        return new float[][]{{0,0},{attack,1},{attack+decay,sustain/100f},
            {attack+decay+hold,sustain/100f},{attack+decay+hold+release,0}};
    }
    private static int clamp(float value,int max){return Math.max(0,Math.min(max,Math.round(value)));}
    public AdsrProfile drag(int handle,float time,float level,int hold){
        if(handle<0||handle>3||hold<0||Float.isNaN(time)||Float.isInfinite(time)||Float.isNaN(level)||Float.isInfinite(level))
            throw new IllegalArgumentException("Invalid envelope handle");
        return new AdsrProfile(handle==0?clamp(time,1000):attack,
            handle==1?clamp(time-attack,1000):decay,
            handle==1||handle==2?clamp(level,100):sustain,
            handle==3?clamp(time-attack-decay-hold,1000):release);
    }
}
