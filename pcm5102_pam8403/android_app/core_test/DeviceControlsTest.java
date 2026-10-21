package cn.fpga.score;
import java.io.IOException;
public final class DeviceControlsTest {
    static int checks;
    static void yes(boolean b){checks++;if(!b)throw new AssertionError("check "+checks);}
    static void bad(String s)throws Exception{checks++;try{DeviceControls.parse(s);}catch(IOException e){return;}throw new AssertionError(s);}
    public static void main(String[] args)throws Exception{
        for(int mode=0;mode<2;mode++)for(int effect=0;effect<3;effect++)for(int wet=0;wet<=8;wet++)for(int analog=0;analog<=4;analog++)for(int volume=0;volume<=16;volume++){
            DeviceControls c=DeviceControls.parse("CTRL,"+mode+","+effect+","+wet+",1,"+analog+","+volume+",0");
            yes(c.mode16==mode&&c.effect==effect&&c.wet==wet&&c.analog==analog&&c.volume==volume&&c.hold==1&&c.pressure==0);
        }
        yes(DeviceControls.touchCommand(0).equals("TOUCH,8"));yes(DeviceControls.touchCommand(1).equals("TOUCH,16"));
        for(int poly:new int[]{1,2,4,8,16})for(int voices=0;voices<=16;voices++){
            DeviceControls c=DeviceControls.parse("CTRL2,1,2,8,2,4,16,0,"+poly+","+voices);
            yes(c.extended&&c.hold==2&&c.poly==poly&&c.voices==voices&&c.summary().contains("钢琴踏板"));
        }
        yes(!DeviceControls.parse("CTRL,0,0,4,0,0,16,0").extended);
        for(String s:new String[]{"CTRL2,1,0,4,3,0,16,0,16,0","CTRL2,1,0,4,2,0,16,0,3,0","CTRL2,1,0,4,2,0,16,0,16,17","CTRL2,1,0,4,2,0,16,0,16"})bad(s);
        for(String s:new String[]{"CTRL,2,0,4,0,0,16,0","CTRL,0,3,4,0,0,16,0","CTRL,0,0,9,0,0,16,0","CTRL,0,0,4,2,0,16,0","CTRL,0,0,4,0,5,16,0","CTRL,0,0,4,0,0,17,0","CTRL,0,0,4,0,0,16,2","CTRL,0,0,4,0,0,-1,0","CTRL,0,0,4,0,0,16,0,","CTRL,0,0,4,0,0,16","CTRL,0,0,4,0,0,+1,0","CTRL,0,0,4,0,0,,0","MAP,0,0,4,0,0,16,0"})bad(s);
        System.out.println("PASS device controls: "+checks+" assertions");
    }
}
