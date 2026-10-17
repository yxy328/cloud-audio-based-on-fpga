package cn.fpga.score;

public final class VoiceBendTest {
    private static int checks;
    private static void yes(boolean b){checks++;if(!b)throw new AssertionError("check "+checks);}
    public static void main(String[] args){
        yes(VoiceBend.ratio(-1200)==8192);yes(VoiceBend.ratio(0)==16384);yes(VoiceBend.ratio(1200)==32768);
        int last=0;
        for(int c=-1200;c<=1200;c++){
            int r=VoiceBend.ratio(c);yes(r>last);last=r;
            double actual=1200*Math.log(r/16384.0)/Math.log(2);yes(Math.abs(actual-c)<0.11);
            yes(VoiceBend.command(7,c).equals("BEND,7,"+r));
        }
        for(int c:new int[]{-1201,1201}){try{VoiceBend.ratio(c);throw new AssertionError();}catch(IllegalArgumentException expected){checks++;}}
        for(int key:new int[]{0,8}){try{VoiceBend.command(key,0);throw new AssertionError();}catch(IllegalArgumentException expected){checks++;}}
        VoiceBend q=new VoiceBend();yes(q.take()==-1);
        // Offline edits are drafts, never sent automatically on reconnection.
        q.edit(3,100,false);yes(!q.hasPending());yes(q.value(3)==100);
        // Hundreds of drag events coalesce to one latest position.
        for(int c=0;c<=600;c++)q.edit(0,c,true);
        yes(q.take()==0);yes(q.value(0)==600);yes(q.take()==-1);
        // An in-flight ACK must not erase a newer edit; keys are serviced fairly.
        q.edit(0,700,true);q.edit(6,-500,true);yes(q.take()==6);yes(q.take()==0);
        q.edit(0,800,true);yes(q.hasPending());yes(q.take()==0);yes(q.value(0)==800);
        int[] snapshot=q.snapshot();q.edit(0,900,true);yes(snapshot[0]==800);
        q.clearPending();yes(q.take()==-1);yes(q.value(0)==900);
        // Drags made during a seven-key batch survive its immutable snapshot.
        for(int i=0;i<7;i++)q.edit(i,i*100,true);
        snapshot=q.snapshot();q.clearPending();q.edit(2,-300,true);
        yes(snapshot[2]==200);yes(q.take()==2);yes(q.value(2)==-300);yes(!q.hasPending());
        yes(VoiceBend.label(-50).contains("-0.50"));
        System.out.println("PASS VoiceBend: "+checks+" assertions; all cents, protocol, pitch error, coalescing/fairness/offline/last edit/batch isolation");
    }
}
