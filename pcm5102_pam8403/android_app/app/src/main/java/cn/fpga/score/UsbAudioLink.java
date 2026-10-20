package cn.fpga.score;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.SystemClock;
import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.hoho.android.usbserial.driver.UsbSerialProber;
import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** USB receives only; HC-05 owns all FPGA control commands. */
public final class UsbAudioLink implements Closeable {
    public interface Listener {
        void state(String text);
        void progress(long bytes,boolean started);
        void result(AudioRecording recording);
        void failure(String reason);
    }
    public static final class Choice {
        final UsbSerialDriver driver;
        final int port;
        Choice(UsbSerialDriver driver,int port){this.driver=driver;this.port=port;}
        @Override public String toString(){
            UsbDevice d=driver.getDevice();
            return driver.getClass().getSimpleName()+" · "+String.format("%04X:%04X",d.getVendorId(),d.getProductId())+" · 端口 "+port;
        }
    }
    private final Context context;
    private final UsbManager manager;
    private final Listener listener;
    private final String permissionAction;
    private final ExecutorService opener=Executors.newSingleThreadExecutor();
    private final BroadcastReceiver receiver;
    private volatile UsbSerialPort port;
    private Choice pending;
    private AudioRecording recording;
    private boolean destroyed;
    private volatile int openGeneration;

