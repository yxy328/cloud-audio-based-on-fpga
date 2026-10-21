package cn.fpga.score;
import android.bluetooth.*;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;
public final class SppAudioTest {
    public static void main(String[] args)throws Exception{
        AtomicInteger writes=new AtomicInteger();BluetoothSocket socket=new BluetoothSocket();
        socket.onCommand=command->{writes.incrementAndGet();socket.feed("PONG\r\n");};
        SppLink link=new SppLink(new SppLink.Listener(){public void line(String line){}public void disconnected(String reason){}});link.connect(new BluetoothDevice(socket));int checks=0;
        for(String command:new String[]{"AREC?","AREC_PREP","AREC_START,0","AREC_STOP","AREC_SEND,1","AREC_ACK,0","AREC_ABORT"}){
            try{link.command(command,"OK");throw new AssertionError("PCM command escaped: "+command);}
            catch(IOException expected){if(!expected.getMessage().contains("不支持"))throw expected;checks++;}
            if(writes.get()!=0||!link.connected())throw new AssertionError("PCM rejection affected transport");checks++;
        }
        if(!link.command("PING","PONG").equals("PONG")||writes.get()!=1)throw new AssertionError("Control transport lost");checks++;
        link.close();System.out.println("PASS SppAudio: "+checks+" checks; removed PCM commands never reach Bluetooth");
    }
}
