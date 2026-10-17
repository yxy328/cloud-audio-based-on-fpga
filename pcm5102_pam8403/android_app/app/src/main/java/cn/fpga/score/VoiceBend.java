package cn.fpga.score;

import java.util.Locale;

/** Ratios are unsigned Q2.14; the queue is owned by the UI thread. */
public final class VoiceBend {
    public static final int LIMIT=1200;
    private final int[] cents=new int[7];
    private final boolean[] pending=new boolean[7];
    private int next;
    public static int ratio(int cents){
        if(cents < -LIMIT || cents > LIMIT)throw new IllegalArgumentException("音高范围为 ±1200 音分");
        return (int)Math.round(16384.0*Math.pow(2.0,cents/1200.0));
    }
    public static String command(int key,int cents){
        if(key<1 || key>7)throw new IllegalArgumentException("声部为 1～7");
        return "BEND,"+key+","+ratio(cents);
    }
    public static String label(int cents){return String.format(Locale.ROOT,"%+.2f 半音（%+d 音分）",cents/100.0,cents);}
    public void edit(int index,int value,boolean online){ratio(value);cents[index]=value;pending[index]=online;}
    public int value(int index){return cents[index];}
    public int[] snapshot(){return cents.clone();}
    // Clear only the selected pending item. A later drag while its ACK is in
    // flight requeues that key, so the final position can never be lost.
    public int take(){
        for(int i=0;i<7;i++){int key=(next+i)%7;if(pending[key]){pending[key]=false;next=(key+1)%7;return key;}}
        return -1;
    }
    public boolean hasPending(){for(boolean p:pending)if(p)return true;return false;}
    public void clearPending(){for(int i=0;i<7;i++)pending[i]=false;}
}
