package cn.fpga.score;

import android.bluetooth.*;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** SPP transport consumes real RTL FAR1 bytes, sends ACKs, and fences control traffic. */
public final class SppAudioTest {
    private static int checks;
    private static void check(boolean b){checks++;if(!b)throw new AssertionError("SPP audio check "+checks);}
    private static final class Observer implements SppLink.Listener {
        final CountDownLatch done=new CountDownLatch(1);final AtomicInteger callbacks=new AtomicInteger();
        public void line(String s){}public void disconnected(String s){}
        public void audioProgress(AudioRecording r){}public void audioFinished(AudioRecording r){callbacks.incrementAndGet();done.countDown();}
    }
    public static void main(String[] args)throws Exception{
        byte[] fixture=Files.readAllBytes(new File(args[0]).toPath());List<byte[]> packets=new ArrayList<>();
        for(int n=0;n<fixture.length;){int length=18+(fixture[n+6]&255)+((fixture[n+7]&255)<<8);packets.add(Arrays.copyOfRange(fixture,n,n+length));n+=length;}
        check(packets.size()>=4);File dir=Files.createTempDirectory("hc05-audio-test-").toFile();
        Observer observer=new Observer();SppLink link=new SppLink(observer);BluetoothSocket socket=new BluetoothSocket();
        AtomicInteger packetIndex=new AtomicInteger(-1),writes=new AtomicInteger();CountDownLatch startAck=new CountDownLatch(1);
        socket.onCommand=command->{writes.incrementAndGet();if(command.startsWith("AREC_SEND,")){socket.feed("OK\r\n");return;}
            int ack=Integer.parseInt(command.trim().substring(9));int index=packetIndex.get();
            if(index==-1){if(ack!=65535)throw new AssertionError();packetIndex.set(0);socket.feed(packets.get(0));}
            else {if(ack!=index)throw new AssertionError("ACK sequence");
                if(index==0){startAck.countDown();return;}
                if(index+1<packets.size()){packetIndex.incrementAndGet();socket.feed(packets.get(index+1));}
            }
        };
        link.connect(new BluetoothDevice(socket));AudioRecording take=new AudioRecording(new File(dir,"good.INCOMPLETE.wav"),4660);link.downloadAudio(take);
        check(startAck.await(2,TimeUnit.SECONDS));int before=writes.get();
        try{link.command("VIZ?","V");throw new AssertionError();}catch(IOException expected){check(expected.getMessage().contains("占用"));}
        check(writes.get()==before&&link.connected());packetIndex.set(1);socket.feed(packets.get(1));
        check(observer.done.await(5,TimeUnit.SECONDS));check(take.complete()&&!link.audioActive()&&observer.callbacks.get()==1);
        check(!take.file().getName().contains("INCOMPLETE"));check(writes.get()==packets.size()+2);link.close();check(observer.callbacks.get()==1);
        Observer interrupted=new Observer();SppLink cut=new SppLink(interrupted);BluetoothSocket partial=new BluetoothSocket();CountDownLatch dataAck=new CountDownLatch(1);
        partial.onCommand=command->{
            if(command.startsWith("AREC_SEND,"))partial.feed("OK\r\n");
            else if(command.startsWith("AREC_ACK,65535"))partial.feed(packets.get(0));
            else if(command.equals("AREC_ACK,0\r\n"))partial.feed(packets.get(1));
            else if(command.equals("AREC_ACK,1\r\n"))dataAck.countDown();
        };
        cut.connect(new BluetoothDevice(partial));AudioRecording prefix=new AudioRecording(new File(dir,"cut.INCOMPLETE.wav"),4660);cut.downloadAudio(prefix);
        check(dataAck.await(2,TimeUnit.SECONDS));cut.close();check(interrupted.done.await(2,TimeUnit.SECONDS));
        check(!prefix.complete()&&prefix.finished()&&prefix.bytesWritten()==512&&prefix.file().getName().contains("INCOMPLETE"));
        check(interrupted.callbacks.get()==1&&prefix.file().length()==572);cut.close();check(interrupted.callbacks.get()==1);
        System.out.println("PASS SppAudio: "+checks+" checks; real RTL packets, ACK order, exclusive commands, complete WAV and disconnect prefix");
    }
}
