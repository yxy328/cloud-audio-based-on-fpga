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
        SppLink link=new SppLink(new SppLink.Listener(){public void line(String line){lines.add(line);}public void disconnected(String reason){lost.countDown();}
            public void audioProgress(AudioRecording recording){}public void audioFinished(AudioRecording recording){}});
        BluetoothSocket a=new BluetoothSocket();a.onCommand=c->{yes(c.equals("PING\r\n"));a.feed("PONG\r\n");};link.connect(new BluetoothDevice(a));yes(link.command("PING","PONG").equals("PONG"));
        // Fragmented lines and asynchronous recording-overflow must not abort a valid command.
        a.onCommand=c->{a.feed("EVT,120,01,0,39321,65535\r");a.feed("\nERR,REC_OVERFLOW,1\r\nO");a.feed("K\r\n");};
        yes(link.command("STOP","OK").equals("OK"));yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,1"));
        // New controls use the same acknowledged transport while recording lines arrive.
        for(String control:new String[]{"GUITAR","TONE,0","TONE,1","TONE,2","TONE,3","TONE,4","VIBRATO,0","VIBRATO,1","BANK,0","BANK,1","ADSR,TOUCH,10,80,60,200","ADSR,SENSOR,10,80,60,200","ADSR_RESET,TOUCH","ADSR_RESET,SENSOR","BEND,1,8192","BEND,4,16384","BEND,7,32768","BEND_RESET","TOUCH,8","TOUCH,16","EFFECT,1,8","EFFECT,2,4","HOLD,1","HOLD,0","VOLUME,0","VOLUME,16","ANALOG,1","ANALOG,2","ANALOG,3","ANALOG,4","PRESSURE,1","CAL,0,590","SERIAL,0","SERIAL,1","PANIC"}){
            final String expected=control+"\r\n";
            a.onCommand=c->{yes(c.equals(expected));a.feed("EVT,140,03,1,30000,65535\r\nERR,REC_OVERFLOW,2\r\nOK\r\n");};
            yes(link.command(control,"OK").equals("OK"));
        }
        a.onCommand=c->a.feed("EVT,1,0,0,0,0\r\nCTRL,1,2,8,1,4,16,0\r\n");
        yes(link.command("CTRL?","CTRL").equals("CTRL,1,2,8,1,4,16,0"));
        a.onCommand=c->a.feed("ADC,3FF,0\r\n");yes(link.command("ADC?","ADC").equals("ADC,3FF,0"));
        a.onCommand=c->a.feed("CAL,000,24E\r\n");yes(link.command("CAL?","CAL").equals("CAL,000,24E"));
        a.onCommand=c->a.feed("SERIAL,1\r\n");yes(link.command("SERIAL?","SERIAL").equals("SERIAL,1"));
        for(String control:new String[]{"AREC_PREP","AREC_START,0","AREC_START,65535","AREC_STOP","AREC_ABORT","AREC_SEND,0","AREC_SEND,65535"}){
            a.onCommand=c->{yes(c.equals(control+"\r\n"));a.feed("EVT,160,00,0,0,65535\r\nOK\r\n");};
            yes(link.command(control,"OK").equals("OK"));
        }
        a.onCommand=c->a.feed("EVT,180,00,0,0,65535\r\nAREC,1,1,0\r\n");
        yes(link.command("AREC?","AREC").equals("AREC,1,1,0"));
        yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,2"));
        // All FPGA XY parameter combinations share the command queue. Split ACKs
        // and interleaved event/end lines must not be mistaken for confirmation.
        for(int ratio=0;ratio<4;ratio++)for(int phase=0;phase<4;phase++){
            final String xy="XY,"+ratio+","+phase;
            a.onCommand=c->{yes(c.equals(xy+"\r\n"));a.feed("EVT,180,01,0,30000,65535\r\nREC_END,0\r\nO");a.feed("K\r");a.feed("\n");};
            yes(link.command(xy,"OK").equals("OK"));yes(link.connected());
        }
        a.onCommand=c->{yes(c.equals("VIS,3\r\n"));a.feed("V,17E78440F7358B52507314831040\r\nEVT,1,01,0,0,0\r\nOK\r\n");};
        yes(link.command("VIS,3","OK").equals("OK"));
        a.onCommand=c->a.feed("OK\r\nVIS,3,3,2,0,2,1,7\r\n");
        yes(link.command("VIS?","VIS").equals("VIS,3,3,2,0,2,1,7"));
        a.onCommand=c->{a.feed("VIS,3,3,2,0,2,1,7\r\nEVT,1,01,0,0,0\r\nV,17E78440F735");a.feed("8B52507314831040\r");a.feed("\n");};
        yes(link.command("VIZ?","V").equals("V,17E78440F7358B52507314831040"));
        a.onCommand=c->a.feed("TAKE,00,0,000000,000,000000\r\n");
        yes(link.command("TAKE?","TAKE,").equals("TAKE,00,0,000000,000,000000"));
        // Neither events nor the recording-end marker acknowledge a gesture/XY command.
        for(String pending:new String[]{"BANK,1","XY,1,2"}){
            CountDownLatch controlSent=new CountDownLatch(1);ExecutorService controlThread=Executors.newSingleThreadExecutor();
            a.onCommand=c->{controlSent.countDown();a.feed("EVT,160,00,0,0,65535\r\nREC_END,0\r\n");};
            Future<String> controlAck=controlThread.submit(()->link.command(pending,"OK"));
            yes(controlSent.await(1,TimeUnit.SECONDS));boolean stillWaiting=false;
            try{controlAck.get(100,TimeUnit.MILLISECONDS);}catch(TimeoutException expected){stillWaiting=true;}
            yes(stillWaiting);a.feed("OK\r\n");yes(controlAck.get(1,TimeUnit.SECONDS).equals("OK"));controlThread.shutdownNow();
        }
        for(String error:new String[]{"ERR,STATE","ERR,CMD","ERR,BUSY","ERR,RANGE","ERR,MISSING","ERR,MAP","ERR,KEY","ERR,NOTE"}){
            a.onCommand=c->a.feed(error+"\r\n");fails(()->link.command("AREC_PREP","OK"),error);yes(link.connected());
            a.onCommand=c->a.feed("PONG\r\n");yes(link.command("PING","PONG").equals("PONG"));
        }
        a.onCommand=c->a.feed("ERR,UART\r\n");fails(()->link.command("PING","PONG"),"ERR,UART");yes(!link.connected());
        BluetoothSocket b=new BluetoothSocket();link.connect(new BluetoothDevice(b));b.onCommand=c->b.eof();fails(()->link.command("PING","PONG"),"断开");yes(lost.await(1,TimeUnit.SECONDS));
        // A user cancel wakes the waiting command immediately and closes the socket.
        BluetoothSocket c=new BluetoothSocket();CountDownLatch sent=new CountDownLatch(1);c.onCommand=x->sent.countDown();link.connect(new BluetoothDevice(c));ExecutorService thread=Executors.newSingleThreadExecutor();
        Future<Boolean> cancelled=thread.submit(()->{try{link.command("SONG_BEGIN,2","OK");return false;}catch(IOException e){return true;}});yes(sent.await(1,TimeUnit.SECONDS));link.close();yes(cancelled.get(1,TimeUnit.SECONDS));thread.shutdownNow();
        // The 4-second timeout fences off all stale ACKs by closing the old session.
        BluetoothSocket d=new BluetoothSocket();link.connect(new BluetoothDevice(d));long begin=System.nanoTime();fails(()->link.command("SONG_CHORD,0,1,500","OK"),"超时");yes(!link.connected());yes(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-begin)>=3900);
        BluetoothSocket e=new BluetoothSocket();e.onCommand=x->e.feed("OK\r\n");link.connect(new BluetoothDevice(e));d.feed("OK\r\n");yes(link.command("SONG_BEGIN,1","OK").equals("OK"));link.close();
        BluetoothSocket oldFirmware=new BluetoothSocket();oldFirmware.onCommand=x->oldFirmware.feed("ERR,CMD\r\n");link.connect(new BluetoothDevice(oldFirmware));
        fails(()->link.command("XY,2,0","OK"),"ERR,CMD");yes(link.connected());link.close();
        System.out.println("PASS SppLink: "+checks+" assertions");
    }
}
