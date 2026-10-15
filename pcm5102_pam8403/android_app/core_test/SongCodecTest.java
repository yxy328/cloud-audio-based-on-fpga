package cn.fpga.score;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class SongCodecTest {
    private static int checks;
    private static void eq(long a,long b){checks++;if(a!=b)throw new AssertionError(a+" != "+b);}
    private interface Attempt {void run()throws Exception;}
    private static void fails(Attempt a,String contains)throws Exception{checks++;try{a.run();}catch(Exception e){if(e.getMessage().contains(contains))return;throw new AssertionError(e);}throw new AssertionError("Expected rejection: "+contains);}
    private static byte[] bytes(int... data){byte[] b=new byte[data.length];for(int i=0;i<data.length;i++)b[i]=(byte)data[i];return b;}
    private static byte[] midi(int format,int ppq,byte[]...tracks)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();DataOutputStream o=new DataOutputStream(b);o.writeBytes("MThd");o.writeInt(6);o.writeShort(format);o.writeShort(tracks.length);o.writeShort(ppq);for(byte[] t:tracks){o.writeBytes("MTrk");o.writeInt(t.length);o.write(t);}return b.toByteArray();}
    public static void main(String[] args)throws Exception {
        SongCodec.Song csv=SongCodec.csv("demo","pitches,duration_ms\n60+64+67,500\nREST,250\n60,70000".getBytes(StandardCharsets.UTF_8));
        eq(csv.events.size(),4);eq(csv.events.get(0).mask,145);eq(csv.events.get(1).mask,0);eq(csv.events.get(2).durationMs,60000);eq(csv.events.get(3).durationMs,10000);eq(csv.durationMs(),70750);
        csv.checkMapping(new int[]{60,62,64,65,67,69,71});fails(()->csv.checkMapping(new int[]{60,61,62,63,64,65,66}),"缺少");
        if(!csv.commands().get(1).equals("SONG_CHORD,0,145,500"))throw new AssertionError();checks++;
        // Two tracks, simultaneous C+E chord, default 120 BPM -> 500ms; rest 250ms;
        // then tempo 1,000,000us/qn -> 1,000ms G. Explicit status plus running status.
        byte[] conductor=bytes(0,255,81,3,7,161,32,0x85,0x50,255,81,3,15,66,64,0,255,47,0);
        byte[] music=bytes(0,144,60,100,0,64,100,0x83,0x60,128,60,0,0,64,0,0x81,0x70,144,67,100,0x83,0x60,128,67,0,0,255,47,0);
        SongCodec.Song m=SongCodec.midi("chord.mid",midi(1,480,conductor,music));
        eq(m.events.size(),3);eq(m.events.get(0).mask,17);eq(m.events.get(0).durationMs,500);eq(m.events.get(1).mask,0);eq(m.events.get(1).durationMs,250);eq(m.events.get(2).mask,128);eq(m.events.get(2).durationMs,1000);
        // Consecutive repeated notes remain separate guidance records.
        byte[] repeated=bytes(0,144,60,1,0x83,0x60,128,60,0,0,144,60,1,0x83,0x60,128,60,0,0,255,47,0);
        eq(SongCodec.midi("repeat.mid",midi(0,480,repeated)).events.size(),2);
        fails(()->SongCodec.midi("range.mid",midi(0,480,bytes(0,144,59,1,0x83,0x60,128,59,0,0,255,47,0))),"60..72");
        fails(()->SongCodec.midi("drums.mid",midi(0,480,bytes(0,153,60,1,0x83,0x60,137,60,0,0,255,47,0))),"鼓轨");
        fails(()->SongCodec.midi("smpte.mid",midi(0,0xe728,music)),"SMPTE");
        fails(()->SongCodec.midi("cut.mid",Arrays.copyOf(midi(0,480,music),25)),"截断");
        fails(()->SongCodec.midi("held.mid",midi(0,480,bytes(0,144,60,1,0,255,47,0))),"未关闭");
        fails(()->SongCodec.midi("sustain.mid",midi(0,480,bytes(0,176,64,127,0,255,47,0))),"延音踏板");
        StringBuilder tooMany=new StringBuilder();for(int i=0;i<129;i++)tooMany.append("60,500\n");fails(()->SongCodec.csv("long",tooMany.toString().getBytes(StandardCharsets.UTF_8)),"128");
        // Tempo changes inside a held note alter its duration without splitting it.
        byte[] tempoHeld=bytes(0,144,60,1,0x81,0x70,255,81,3,15,66,64,0x81,0x70,128,60,0,0,255,47,0);
        SongCodec.Song h=SongCodec.midi("tempo.mid",midi(0,480,tempoHeld));eq(h.events.size(),1);eq(h.events.get(0).durationMs,750);
        byte[] trailing=bytes(0,144,60,1,0x83,0x60,128,60,0,0x83,0x60,255,47,0);
        SongCodec.Song tail=SongCodec.midi("tail.mid",midi(0,480,trailing));eq(tail.events.size(),2);eq(tail.events.get(1).mask,0);eq(tail.events.get(1).durationMs,500);
        eq(SongCodec.parseMapping("MAP,60,62,64,65,67,69,71")[6],71);
        fails(()->SongCodec.parseMapping("MAP,60,62"),"格式");
        System.out.println("PASS SongCodec: "+checks+" assertions");
    }
}
