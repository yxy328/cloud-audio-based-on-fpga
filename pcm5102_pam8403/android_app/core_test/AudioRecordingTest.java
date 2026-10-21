package cn.fpga.score;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Random;

public final class AudioRecordingTest {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void put16(byte[] b,int p,int n){b[p]=(byte)n;b[p+1]=(byte)(n>>8);}
    private static void put32(byte[] b,int p,long n){put16(b,p,(int)n);put16(b,p+2,(int)(n>>16));}
    private static int u16(byte[] b,int p){return (b[p]&255)|((b[p+1]&255)<<8);}
    private static long u32(byte[] b,int p){return (long)u16(b,p)|((long)u16(b,p+2)<<16);}
    private static byte[] packet(int type,int flags,int seq,int session,long index,byte[] payload){
        byte[] b=new byte[18+payload.length];System.arraycopy(new byte[]{'F','A','R','1'},0,b,0,4);
        b[4]=(byte)type;b[5]=(byte)flags;put16(b,6,payload.length);put16(b,8,seq);put16(b,10,session);put32(b,12,index);
        System.arraycopy(payload,0,b,16,payload.length);
        // Independent polynomial division oracle (not the production helper).
        long dividend=65535;
        for(int n=0;n<16+payload.length;n++)for(int bit=7;bit>=0;bit--){
            long top=(dividend>>15)^((b[n]>>bit)&1);dividend=(dividend<<1)&65535;
            if((top&1)!=0)dividend^=0x1021;
        }
        put16(b,b.length-2,(int)dividend);return b;
    }
    private static byte[] start(int session){
        byte[] format=new byte[8];put32(format,0,50000000);put16(format,4,1024);format[6]=16;format[7]=1;
        return packet(1,0,0,session,0,format);
    }
    private static byte[] end(int flags,int seq,int session,int samples){
        byte[] status=new byte[4];put32(status,0,flags);return packet(3,flags,seq,session,samples,status);
    }
    private static byte[] pcm(int samples){
        byte[] b=new byte[samples*2];for(int n=0;n<samples;n++)put16(b,n*2,(n*73)^0xb631);
        return b;
    }
    private static void feed(AudioRecording r,byte[] bytes,int split)throws IOException {
        for(int offset=0;offset<bytes.length;){
            int length=Math.min(split,bytes.length-offset);r.feed(Arrays.copyOfRange(bytes,offset,offset+length),length);offset+=length;
        }
    }
    private static void wave(File f,byte[] expected)throws IOException {
        byte[] b=Files.readAllBytes(f.toPath());
        check(b.length==60+expected.length,"WAV size");
        check(new String(b,0,4,StandardCharsets.US_ASCII).equals("RIFF"),"RIFF");
        check(u32(b,4)==b.length-8,"RIFF length");check(u16(b,20)==1&&u16(b,22)==1,"PCM mono");
        check(u32(b,24)==48828&&u32(b,28)==97656,"integer WAV rate");
        check(u16(b,32)==2&&u16(b,34)==16,"PCM width");
        check(new String(b,36,4,StandardCharsets.US_ASCII).equals("srAT")&&u32(b,40)==8,"rational chunk");
        check(u32(b,44)==50000000&&u32(b,48)==1024,"exact rational sample rate");
        check(u32(b,56)==expected.length,"WAV data size");
        check(Arrays.equals(Arrays.copyOfRange(b,60,b.length),expected),"all original signed PCM words preserved");
    }
    private static void generated(File dir)throws Exception {
        check(AudioRecording.crc16("123456789".getBytes(StandardCharsets.US_ASCII),0,9)==0x29b1,"CRC known vector");
        for(int split:new int[]{1,3,16,31,530,16384}){
            File file=new File(dir,"split-"+split+".wav");AudioRecording r=new AudioRecording(file,345);
            byte[] data=pcm(777);data[123]='F';data[124]='A';data[125]='R';data[126]='1';
            feed(r,new byte[]{0,1,'F','A','R','1',7,0,-1,-1},split);feed(r,start(344),split);feed(r,start(345),split);
            int seq=1;
            for(int n=0;n<777;n+=256)feed(r,packet(2,0,seq++,345,n,Arrays.copyOfRange(data,n*2,Math.min(777,n+256)*2)),split);
            feed(r,end(0,seq,345,777),split);
            check(r.complete()&&r.finished()&&r.bytesWritten()==1554,"complete fragmented stream");wave(file,data);r.close();
        }
        // CRC damage freezes writing at the verified contiguous prefix.
        AudioRecording corrupt=new AudioRecording(new File(dir,"crc.wav"),1);feed(corrupt,start(1),1);
        byte[] block=pcm(16);feed(corrupt,packet(2,0,1,1,0,block),11);
        byte[] bad=packet(2,0,2,1,16,block);bad[20]^=1;feed(corrupt,bad,5);
        feed(corrupt,packet(2,0,3,1,32,block),7);feed(corrupt,end(0,4,1,48),3);
        check(corrupt.finished()&&!corrupt.complete()&&corrupt.bytesWritten()==32,"CRC corruption not complete");wave(corrupt.file(),block);
        AudioRecording missing=new AudioRecording(new File(dir,"gap.wav"),2);feed(missing,start(2),30);
        feed(missing,packet(2,0,2,2,16,block),30);feed(missing,end(0,3,2,32),30);
        check(missing.finished()&&!missing.complete()&&missing.bytesWritten()==0,"missing packet not compressed in time");
        AudioRecording overflow=new AudioRecording(new File(dir,"overflow.wav"),3);feed(overflow,start(3),8);
        feed(overflow,packet(2,1,1,3,0,block),9);feed(overflow,end(1,2,3,16),10);
        check(!overflow.complete()&&overflow.bytesWritten()==32,"overflow preserves valid truncated prefix");wave(overflow.file(),block);
        AudioRecording cut=new AudioRecording(new File(dir,"cut.wav"),4);feed(cut,start(4),10);
        feed(cut,packet(2,0,1,4,0,block),10);cut.close();
        check(!cut.complete()&&cut.finished(),"disconnect without END not complete");wave(cut.file(),block);
        AudioRecording stale=new AudioRecording(new File(dir,"stale.wav"),5);feed(stale,start(6),2);
        feed(stale,end(0,1,6,0),5);check(!stale.started()&&!stale.finished(),"stale nonce ignored");stale.close();
        // Exercise the real 16-bit sequence wrap without allocating a long take.
        AudioRecording wrap=new AudioRecording(new File(dir,"wrap.wav"),7);feed(wrap,start(7),26);
        for(int n=0;n<65537;n++){
            byte[] one={(byte)n,(byte)(n>>8)};feed(wrap,packet(2,0,n+1,7,n,one),20);
        }
        feed(wrap,end(0,65538,7,65537),22);check(wrap.complete()&&wrap.bytesWritten()==131074,"sequence wrap");
        Random random=new Random(8471);
        for(int n=0;n<100;n++){
            AudioRecording r=new AudioRecording(new File(dir,"random.wav"),n);byte[] data=new byte[512];random.nextBytes(data);
            feed(r,start(n),1+random.nextInt(26));feed(r,packet(2,0,1,n,0,data),1+random.nextInt(530));
            feed(r,end(0,2,n,256),1+random.nextInt(22));check(r.complete(),"random signed payload and fragmentation");wave(r.file(),data);
        }
    }
    private static void rtl(File input)throws Exception {
        File out=new File(input.getParentFile(),"audio_record_from_rtl.wav");
        AudioRecording recording=new AudioRecording(out,0x9234);
        feed(recording,Files.readAllBytes(input.toPath()),37);
        check(recording.complete()&&recording.bytesWritten()==3002,"RTL stream received completely");wave(out,pcm(1501));
        System.out.println("PASS RTL UART -> Java receiver -> WAV: 1501 samples preserved bit for bit");
    }
    private static void top(File input,File expectedFile)throws Exception {
        File out=new File(input.getParentFile(),"audio_record_from_top.wav");
        AudioRecording recording=new AudioRecording(out,4660);
        feed(recording,Files.readAllBytes(input.toPath()),113);
        java.util.List<String> lines=Files.readAllLines(expectedFile.toPath(),StandardCharsets.US_ASCII);
        byte[] expected=new byte[lines.size()*2];
        for(int n=0;n<lines.size();n++){
            int value=Integer.parseInt(lines.get(n));expected[2*n]=(byte)value;expected[2*n+1]=(byte)(value>>8);
        }
        check(recording.complete()&&recording.bytesWritten()==expected.length,"top live stream complete");
        wave(out,expected);
        System.out.println("PASS top I2S -> 2Mbps UART -> Java receiver -> WAV: "+lines.size()+" samples bit-exact");
    }
    public static void main(String[] args)throws Exception {
        if(args.length==2)top(new File(args[0]),new File(args[1]));
        else if(args.length>0)rtl(new File(args[0]));
        else {File base=new File("build/audio-record-test");base.mkdirs();generated(Files.createTempDirectory(base.toPath(),"run-").toFile());}
        System.out.println("PASS AudioRecording: "+checks+" checks");
    }
}
