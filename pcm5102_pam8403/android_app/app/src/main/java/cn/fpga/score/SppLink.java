package cn.fpga.score;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.*;

/** Classic Bluetooth SPP. One command in flight; a timeout closes the session. */
public final class SppLink implements Closeable {
    public interface Listener { void line(String line); void disconnected(String reason); }
    private static final UUID SPP=UUID.fromString("00001101-0000-1000-8000-00805f9b34fb");
    private final Listener listener;
    private final BlockingQueue<String> responses=new LinkedBlockingQueue<>();
    private volatile BluetoothSocket socket;
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
        try{InputStream input=s.getInputStream();ByteArrayOutputStream b=new ByteArrayOutputStream();int ch;
            while((ch=input.read())!=-1){if(socket!=s)return;if(ch=='\n'){String line=new String(b.toByteArray(),StandardCharsets.US_ASCII).trim();b.reset();if(line.isEmpty())continue;
                    listener.line(line);if(waiting&&!line.startsWith("ERR,REC_OVERFLOW,")&&(line.equals("OK")||line.startsWith("OK,")||line.startsWith("ERR,")||line.startsWith("MAP,")||line.equals("PONG")))responses.offer(line);
                }else if(ch!='\r'){if(b.size()>=1024)throw new IOException("接收行过长，连接已关闭");b.write(ch);}}
            throw new IOException("设备已断开");
        }catch(IOException e){if(socket==s){socket=null;responses.offer("!DISCONNECTED");listener.disconnected(e.getMessage());}try{s.close();}catch(IOException ignored){}}
    }
    public String command(String command,String expected)throws IOException,InterruptedException {
        BluetoothSocket s=socket;if(s==null||!s.isConnected())throw new IOException("尚未连接 HC-05");
        if(command.length()>62||command.indexOf('\n')>=0||command.indexOf('\r')>=0)throw new IOException("命令长度/格式无效");
        responses.clear();waiting=true;
        try{OutputStream out=s.getOutputStream();out.write((command+"\r\n").getBytes(StandardCharsets.US_ASCII));out.flush();
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);
            for(;;){long remaining=deadline-System.nanoTime();if(remaining<=0)throw new IOException("等待回复超时；请重新连接并重新下载，原有效曲谱保留");
                String response=responses.poll(remaining,TimeUnit.NANOSECONDS);if(response==null)continue;
                if(response.equals("!DISCONNECTED"))throw new IOException("蓝牙已断开；重新连接后可从头重试下载");
                if(response.startsWith("ERR,"))throw new IOException("设备返回 "+response);
                if(expected.equals("MAP")&&response.startsWith("MAP,"))return response;
                if(expected.equals("OK")&&(response.equals("OK")||response.startsWith("OK,")))return response;
                if(expected.equals("PONG")&&response.equals("PONG"))return response;
            }
        }catch(IOException|InterruptedException e){close();throw e;}finally{waiting=false;}
    }
    @Override public void close(){waiting=false;BluetoothSocket s=socket;socket=null;if(s!=null)try{s.close();}catch(IOException ignored){}responses.clear();responses.offer("!DISCONNECTED");}
}
