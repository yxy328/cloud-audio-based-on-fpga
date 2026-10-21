package cn.fpga.score;

import android.media.*;
import java.io.Closeable;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Immediate local sine keyboard and event replay. No Bluetooth traffic. */
public final class PhonePiano implements Closeable {
    private static final double[] LIVE_STEPS=steps(ChromaticKeys.pitches());
    private final AtomicInteger gates=new AtomicInteger();
    private final AudioTrack track;
    private volatile boolean running=true;
    private volatile double[] voiceSteps=LIVE_STEPS;
    private ScheduledExecutorService replay;
    public PhonePiano(){
        int minimum=AudioTrack.getMinBufferSize(22050,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT);
        if(minimum<0)throw new IllegalStateException("手机不支持本地音符试听");
        track=new AudioTrack.Builder().setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(new AudioFormat.Builder().setSampleRate(22050).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(Math.max(minimum,1024)).build();track.play();
        Thread audio=new Thread(()->{
            double[] phases=new double[16],levels=new double[16];
            short[] block=new short[256];
            try{while(running){int mask=gates.get();double[] steps=voiceSteps;for(int n=0;n<block.length;n++){double sum=0;for(int key=0;key<16;key++){levels[key]=(mask&(1<<key))!=0?Math.min(1,levels[key]+.02):levels[key]*.994;if(levels[key]<.0001){levels[key]=0;continue;}sum+=Math.sin(phases[key])*levels[key]*.06;phases[key]+=steps[key];if(phases[key]>=2*Math.PI)phases[key]-=2*Math.PI;}block[n]=(short)Math.max(-32768,Math.min(32767,Math.round(sum*32767)));}if(track.write(block,0,block.length,AudioTrack.WRITE_BLOCKING)<0)break;}}
            finally{track.release();}
        },"phone-piano-audio");audio.setDaemon(true);audio.start();
    }
    private static double[] steps(int[] pitches){double[] steps=new double[16];for(int key=0;key<16;key++)steps[key]=2*Math.PI*440*Math.pow(2,(pitches[key]-69)/12.0)/22050;return steps;}
    public void key(int key,boolean on){for(;;){int before=gates.get(),after=on?before|(1<<key):before&~(1<<key);if(gates.compareAndSet(before,after))return;}}
    public synchronized void liveKey(int key,boolean on){if(on){if(replay!=null)stop();voiceSteps=LIVE_STEPS;}key(key,on);}
    public synchronized void stop(){if(replay!=null){replay.shutdownNow();replay=null;}gates.set(0);voiceSteps=LIVE_STEPS;}
    public synchronized boolean replaying(){return replay!=null;}
    public synchronized void play(PhoneTake take,Runnable complete){
        stop();voiceSteps=steps(take.pitches());final ScheduledExecutorService session=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"phone-piano-replay");t.setDaemon(true);return t;});replay=session;
        for(PhoneTake.Event event:take.events())session.schedule(()->{synchronized(this){if(replay==session)key(event.key,event.on);}},event.ms,TimeUnit.MILLISECONDS);
        session.schedule(()->{synchronized(this){if(replay!=session)return;gates.set(0);replay=null;session.shutdown();}complete.run();},take.duration(),TimeUnit.MILLISECONDS);
    }
    @Override public synchronized void close(){stop();running=false;try{track.pause();}catch(IllegalStateException ignored){}}
}
