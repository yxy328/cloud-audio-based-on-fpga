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
});
        BluetoothSocket a=new BluetoothSocket();a.onCommand=c->{yes(c.equals("PING\n"));a.feed("PONG\r\n");};link.connect(new BluetoothDevice(a));yes(link.command("PING","PONG").equals("PONG"));
        // Fragmented lines and asynchronous recording-overflow must not abort a valid command.
        a.onCommand=c->{a.feed("EVT,120,01,0,39321,65535\r");a.feed("\nERR,REC_OVERFLOW,1\r\nO");a.feed("K\r\n");};
        yes(link.command("STOP","OK").equals("OK"));yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,1"));
        // New controls use the same acknowledged transport while recording lines arrive.
        for(String control:new String[]{"GUITAR","TONE,0","TONE,1","TONE,2","TONE,3","TONE,4","VIBRATO,0","VIBRATO,1","BANK,0","BANK,1","ADSR,TOUCH,10,80,60,200","ADSR,SENSOR,10,80,60,200","ADSR_RESET,TOUCH","ADSR_RESET,SENSOR","BEND,1,8192","BEND,4,16384","BEND,7,32768","BEND_RESET","TOUCH,8","TOUCH,16","EFFECT,1,8","EFFECT,2,4","HOLD,1","HOLD,0","HOLD,2","POLY,1","POLY,2","POLY,4","POLY,8","POLY,16","VOLUME,0","VOLUME,16","ANALOG,1","ANALOG,2","ANALOG,3","ANALOG,4","PRESSURE,1","CAL,0,590","SERIAL,0","SERIAL,1","PANIC"}){
            final String expected=control+"\n";
            a.onCommand=c->{yes(c.equals(expected));a.feed("EVT,140,03,1,30000,65535\r\nERR,REC_OVERFLOW,2\r\nOK\r\n");};
            yes(link.command(control,"OK").equals("OK"));
        }
        a.onCommand=c->a.feed("EVT,1,0,0,0,0\r\nCTRL,1,2,8,1,4,16,0\r\n");
        yes(link.command("CTRL?","CTRL").equals("CTRL,1,2,8,1,4,16,0"));
        a.onCommand=c->a.feed("CTRL2,1,2,8,2,4,16,0,04,03\r\n");
        yes(link.command("CTRL2?","CTRL2").equals("CTRL2,1,2,8,2,4,16,0,04,03"));
        a.onCommand=c->a.feed("HOLD,2\r\n");yes(link.command("HOLD,?","HOLD").equals("HOLD,2"));
        a.onCommand=c->a.feed("POLY,04\r\n");yes(link.command("POLY,?","POLY").equals("POLY,04"));
        a.onCommand=c->a.feed("ADC,3FF,0\r\n");yes(link.command("ADC?","ADC").equals("ADC,3FF,0"));
        a.onCommand=c->a.feed("CAL,000,24E\r\n");yes(link.command("CAL?","CAL").equals("CAL,000,24E"));
        a.onCommand=c->a.feed("SERIAL,1\r\n");yes(link.command("SERIAL?","SERIAL").equals("SERIAL,1"));
        yes(link.connected());yes(lines.contains("ERR,REC_OVERFLOW,2"));
        // All FPGA XY parameter combinations share the command queue. Split ACKs
        // and interleaved event/end lines must not be mistaken for confirmation.
        for(int ratio=0;ratio<4;ratio++)for(int phase=0;phase<4;phase++){
            final String xy="XY,"+ratio+","+phase;
            a.onCommand=c->{yes(c.equals(xy+"\n"));a.feed("EVT,180,01,0,30000,65535\r\nREC_END,0\r\nO");a.feed("K\r");a.feed("\n");};
            yes(link.command(xy,"OK").equals("OK"));yes(link.connected());
        }
        a.onCommand=c->{yes(c.equals("VIS,3\n"));a.feed("V,17E78440F7358B52507314831040\r\nEVT,1,01,0,0,0\r\nOK\r\n");};
        yes(link.command("VIS,3","OK").equals("OK"));
        a.onCommand=c->a.feed("OK\r\nVIS,3,3,2,0,2,1,7\r\n");
        yes(link.command("VIS?","VIS").equals("VIS,3,3,2,0,2,1,7"));
        a.onCommand=c->{a.feed("VIS,3,3,2,0,2,1,7\r\nEVT,1,01,0,0,0\r\nV,17E78440F735");a.feed("8B52507314831040\r");a.feed("\n");};
        yes(link.command("VIZ?","V").equals("V,17E78440F7358B52507314831040"));
        a.onCommand=c->a.feed("TAKE,00,0,000000,000,000000\r\n");
        yes(link.command("TAKE?","TAKE,").equals("TAKE,00,0,000000,000,000000"));
        // v1.21 performance queries must reach the waiting command even while events stream in.
        a.onCommand=c->a.feed("EVT,1,01,0,0,0\r\nPITCH,2000,8000,1000,4000\r\n");
        yes(link.command("PITCH,?","PITCH").equals("PITCH,2000,8000,1000,4000"));
        a.onCommand=c->a.feed("VIB,0008,0D96,100,0000\r\n");yes(link.command("VIB,?","VIB").equals("VIB,0008,0D96,100,0000"));
        a.onCommand=c->a.feed("EFFECT2,0\r\n");yes(link.command("EFFECT2,?","EFFECT2").equals("EFFECT2,0"));
        a.onCommand=c->{a.feed("P");a.feed("ITCH,2000,8000,1000,4000\r\n");};
        yes(link.command("PITCH,?","PITCH").equals("PITCH,2000,8000,1000,4000"));
        // Live key uplink: unsolicited K lines must reach the listener without swallowing the ACK.
        a.onCommand=c->{yes(c.equals("KLIVE_ON\n"));a.feed("K,01,1\r\nK,03,1\r\nOK\r\nK,01,0\r\n");};
        yes(link.command("KLIVE_ON","OK").equals("OK"));yes(lines.contains("K,01,1"));yes(lines.contains("K,01,0"));
        a.onCommand=c->{yes(c.equals("KLIVE_OFF\n"));a.feed("K,03,0\r\nOK\r\n");};
        yes(link.command("KLIVE_OFF","OK").equals("OK"));
        String[][] initialization={
            {"PING","PONG","PONG"},
            {"MAP?","MAP","MAP,60,61,62,63,64,65,66"},
            {"CTRL2?","CTRL2","CTRL2,1,0,4,0,0,16,0,16,00"},
            {"SERIAL?","SERIAL","SERIAL,0"},{"CAL?","CAL","CAL,000,3FF"},
            {"PITCH,?","PITCH","PITCH,2000,8000,1000,4000"},
            {"VIB,?","VIB","VIB,0008,0D96,100,0000"},{"EFFECT2,?","EFFECT2","EFFECT2,0"},
            {"TAKE?","TAKE,","TAKE,00,0,000000,000,000000"},{"VIS?","VIS","VIS,0,0,2,0,0,0,0"}
        };
        for(String[] step:initialization){
            a.onCommand=c->{yes(c.equals(step[0]+"\n"));a.feed("EVT,2,01,0,0,0\r\nV,old\r\n");for(char ch:(step[2]+"\r\n").toCharArray())a.feed(new byte[]{(byte)ch});};
            String reply=link.command(step[0],step[1]);yes(reply.equals(step[2]));yes(link.connected());
            if(step[1].equals("PITCH"))yes(PerformanceParams.parsePitch(reply)[3]==16384);
            if(step[1].equals("VIB"))yes(PerformanceParams.parseVibrato(reply)[1]==3478);
            if(step[1].equals("EFFECT2"))yes(PerformanceParams.parseEcho(reply)[0]==0);
        }
        String boundary=String.join("",Collections.nCopies(64,"X"));
        a.onCommand=c->{yes(c.equals(boundary+"\n"));a.feed("ERR,CMD\r\n");};
        fails(()->link.command(boundary,"OK"),"ERR,CMD");yes(link.connected());
        a.onCommand=c->{throw new AssertionError("Invalid command reached transport");};
        for(String invalid:new String[]{boundary+"X","PING\n","PING\r","P\tING","测试",""}){
            fails(()->link.command(invalid,"OK"),"ASCII");yes(link.connected());
        }
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
            a.onCommand=c->a.feed(error+"\r\n");fails(()->link.command("TAKE_REC","OK"),error);yes(link.connected());
            a.onCommand=c->a.feed("PONG\r\n");yes(link.command("PING","PONG").equals("PONG"));
        }
        a.onCommand=c->a.feed("ERR,UART\r\n");fails(()->link.command("PING","PONG"),"ERR,UART");yes(!link.connected());
        BluetoothSocket b=new BluetoothSocket();link.connect(new BluetoothDevice(b));b.onCommand=c->b.eof();fails(()->link.command("PING","PONG"),"断开");yes(lost.await(1,TimeUnit.SECONDS));
        // A user cancel wakes the waiting command immediately and closes the socket.
        BluetoothSocket c=new BluetoothSocket();CountDownLatch sent=new CountDownLatch(1);c.onCommand=x->sent.countDown();link.connect(new BluetoothDevice(c));ExecutorService thread=Executors.newSingleThreadExecutor();
        Future<Boolean> cancelled=thread.submit(()->{try{link.command("SONG_BEGIN,2","OK");return false;}catch(IOException e){return true;}});yes(sent.await(1,TimeUnit.SECONDS));link.close();yes(cancelled.get(1,TimeUnit.SECONDS));thread.shutdownNow();
        // The 4-second timeout fences off all stale ACKs by closing the old session.
        BluetoothSocket d=new BluetoothSocket();link.connect(new BluetoothDevice(d));long begin=System.nanoTime();fails(()->link.command("SONG_CHORD,0,1,500","OK"),"超时");yes(!link.connected());yes(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-begin)>=3900);
        for(String data:new String[]{"","PITCH,2000,8000,1000,4000","EVT,1,01,0,0,0\r\nVIB,0008,0D96,100,0000\r\n"}){
            BluetoothSocket timed=new BluetoothSocket();timed.onCommand=x->timed.feed(data);link.connect(new BluetoothDevice(timed));
            try{link.command("PITCH,?","PITCH");throw new AssertionError("Missing PITCH acknowledged");}
            catch(IOException timeout){yes(timeout.getMessage().contains("PITCH,?"));yes(timeout.getMessage().contains("期望 PITCH"));
                yes(timeout.getMessage().contains(data.isEmpty()?"未收到任何字节":data.contains("\n")?"最近完整行：VIB,0008,0D96,100,0000":"未收到完整非空行"));}
            yes(!link.connected());
        }
        BluetoothSocket e=new BluetoothSocket();e.onCommand=x->e.feed("OK\r\n");link.connect(new BluetoothDevice(e));d.feed("OK\r\n");yes(link.command("SONG_BEGIN,1","OK").equals("OK"));link.close();
        BluetoothSocket oldFirmware=new BluetoothSocket();oldFirmware.onCommand=x->oldFirmware.feed("ERR,CMD\r\n");link.connect(new BluetoothDevice(oldFirmware));
        fails(()->link.command("XY,2,0","OK"),"ERR,CMD");yes(link.connected());link.close();
        System.out.println("PASS SppLink: "+checks+" assertions");
    }
}
