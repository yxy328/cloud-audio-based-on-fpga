package cn.fpga.score;

import java.io.*;
import java.util.*;

/** Local phone keyboard events. Independent of FPGA Flash and original PCM. */
public final class PhoneTake {
    public static final int MAX_NOTES=10000;
    private final int[] pitches;
    public PhoneTake(){this(ChromaticKeys.pitches());}
    PhoneTake(int[] pitches){
        if(pitches.length!=16)throw new IllegalArgumentException("手机录制音高表无效");this.pitches=pitches.clone();
        for(int pitch:pitches)if(pitch<0||pitch>127)throw new IllegalArgumentException("手机录制音高无效");
    }
    public int[] pitches(){return pitches.clone();}
    public static final class Event {
        public final int ms,key,velocity;public final boolean on;
        Event(int ms,int key,boolean on,int velocity){this.ms=ms;this.key=key;this.on=on;this.velocity=velocity;}
    }
    private final List<Event> events=new ArrayList<>();
    private int active,lastTime,notes,duration;
    private boolean finished;
    public int notes(){return notes;}public int duration(){return duration;}public boolean finished(){return finished;}
    public List<Event> events(){return Collections.unmodifiableList(new ArrayList<>(events));}
    public boolean down(int key,int velocity,int ms){
        check(key,ms);if(velocity<1||velocity>127)throw new IllegalArgumentException("力度无效");
        if((active&(1<<key))!=0)return true;if(notes>=MAX_NOTES)return false;
        events.add(new Event(ms,key,true,velocity));active|=1<<key;notes++;lastTime=ms;return true;
    }
    public void up(int key,int ms){check(key,ms);if((active&(1<<key))==0)return;events.add(new Event(ms,key,false,0));active&=~(1<<key);lastTime=ms;}
    private void check(int key,int ms){if(finished||key<0||key>=16||ms<lastTime)throw new IllegalArgumentException("手机录制事件无效");}
    public void finish(int ms){
        if(finished)return;if(ms<lastTime)throw new IllegalArgumentException("录制结束时间无效");
        for(int key=0;key<16;key++)if((active&(1<<key))!=0)up(key,ms);
        duration=ms;finished=true;
    }
    static PhoneTake restore(List<Event> source,int duration,int expectedNotes,int[] pitches)throws IOException {
        PhoneTake take=new PhoneTake(pitches);
        try{for(Event event:source){int before=take.events.size();if(event.on){if(!take.down(event.key,event.velocity,event.ms))throw new IOException("手机录制超过10000个音符");}else take.up(event.key,event.ms);if(take.events.size()!=before+1)throw new IOException("手机录制键态不完整");}
            if(take.active!=0||take.notes!=expectedNotes)throw new IOException("手机录制未完整结束");take.finish(duration);return take;
        }catch(IllegalArgumentException e){throw new IOException("手机录制时间线损坏",e);}
    }
    private static void vlq(OutputStream out,int value)throws IOException {
        int packed=value&127;while((value>>>=7)!=0)packed=(packed<<8)|((value&127)|128);
        for(;;){out.write(packed&255);if((packed&128)==0)return;packed>>>=8;}
    }
    private static void delta(OutputStream out,int ms)throws IOException {
        // SMF delta times have four VLQ bytes. Empty text events bridge a
        // longer silent interval without truncating the recorded duration.
        while(ms>0x0fffffff){vlq(out,0x0fffffff);out.write(new byte[]{(byte)255,1,0});ms-=0x0fffffff;}vlq(out,ms);
    }
    public byte[] midi()throws IOException {
        if(!finished||notes==0)throw new IOException("请先停止手机录制，并至少录入一个音符");
        ByteArrayOutputStream track=new ByteArrayOutputStream();track.write(new byte[]{0,(byte)255,81,3,7,(byte)161,32,0,(byte)192,0});
        int previous=0;for(Event event:events){delta(track,event.ms-previous);track.write(event.on?0x90:0x80);track.write(pitches[event.key]);track.write(event.velocity);previous=event.ms;}
        delta(track,duration-previous);track.write(new byte[]{(byte)255,47,0});
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        out.writeInt(0x4d546864);out.writeInt(6);out.writeShort(0);out.writeShort(1);out.writeShort(500);out.writeInt(0x4d54726b);out.writeInt(track.size());track.writeTo(out);return bytes.toByteArray();
    }
}