    public UsbAudioLink(Context context,Listener listener){
        this.context=context.getApplicationContext();this.listener=listener;
        manager=(UsbManager)this.context.getSystemService(Context.USB_SERVICE);
        permissionAction=this.context.getPackageName()+".AUDIO_USB_PERMISSION";
        receiver=new BroadcastReceiver(){@Override public void onReceive(Context c,Intent intent){
            UsbDevice device=intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if(permissionAction.equals(intent.getAction())){
                Choice choice;
                synchronized(UsbAudioLink.this){
                    choice=pending;
                    if(choice==null||device==null||device.getDeviceId()!=choice.driver.getDevice().getDeviceId())return;
                    pending=null;
                }
                if(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED,false))connect(choice);
                else listener.failure("USB访问未获授权");
            }else if(UsbManager.ACTION_USB_DEVICE_DETACHED.equals(intent.getAction())){
                UsbSerialPort current=port;
                if(current!=null&&device!=null&&current.getDevice().getDeviceId()==device.getDeviceId())
                    failLink(current,openGeneration,"USB录音模块已断开");
            }
        }};
        IntentFilter filter=new IntentFilter(permissionAction);filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if(Build.VERSION.SDK_INT>=33)this.context.registerReceiver(receiver,filter,Context.RECEIVER_NOT_EXPORTED);
        else this.context.registerReceiver(receiver,filter);
    }
    public List<Choice> choices(){
        List<Choice> result=new ArrayList<>();
        if(manager!=null)for(UsbSerialDriver driver:UsbSerialProber.getDefaultProber().findAllDrivers(manager))
            for(int n=0;n<driver.getPorts().size();n++)result.add(new Choice(driver,n));
        return result;
    }
    public boolean connected(){return port!=null;}
    public void connect(Choice choice){
        final int generation;
        synchronized(this){
            if(destroyed)return;
            if(recording!=null){listener.failure("请先停止当前音频录制");return;}
            if(manager==null){listener.failure("手机不支持USB Host");return;}
            generation=++openGeneration;
            if(!manager.hasPermission(choice.driver.getDevice())){
                pending=choice;
                int flags=PendingIntent.FLAG_UPDATE_CURRENT|(Build.VERSION.SDK_INT>=31?PendingIntent.FLAG_MUTABLE:0);
                PendingIntent permission=PendingIntent.getBroadcast(context,0,new Intent(permissionAction).setPackage(context.getPackageName()),flags);
                manager.requestPermission(choice.driver.getDevice(),permission);return;
            }
        }
        opener.execute(()->open(choice,generation));
    }
    private void open(Choice choice,int generation){
        UsbSerialPort candidate=null;
        try{
            UsbSerialPort previous;
            synchronized(this){if(destroyed||generation!=openGeneration)return;previous=port;port=null;}
            if(previous!=null)previous.close();
            UsbDeviceConnection connection=manager.openDevice(choice.driver.getDevice());
            if(connection==null)throw new IOException("无法打开USB模块");
            candidate=choice.driver.getPorts().get(choice.port);
            // Keep USB requests queued while CRC/file work runs. Upstream
            // warns that timed bulkTransfer can lose continuous high-rate data.
            candidate.setReadQueue(32,4096);
            candidate.open(connection);
            if(!candidate.getSupportedFlowControl().contains(UsbSerialPort.FlowControl.RTS_CTS))
                throw new IOException("此驱动不支持所需RTS/CTS流控，请使用支持2Mbps的CP2102N或FTDI模块");
            candidate.setParameters(2000000,8,UsbSerialPort.STOPBITS_1,UsbSerialPort.PARITY_NONE);
            candidate.setDTR(true);candidate.setRTS(true);
            candidate.setFlowControl(UsbSerialPort.FlowControl.RTS_CTS);
            candidate.purgeHwBuffers(true,true);
            final UsbSerialPort active=candidate;
            synchronized(this){
                if(destroyed||generation!=openGeneration){candidate.close();return;}
                port=active;
            }
            listener.state("USB录音通道已打开：2Mbps / 8N1 / RTS-CTS；实际完整性以录音校验结果为准");
            Thread reader=new Thread(()->read(active,generation),"FPGA-audio-USB");reader.setDaemon(true);reader.start();
        }catch(Exception e){
            if(candidate!=null)try{candidate.close();}catch(IOException ignored){}
            synchronized(this){if(destroyed||generation!=openGeneration)return;}
            listener.failure("USB连接失败："+e.getMessage());
        }
    }
    private void read(UsbSerialPort active,int generation){
        byte[] buffer=new byte[active.getReadQueueBufferSize()];long lastUpdate=0;boolean wasStarted=false;
        try{
            while(port==active&&generation==openGeneration){
                // timeout=0 uses UsbRequest/requestWait; closing the port
                // cancels pending requests and unblocks this reader.
                int length=active.read(buffer,0);
                if(length<=0)continue;
                AudioRecording current;
                synchronized(this){
                    if(port!=active||generation!=openGeneration)return;
                    current=recording;
                    if(current!=null)current.feed(buffer,length);
                    if(current!=null&&current.finished())recording=null;
                }
                if(current==null)continue;
                if(current.finished()){
                    wasStarted=false;listener.result(current);
                }else{
                    boolean started=current.started();long now=SystemClock.elapsedRealtime();
                    if(started!=wasStarted||now-lastUpdate>=250){listener.progress(current.bytesWritten(),started);lastUpdate=now;wasStarted=started;}
                }
            }
        }catch(Exception e){failLink(active,generation,"USB音频接收失败："+e.getMessage());}
    }
    public synchronized void begin(File file,int session)throws IOException {
        if(port==null)throw new IOException("请先连接USB录音模块");
        if(recording!=null)throw new IOException("上一段音频仍在录制或排空");
        recording=new AudioRecording(file,session);
    }
    public synchronized boolean started(){return recording!=null&&recording.started();}
    public void cancel(){
        AudioRecording current;
        synchronized(this){current=recording;recording=null;}
        if(current!=null){
            try{current.close();}catch(IOException e){listener.failure("录音文件关闭失败："+e.getMessage());}
            if(current.started())listener.result(current);
        }
    }
    private void failLink(UsbSerialPort active,int generation,String reason){
        synchronized(this){if(port!=active||generation!=openGeneration)return;port=null;}
        try{active.close();}catch(IOException ignored){}
        // Report link loss first so the UI can still identify an active take
        // and queue AREC_ABORT before the incomplete-file result is posted.
        listener.failure(reason);cancel();
    }
    @Override public void close(){
        UsbSerialPort current;
        synchronized(this){current=port;port=null;pending=null;++openGeneration;}
        if(current!=null)try{current.close();}catch(IOException ignored){}
        cancel();
    }
    public void destroy(){
        synchronized(this){destroyed=true;}
        close();context.unregisterReceiver(receiver);opener.shutdownNow();
    }
}
