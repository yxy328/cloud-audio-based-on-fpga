package cn.fpga.score;

import java.awt.Color;
import java.nio.file.Files;
import java.nio.file.Paths;

public final class LedHueTest {
    private static int checks;
    private static void yes(boolean condition){checks++;if(!condition)throw new AssertionError("Hue check "+checks);}
    public static void main(String[] args)throws Exception{
        int[][] anchors={{0,3,31,31},{2,3,26,31},{8,3,10,31},{16,17,3,31},{24,31,3,24},{32,31,3,3}};
        for(int[] a:anchors)yes(LedHue.rgb5(a[0])==((a[1]<<10)|(a[2]<<5)|a[3]));
        int previous=LedHue.rgb5(0);
        for(int p=0;p<64;p++){
            int c=LedHue.rgb5(p),r=c>>10,g=(c>>5)&31,b=c&31;
            yes(r>=(previous>>10)&&g<=((previous>>5)&31)&&b<=(previous&31));
            yes(Math.max(r,Math.max(g,b))==31 && Math.min(r,Math.min(g,b))==3);
            int hsv=Color.HSBtoRGB((180+Math.min(p,32)*5.625f)/360f,.903f,1);
            yes(Math.abs(r-Math.round(((hsv>>16)&255)*31f/255))<=1);
            yes(Math.abs(g-Math.round(((hsv>>8)&255)*31f/255))<=1);
            yes(Math.abs(b-Math.round((hsv&255)*31f/255))<=1);
            if(p>=32)yes(c==LedHue.rgb5(32));
            previous=c;
        }
        yes(LedHue.amplitudeColor(0,31)==LedHue.SILENT);
        yes(LedHue.amplitudeColor(0,56)==LedHue.SILENT);
        yes(LedHue.amplitudeColor(31,31)==LedHue.color(32));
        yes(LedHue.amplitudeColor(56,56)==LedHue.color(32));
        yes(LedHue.amplitudeColor(100,56)==LedHue.color(32));
        yes(LedHue.amplitudeColor(1,56)==LedHue.color(1));
        yes(LedHue.amplitudeColor(10,0)==LedHue.SILENT);
        yes(LedHue.color(-1)==LedHue.color(0));
        if(args.length>0){
            int rows=0;
            for(String row:Files.readAllLines(Paths.get(args[0]))){
                if(row.startsWith("p,"))continue;
                String[] f=row.split(",");int p=Integer.parseInt(f[0]);
                yes(LedHue.rgb5(p)==((Integer.parseInt(f[1])<<10)|(Integer.parseInt(f[2])<<5)|Integer.parseInt(f[3])));
                rows++;
            }
            yes(rows==64);
            System.out.println("PASS RTL RGB5 palette -> App: all 64 hardware codes match");
        }
        System.out.println("PASS LedHue: "+checks+" checks, 33 anchors/HSV, silence, saturation and independent App scales");
    }
}
