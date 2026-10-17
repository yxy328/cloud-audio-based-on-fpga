package cn.fpga.score;

public final class AdsrProfileTest {
    private static int checks;
    private static void yes(boolean x){checks++;if(!x)throw new AssertionError("ADSR check "+checks);}
    private static void invalid(int a,int d,int s,int r){try{new AdsrProfile(a,d,s,r);}catch(IllegalArgumentException e){checks++;return;}throw new AssertionError("Accepted invalid profile");}
    public static void main(String[] args){
        AdsrProfile p=new AdsrProfile(10,80,60,200);
        yes(p.command("TOUCH").equals("ADSR,TOUCH,10,80,60,200"));
        yes(p.command("SENSOR").equals("ADSR,SENSOR,10,80,60,200"));
        float[][] points=p.points(300);
        yes(points.length==5);yes(points[1][0]==10&&points[1][1]==1);
        yes(points[2][0]==90&&points[2][1]==0.6f);yes(points[3][0]==390&&points[3][1]==0.6f);
        yes(points[4][0]==590&&points[4][1]==0);
        for(int i=0;i<=1000;i++){
            AdsrProfile v=new AdsrProfile(i,1000-i,i%101,i);
            float[][] q=v.points(300);for(int n=1;n<q.length;n++)yes(q[n][0]>=q[n-1][0]);
            yes(v.command("TOUCH").length()<64);
        }
        invalid(-1,0,0,0);invalid(1001,0,0,0);invalid(0,1001,0,0);invalid(0,0,-1,0);
        invalid(0,0,101,0);invalid(0,0,0,1001);invalid(0,0,0,-1);
        try{p.command("OTHER");throw new AssertionError();}catch(IllegalArgumentException e){checks++;}
        try{p.points(-1);throw new AssertionError();}catch(IllegalArgumentException e){checks++;}
        yes(new AdsrProfile(0,0,0,0).points(300)[4][0]==300);
        AdsrProfile dragged=p.drag(0,50,20,300);yes(dragged.attack==50&&dragged.decay==80&&dragged.sustain==60&&dragged.release==200);
        dragged=p.drag(1,200,25,300);yes(dragged.attack==10&&dragged.decay==190&&dragged.sustain==25&&dragged.release==200);
        dragged=p.drag(2,0,80,300);yes(dragged.attack==10&&dragged.decay==80&&dragged.sustain==80&&dragged.release==200);
        dragged=p.drag(3,690,0,300);yes(dragged.attack==10&&dragged.decay==80&&dragged.sustain==60&&dragged.release==300);
        yes(p.drag(0,-10,0,300).attack==0);yes(p.drag(0,2000,0,300).attack==1000);
        yes(p.drag(1,-10,-50,300).decay==0);yes(p.drag(2,0,150,300).sustain==100);
        yes(p.drag(3,0,0,300).release==0);yes(p.drag(3,5000,0,300).release==1000);
        System.out.println("PASS AdsrProfile: "+checks+" assertions");
    }
}
