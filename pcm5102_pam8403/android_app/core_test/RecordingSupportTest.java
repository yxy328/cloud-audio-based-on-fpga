package cn.fpga.score;
import android.bluetooth.*;
import java.io.*;
public final class RecordingSupportTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("RecordingSupport "+checks);}
    public static void main(String[] args)throws Exception{
        SppLink link=new SppLink(new SppLink.Listener(){public void line(String line){}public void disconnected(String reason){}});
        for(String response:new String[]{"TAKE,00,0,000000,000,000000","ERR,CMD","ERR,STATE","ERR,BUSY","TAKE,broken"}){
            BluetoothSocket socket=new BluetoothSocket();socket.onCommand=command->{check(command.equals("TAKE?\n"));socket.feed(response+"\r\n");};link.connect(new BluetoothDevice(socket));
            try{TakeStatus take=RecordingSupport.readEvents(link);check(response.startsWith("TAKE,00")&&take.count==0);}
            catch(RecordingSupport.UnsupportedFeatureException expected){check(response.equals("ERR,CMD")||response.equals("ERR,STATE"));check(expected.getMessage().contains("事件录制"));}
            catch(SppLink.CommandRejectedException expected){check(response.equals("ERR,BUSY"));}
            catch(IOException expected){check(response.equals("TAKE,broken"));}
            check(link.connected());
        }
        link.close();System.out.println("PASS RecordingSupport: "+checks+" checks; event-only queries and rejection recovery");
    }
}
