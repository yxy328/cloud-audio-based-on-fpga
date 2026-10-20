package cn.fpga.score;
import android.bluetooth.*;
import java.io.*;
public final class RecordingSupportTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("support check "+checks);}
    public static void main(String[] args)throws Exception {
        SppLink link=new SppLink(new SppLink.Listener(){public void line(String s){}public void disconnected(String s){}public void audioProgress(AudioRecording r){}public void audioFinished(AudioRecording r){}});
        for(int variant=0;variant<4;variant++){
            final boolean audio=(variant&1)!=0,event=(variant&2)!=0;BluetoothSocket socket=new BluetoothSocket();
            socket.onCommand=c->{if(c.equals("AREC?\r\n"))socket.feed(audio?"AREC,0,0,0,0,0,0,0000,000000\r\n":"AREC,0,1,0\r\n");else if(c.equals("TAKE?\r\n"))socket.feed(event?"TAKE,00,0,000000,000,000000\r\n":"ERR,CMD\r\n");else if(c.equals("PING\r\n"))socket.feed("PONG\r\n");else throw new AssertionError("Probe mutated device: "+c);};
            link.connect(new BluetoothDevice(socket));RecordingSupport support=RecordingSupport.probe(link);
            check((support.audio!=null)==audio);check((support.events!=null)==event);check(link.connected());check(link.command("PING","PONG").equals("PONG"));
            if(!audio)try{RecordingSupport.readAudio(link);throw new AssertionError();}catch(RecordingSupport.UnsupportedFeatureException expected){check(expected.getMessage().contains("PCM5102_UNIFIED.fs"));check(link.connected());}
        }
        BluetoothSocket bad=new BluetoothSocket();bad.onCommand=c->bad.feed("AREC,broken\r\n");link.connect(new BluetoothDevice(bad));
        try{RecordingSupport.probe(link);throw new AssertionError();}catch(RecordingSupport.UnsupportedFeatureException e){throw new AssertionError("Malformed response became unsupported",e);}catch(IOException expected){check(true);}
        bad.onCommand=c->bad.feed("ERR,BUSY\r\n");try{RecordingSupport.probe(link);throw new AssertionError();}catch(SppLink.CommandRejectedException expected){check(link.connected());}
        link.close();System.out.println("PASS RecordingSupport: "+checks+" checks; ordinary/audio/event/unified firmware, read-only probes and rejection recovery");
    }
}
