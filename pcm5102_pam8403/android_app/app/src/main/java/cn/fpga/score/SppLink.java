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
    }
    private static final UUID SPP=UUID.fromString("00001101-0000-1000-8000-00805f9b34fb");
    private final Listener listener;
    private final BlockingQueue<String> responses=new LinkedBlockingQueue<>();
    private volatile BluetoothSocket socket;
    private final Object outputLock=new Object();
    private final Object commandLock=new Object();
    private volatile boolean waiting;
    private volatile long receivedBytes,receivedLines;
    private volatile String lastLine="";
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
        try{InputStream input=s.getInputStream();ByteArrayOutputStream b=new ByteArrayOutputStream();int ch;
            while((ch=input.read())!=-1){if(socket!=s)return;
                receivedBytes++;
                if(ch=='\n'){String line=new String(b.toByteArray(),StandardCharsets.US_ASCII).trim();b.reset();if(line.isEmpty())continue;
                    lastLine=line;receivedLines++;
                    listener.line(line);if(waiting)responses.offer(line);
                }else if(ch!='\r'){if(b.size()>=1024)throw new IOException("接收行过长，连接已关闭");b.write(ch);}}
            throw new IOException("设备已断开");
        }catch(IOException e){if(socket==s){socket=null;
                responses.offer("!DISCONNECTED");listener.disconnected(e.getMessage());}try{s.close();}catch(IOException ignored){}}
    }
    private void rawWrite(BluetoothSocket s,String text)throws IOException {
        synchronized(outputLock){if(socket!=s||!s.isConnected())throw new IOException("蓝牙已断开");OutputStream out=s.getOutputStream();out.write(text.getBytes(StandardCharsets.US_ASCII));out.flush();}
    }
    public String command(String command,String expected)throws IOException,InterruptedException {
        synchronized(commandLock){return commandLocked(command,expected);}
    }
    private String commandLocked(String command,String expected)throws IOException,InterruptedException {
        if(command.startsWith("AREC"))throw new IOException("当前 App 不支持板上 PCM 录音与 HC-05 音频回传");
        BluetoothSocket s=socket;if(s==null||!s.isConnected())throw new IOException("尚未连接 HC-05");
        if(command.length()>64||command.indexOf('\n')>=0||command.indexOf('\r')>=0||!command.matches("[ -~]+"))throw new IOException("命令必须为 1～64 个可打印 ASCII 字符，不能包含换行");
        long bytesBefore=receivedBytes,linesBefore=receivedLines;
        responses.clear();waiting=true;
        try{rawWrite(s,command+"\n");
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);
            for(;;){long remaining=deadline-System.nanoTime();if(remaining<=0){
                    long bytes=receivedBytes-bytesBefore;
                    String receivedLast=lastLine;
                    String detail=bytes==0?"本次未收到任何字节":receivedLines==linesBefore?"本次收到 "+bytes+" 字节，未收到完整非空行（LF）":"本次收到 "+bytes+" 字节；最近完整行："+receivedLast.substring(0,Math.min(96,receivedLast.length()));
                    throw new IOException("命令 "+command+" 等待回复超时（4 秒，期望 "+expected+"）。\n"+detail+"\n连接已关闭，请重连；原有效曲谱保留");
                }
                String response=responses.poll(remaining,TimeUnit.NANOSECONDS);if(response==null)continue;
                if(response.equals("!DISCONNECTED"))throw new IOException("蓝牙已断开；重新连接后可从头重试下载");
                if(response.startsWith("ERR,REC_OVERFLOW,"))continue;
                if(response.matches("ERR,(STATE|CMD|BUSY|RANGE|MISSING|MAP|KEY|NOTE)"))
                    throw new CommandRejectedException(command,response);
                if(response.startsWith("ERR,"))throw new IOException("设备返回 "+response);
                String type=expected.endsWith(",")?expected.substring(0,expected.length()-1):expected;
                if(!type.equals("OK")&&!type.equals("PONG")&&response.startsWith(type+","))return response;
                if(expected.equals("OK")&&(response.equals("OK")||response.startsWith("OK,")))return response;
                if(expected.equals("PONG")&&response.equals("PONG"))return response;
            }
        }catch(CommandRejectedException e){throw e;}
        catch(IOException|InterruptedException e){close();throw e;}finally{waiting=false;}
    }
    @Override public void close(){waiting=false;BluetoothSocket s=socket;socket=null;
        if(s!=null)try{s.close();}catch(IOException ignored){}
        responses.clear();responses.offer("!DISCONNECTED");}
}
