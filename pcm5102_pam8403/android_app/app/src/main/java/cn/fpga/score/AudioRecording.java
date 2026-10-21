package cn.fpga.score;

import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;

/** Receive-only FAR1 parser and bounded-memory PCM WAV writer. No playback. */
public final class AudioRecording implements Closeable {
    private final File file;
    private final int session;
    private final RandomAccessFile out;
    private final byte[] packet=new byte[530];
    private int buffered,expectedSequence;
    private long expectedSample,bytesWritten,clockHz;
    private int sampleDivisor,sampleRate;
    private boolean started,finished,complete,damaged,discontinuous;
    private String problem="";

    public AudioRecording(File file,int session)throws IOException {
        if(session<0||session>65535)throw new IllegalArgumentException("session");
        this.file=file;this.session=session;
        out=new RandomAccessFile(file,"rw");out.setLength(0);
    }
    public synchronized boolean started(){return started;}
    public synchronized boolean finished(){return finished;}
    public synchronized boolean complete(){return complete;}
    public synchronized long bytesWritten(){return bytesWritten;}
    public synchronized String problem(){return problem;}
    public synchronized File file(){return file;}
    public int session(){return session;}
    public static int crc16(byte[] bytes,int offset,int length){
        int crc=65535;
        for(int n=0;n<length;n++){
            crc^=(bytes[offset+n]&255)<<8;
            for(int b=0;b<8;b++)crc=((crc<<1)^((crc&32768)!=0?0x1021:0))&65535;
        }
        return crc;
    }
    private static int u16(byte[] b,int p){return (b[p]&255)|((b[p+1]&255)<<8);}
    private static long u32(byte[] b,int p){return (long)u16(b,p)|((long)u16(b,p+2)<<16);}
    private void fail(String message){damaged=true;if(problem.isEmpty())problem=message;}
    private void breakStream(String message){discontinuous=true;fail(message);}
    private void discard(int count){
        System.arraycopy(packet,count,packet,0,buffered-count);buffered-=count;
    }
    public synchronized void feed(byte[] bytes,int length)throws IOException {
        if(length<0||length>bytes.length)throw new IllegalArgumentException("length");
        for(int n=0;n<length&&!finished;n++){
            packet[buffered++]=bytes[n];
            while(buffered>=4&&!finished){
                if(packet[0]!='F'||packet[1]!='A'||packet[2]!='R'||packet[3]!='1'){
                    if(started)breakStream("音频数据失去帧边界");discard(1);continue;
                }
                if(buffered<16)break;
                int type=packet[4]&255,size=u16(packet,6);
                boolean valid=(type==1&&size==8)||(type==2&&size>0&&size<=512&&(size&1)==0)||(type==3&&size==4);
                if(!valid){if(started)breakStream("音频包头无效");discard(1);continue;}
                int total=18+size;
                if(buffered<total)break;
                if(crc16(packet,0,16+size)!=u16(packet,16+size)){
                    if(started)breakStream("音频CRC校验失败");discard(1);continue;
                }
                accept(type,size);
                discard(total);
            }
        }
    }
    private void accept(int type,int size)throws IOException {
        if(u16(packet,10)!=session)return; // stale packets from a previous take
        int sequence=u16(packet,8),flags=packet[5]&255;
        long index=u32(packet,12);
        if(type==1){
            if(started){breakStream("重复的录音开始包");return;}
            if(sequence!=0||index!=0||flags!=0||size!=8)throw new IOException("录音开始包无效");
            clockHz=u32(packet,16);sampleDivisor=u16(packet,20);
            if(sampleDivisor==0||packet[22]!=16||packet[23]!=1)throw new IOException("不支持的录音格式");
            sampleRate=(int)((clockHz+sampleDivisor/2)/sampleDivisor);
            if(sampleRate<8000||sampleRate>192000)throw new IOException("录音采样率无效");
            started=true;expectedSequence=1;expectedSample=0;writeHeader();out.seek(60);
            return;
        }
        if(!started)return;
        if(sequence!=expectedSequence)breakStream("录音数据包序号不连续");
        expectedSequence=(sequence+1)&65535;
        if(index!=expectedSample)breakStream("录音采样位置不连续");
        if(type==2){
            if(flags!=0)fail("FPGA录音缓存溢出，录音提前结束");
            expectedSample=index+size/2;
            if(!discontinuous){
                if(bytesWritten+size>0xffffffffL-52)throw new IOException("WAV已达到4GB格式上限");
                out.write(packet,16,size);bytesWritten+=size;
            }
        }else{
            if(u32(packet,16)!=0)fail("FPGA报告录音丢样");
            if(index!=bytesWritten/2)fail("录音结束采样数与文件不一致");
            finishFile();complete=!damaged;
        }
    }
    private void le16(int value)throws IOException {out.write(value);out.write(value>>>8);}
    private void le32(long value)throws IOException {le16((int)value);le16((int)(value>>>16));}
    private void writeHeader()throws IOException {
        out.seek(0);out.writeBytes("RIFF");le32(52+bytesWritten);out.writeBytes("WAVEfmt ");
        le32(16);le16(1);le16(1);le32(sampleRate);le32(sampleRate*2L);le16(2);le16(16);
        // Standard WAV uses integer Hz. Preserve the exact rational clock rate
        // in a private RIFF chunk; all original PCM words remain unchanged.
        out.writeBytes("srAT");le32(8);le32(clockHz);le32(sampleDivisor);
        out.writeBytes("data");le32(bytesWritten);
    }
    private void finishFile()throws IOException {
        try{
            if(started){writeHeader();out.setLength(60+bytesWritten);out.getFD().sync();}
        }catch(IOException e){fail("录音文件保存失败");throw e;}
        finally{finished=true;out.close();}
    }
    @Override public synchronized void close()throws IOException {
        if(!finished){fail("录音中断，未收到完整结束包");finishFile();}
    }
}
