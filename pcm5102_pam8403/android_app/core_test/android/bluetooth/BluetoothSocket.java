package android.bluetooth;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** JVM-only fake. Not included in the APK. */
public final class BluetoothSocket implements Closeable {
    private final BlockingQueue<Integer> input=new LinkedBlockingQueue<>();
    public Consumer<String> onCommand;
    private volatile boolean connected;
    public void connect()throws IOException{connected=true;}
    public boolean isConnected(){return connected;}
    public void feed(String line){for(byte b:line.getBytes(StandardCharsets.US_ASCII))input.offer(b&255);}
    public void feed(byte[] bytes){for(byte b:bytes)input.offer(b&255);}
    public void eof(){input.offer(-1);}
    public InputStream getInputStream(){return new InputStream(){public int read()throws IOException{try{return input.take();}catch(InterruptedException e){throw new IOException(e);}}};}
    public OutputStream getOutputStream(){return new ByteArrayOutputStream(){@Override public void flush()throws IOException{String line=new String(toByteArray(),StandardCharsets.US_ASCII);reset();if(onCommand!=null)onCommand.accept(line);}};}
    public void close()throws IOException{connected=false;input.offer(-1);}
}
