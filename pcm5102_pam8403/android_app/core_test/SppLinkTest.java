package cn.fpga.score;
import android.bluetooth.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

public final class SppLinkTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("check "+checks);}
    private interface Attempt{void run()throws Exception;}
    private static void fails(Attempt attempt,String text)throws Exception{checks++;try{attempt.run();}catch(IOException e){if(e.getMessage().contains(text))return;throw e;}throw new AssertionError("Expected: "+text);}
    public static void main(String[] args)throws Exception{
        List<String> lines=Collections.synchronizedList(new ArrayList<>());CountDownLatch lost=new CountDownLatch(1);
        SppLink link=new SppLink(new SppLink.Listener(){public void line(String line){lines.add(line);}public void disconnected(String reason){lost.countDown();}});
        BluetoothSocket a=new BluetoothSocket();a.onCommand=c->{yes(c.equals("PING\r\n"));a.feed("PONG\r\n");};link.connect(new BluetoothDevice(a));yes(link.command("PING","PONG").equals("PONG"));
        // Fragmented lines and asynchronous recording-overflow must not abort a valid command.
        a.onCommand=c->{a.feed("EVT,120,01,0,39321,65535\r");a.feed("\nERR,REC_OVERFLOW,1\r\nO");a.feed("K\r\n");};
        yes(link.command("STOP","OK").equals("OK"));yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,1"));
        // New controls use the same acknowledged transport while recording lines arrive.
        for(String control:new String[]{"GUITAR","TONE,0","TONE,1","TONE,2","TONE,3","TONE,4","VIBRATO,0","VIBRATO,1","BANK,0","BANK,1","ADSR,TOUCH,10,80,60,200","ADSR,SENSOR,10,80,60,200","ADSR_RESET,TOUCH","ADSR_RESET,SENSOR","BEND,1,8192","BEND,4,16384","BEND,7,32768","BEND_RESET"}){
            final String expected=control+"\r\n";
            a.onCommand=c->{yes(c.equals(expected));a.feed("EVT,140,03,1,30000,65535\r\nERR,REC_OVERFLOW,2\r\nOK\r\n");};
            yes(link.command(control,"OK").equals("OK"));
        }
        yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,2"));
        // Neither events nor the recording-end marker acknowledge a gesture command.
        CountDownLatch controlSent=new CountDownLatch(1);ExecutorService controlThread=Executors.newSingleThreadExecutor();
        a.onCommand=c->{controlSent.countDown();a.feed("EVT,160,00,0,0,65535\r\nREC_END,0\r\n");};
        Future<String> controlAck=controlThread.submit(()->link.command("BANK,1","OK"));
        yes(controlSent.await(1,TimeUnit.SECONDS));boolean stillWaiting=false;
        try{controlAck.get(100,TimeUnit.MILLISECONDS);}catch(TimeoutException expected){stillWaiting=true;}
        yes(stillWaiting);a.feed("OK\r\n");yes(controlAck.get(1,TimeUnit.SECONDS).equals("OK"));controlThread.shutdownNow();
        a.onCommand=c->a.feed("ERR,MAP\r\n");fails(()->link.command("SONG_END","OK"),"ERR,MAP");yes(!link.connected());
        BluetoothSocket b=new BluetoothSocket();link.connect(new BluetoothDevice(b));b.onCommand=c->b.eof();fails(()->link.command("PING","PONG"),"断开");yes(lost.await(1,TimeUnit.SECONDS));
        // A user cancel wakes the waiting command immediately and closes the socket.
        BluetoothSocket c=new BluetoothSocket();CountDownLatch sent=new CountDownLatch(1);c.onCommand=x->sent.countDown();link.connect(new BluetoothDevice(c));ExecutorService thread=Executors.newSingleThreadExecutor();
        Future<Boolean> cancelled=thread.submit(()->{try{link.command("SONG_BEGIN,2","OK");return false;}catch(IOException e){return true;}});yes(sent.await(1,TimeUnit.SECONDS));link.close();yes(cancelled.get(1,TimeUnit.SECONDS));thread.shutdownNow();
        // The 4-second timeout fences off all stale ACKs by closing the old session.
        BluetoothSocket d=new BluetoothSocket();link.connect(new BluetoothDevice(d));long begin=System.nanoTime();fails(()->link.command("SONG_CHORD,0,1,500","OK"),"超时");yes(!link.connected());yes(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-begin)>=3900);
        BluetoothSocket e=new BluetoothSocket();e.onCommand=x->e.feed("OK\r\n");link.connect(new BluetoothDevice(e));d.feed("OK\r\n");yes(link.command("SONG_BEGIN,1","OK").equals("OK"));link.close();
        System.out.println("PASS SppLink: "+checks+" assertions");
    }
}
