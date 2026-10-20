package cn.fpga.score;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.*;

/** Classic Bluetooth SPP. One command in flight; a timeout closes the session. */
public final class SppLink implements Closeable {
    /** A complete device refusal ends this command without losing the SPP session. */
    public static final class CommandRejectedException extends IOException {
        public final String command,response;
        private CommandRejectedException(String command,String response){
            super("设备返回 "+response);this.command=command;this.response=response;
        }
    }
    public interface Listener {
        void line(String line);void disconnected(String reason);
        void audioProgress(AudioRecording recording);void audioFinished(AudioRecording recording);
    }
    private static final UUID SPP=UUID.fromString("00001101-0000-1000-8000-00805f9b34fb");
    private final Listener listener;
    private final BlockingQueue<String> responses=new LinkedBlockingQueue<>();
    private volatile BluetoothSocket socket;
    private volatile AudioRecording audioRecording;
    private final Object outputLock=new Object();
    private final Object commandLock=new Object(),audioLock=new Object();
    private volatile long audioLastByte;
    private ScheduledExecutorService audioTimer;
    private volatile boolean waiting;
    public SppLink(Listener listener){this.listener=listener;}
    public boolean connected(){BluetoothSocket s=socket;return s!=null&&s.isConnected();}
    public void connect(BluetoothDevice device)throws IOException {
        close();final BluetoothSocket s=device.createRfcommSocketToServiceRecord(SPP);socket=s;
        ScheduledExecutorService timeout=Executors.newSingleThreadScheduledExecutor();
        ScheduledFuture<?> guard=timeout.schedule(()->{if(socket==s&&!s.isConnected())try{s.close();}catch(IOException ignored){}},15,TimeUnit.SECONDS);
        try{s.connect();}catch(IOException e){if(socket==s)socket=null;try{s.close();}catch(IOException ignored){}throw e;}finally{guard.cancel(false);timeout.shutdownNow();}
        if(socket!=s){s.close();throw new IOException("连接已取消");}
        Thread reader=new Thread(()->read(s),"HC05-reader");reader.setDaemon(true);reader.start();
    }
    private void read(BluetoothSocket s){
        try{InputStream input=s.getInputStream();ByteArrayOutputStream b=new ByteArrayOutputStream();int ch;byte[] one=new byte[1];
            while((ch=input.read())!=-1){if(socket!=s)return;AudioRecording audio=audioRecording;
                if(audio!=null){audioLastByte=System.nanoTime();one[0]=(byte)ch;audio.feed(one,1);Integer ack;
                    try{while((ack=audio.pollAcknowledgement())!=null){rawWrite(s,"AREC_ACK,"+ack+"\r\n");listener.audioProgress(audio);}}
                    finally{if(audio.finished())finishAudio(audio);}
                    continue;
                }
                if(ch=='\n'){String line=new String(b.toByteArray(),StandardCharsets.US_ASCII).trim();b.reset();if(line.isEmpty())continue;
                    listener.line(line);if(waiting&&!line.startsWith("ERR,REC_OVERFLOW,")&&(line.equals("OK")||line.startsWith("OK,")||line.startsWith("ERR,")||line.startsWith("MAP,")||line.startsWith("CTRL,")||line.startsWith("ADC,")||line.startsWith("CAL,")||line.startsWith("SERIAL,")||line.startsWith("AREC,")||line.startsWith("VIS,")||line.startsWith("V,")||line.startsWith("TAKE,")||line.equals("PONG")))responses.offer(line);
                }else if(ch!='\r'){if(b.size()>=1024)throw new IOException("接收行过长，连接已关闭");b.write(ch);}}
            throw new IOException("设备已断开");
        }catch(IOException e){if(socket==s){socket=null;AudioRecording audio=audioRecording;
                if(audio!=null)finishAudio(audio);
                responses.offer("!DISCONNECTED");listener.disconnected(e.getMessage());}try{s.close();}catch(IOException ignored){}}
    }
    private void rawWrite(BluetoothSocket s,String text)throws IOException {
        synchronized(outputLock){if(socket!=s||!s.isConnected())throw new IOException("蓝牙已断开");OutputStream out=s.getOutputStream();out.write(text.getBytes(StandardCharsets.US_ASCII));out.flush();}
    }
    public void beginAudio(AudioRecording recording)throws IOException {
        synchronized(commandLock){beginAudioLocked(recording);}
    }
    private void beginAudioLocked(AudioRecording recording)throws IOException {
        BluetoothSocket s=socket;if(s==null||!s.isConnected())throw new IOException("尚未连接 HC-05");
        synchronized(audioLock){
            if(audioRecording!=null)throw new IOException("已有音频回传正在进行");audioRecording=recording;audioLastByte=System.nanoTime();
            audioTimer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"HC05-audio-timeout");t.setDaemon(true);return t;});
            audioTimer.scheduleAtFixedRate(()->{if(audioRecording==recording&&System.nanoTime()-audioLastByte>TimeUnit.SECONDS.toNanos(10)){
                close();listener.disconnected("音频回传10秒无数据，文件已标记INCOMPLETE");
            }},1,1,TimeUnit.SECONDS);
        }
        try{rawWrite(s,"AREC_ACK,65535\r\n");}catch(IOException e){close();throw e;}
    }
    public void downloadAudio(AudioRecording recording)throws IOException,InterruptedException {
        synchronized(commandLock){commandLocked("AREC_SEND,"+recording.session(),"OK");beginAudioLocked(recording);}
    }
    private void finishAudio(AudioRecording recording){
        synchronized(audioLock){
            if(audioRecording!=recording)return;
            audioRecording=null;if(audioTimer!=null){audioTimer.shutdownNow();audioTimer=null;}
        }
        try{recording.close();}catch(IOException ignored){}listener.audioFinished(recording);
    }
    public boolean audioActive(){return audioRecording!=null;}
    public String command(String command,String expected)throws IOException,InterruptedException {
        synchronized(commandLock){return commandLocked(command,expected);}
    }
    private String commandLocked(String command,String expected)throws IOException,InterruptedException {
        if(audioActive())throw new IOException("音频回传占用HC-05，请完成或中止回传后再发送控制命令");
        BluetoothSocket s=socket;if(s==null||!s.isConnected())throw new IOException("尚未连接 HC-05");
        if(command.length()>62||command.indexOf('\n')>=0||command.indexOf('\r')>=0)throw new IOException("命令长度/格式无效");
        responses.clear();waiting=true;
        try{rawWrite(s,command+"\r\n");
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);
            for(;;){long remaining=deadline-System.nanoTime();if(remaining<=0)throw new IOException("等待回复超时；请重新连接并重新下载，原有效曲谱保留");
                String response=responses.poll(remaining,TimeUnit.NANOSECONDS);if(response==null)continue;
                if(response.equals("!DISCONNECTED"))throw new IOException("蓝牙已断开；重新连接后可从头重试下载");
                if(response.matches("ERR,(STATE|CMD|BUSY|RANGE|MISSING|MAP|KEY|NOTE)"))
                    throw new CommandRejectedException(command,response);
                if(response.startsWith("ERR,"))throw new IOException("设备返回 "+response);
                String type=expected.endsWith(",")?expected.substring(0,expected.length()-1):expected;
                if((type.equals("MAP")||type.equals("CTRL")||type.equals("ADC")||type.equals("CAL")||type.equals("SERIAL")||type.equals("AREC")||type.equals("VIS")||type.equals("V")||type.equals("TAKE"))&&response.startsWith(type+","))return response;
                if(expected.equals("OK")&&(response.equals("OK")||response.startsWith("OK,")))return response;
                if(expected.equals("PONG")&&response.equals("PONG"))return response;
            }
        }catch(CommandRejectedException e){throw e;}
        catch(IOException|InterruptedException e){close();throw e;}finally{waiting=false;}
    }
    @Override public void close(){waiting=false;BluetoothSocket s=socket;socket=null;AudioRecording audio=audioRecording;
        if(s!=null)try{s.close();}catch(IOException ignored){}if(audio!=null)finishAudio(audio);
        responses.clear();responses.offer("!DISCONNECTED");}
}
