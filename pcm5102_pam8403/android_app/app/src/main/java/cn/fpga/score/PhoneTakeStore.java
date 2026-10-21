package cn.fpga.score;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

/** A new file per save; atomic rename preserves the old file on write failure. */
public final class PhoneTakeStore {
    // PTK1 encoded scan indices with this fixed scale, not absolute MIDI notes.
    private static final int[] PTK1_PITCHES={60,62,64,65,67,69,71,72,74,76,77,79,81,83,84,86};
    public static final class Entry {
        public final String id,name;public final int duration,notes;
        private final int[] pitches;
        Entry(String id,String name,int duration,int notes,int[] pitches){this.id=id;this.name=name;this.duration=duration;this.notes=notes;this.pitches=pitches.clone();}
        public String toString(){return name+" · "+notes+"音符 · "+String.format(Locale.ROOT,"%.2f秒",duration/1000.0);}
    }
    private final File directory;
    public PhoneTakeStore(File directory)throws IOException {this.directory=directory;if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建手机录制目录");}
    private File file(String id)throws IOException {try{UUID.fromString(id);}catch(IllegalArgumentException e){throw new IOException("录制编号无效",e);}return new File(directory,"phone-"+id+".take");}
    private static String name(String name)throws IOException {String value=name==null?"":name.trim();if(value.isEmpty()||value.length()>80)throw new IOException("录制名称须为1～80个字符");return value;}
    public Entry save(String name,PhoneTake take)throws IOException {return write(UUID.randomUUID().toString(),name(name),take);}
    public Entry rename(Entry entry,String name)throws IOException {return write(entry.id,name(name),load(entry));}
    private Entry write(String id,String name,PhoneTake take)throws IOException {
        if(!take.finished()||take.notes()==0)throw new IOException("请先停止手机录制，再保存");
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        out.writeInt(0x50544b32);out.writeUTF(name);out.writeInt(take.duration());out.writeInt(take.notes());List<PhoneTake.Event> events=take.events();out.writeInt(events.size());
        for(int pitch:take.pitches())out.writeByte(pitch);
        for(PhoneTake.Event event:events){out.writeInt(event.ms);out.writeByte(event.key);out.writeBoolean(event.on);out.writeByte(event.velocity);}out.flush();
        CRC32 crc=new CRC32();crc.update(bytes.toByteArray());out.writeInt((int)crc.getValue());out.flush();
        File staged=File.createTempFile(".phone-",".tmp",directory);
        try{try(FileOutputStream stream=new FileOutputStream(staged)){bytes.writeTo(stream);stream.getFD().sync();}
            Files.move(staged.toPath(),file(id).toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
            return new Entry(id,name,take.duration(),take.notes(),take.pitches());
        }finally{if(staged.exists())staged.delete();}
    }
    private DataInputStream read(String id)throws IOException {
        File source=file(id);if(source.length()<20||source.length()>150000)throw new IOException("手机录制文件长度无效");byte[] bytes=Files.readAllBytes(source.toPath());
        CRC32 crc=new CRC32();crc.update(bytes,0,bytes.length-4);DataInputStream tail=new DataInputStream(new ByteArrayInputStream(bytes,bytes.length-4,4));
        if((int)crc.getValue()!=tail.readInt())throw new IOException("手机录制文件校验失败");DataInputStream in=new DataInputStream(new ByteArrayInputStream(bytes,0,bytes.length-4));
        return in;
    }
    private Entry header(String id,DataInputStream in)throws IOException {
        int version=in.readInt();if(version!=0x50544b31&&version!=0x50544b32)throw new IOException("手机录制版本不支持");
        String name=name(in.readUTF());int duration=in.readInt(),notes=in.readInt(),count=in.readInt();
        int[] pitches=PTK1_PITCHES.clone();if(version==0x50544b32)for(int key=0;key<16;key++){pitches[key]=in.readUnsignedByte();if(pitches[key]>127)throw new IOException("手机录制音高无效");}
        if(duration<0||notes<1||notes>PhoneTake.MAX_NOTES||count!=notes*2||in.available()!=count*7)throw new IOException("手机录制内容不完整");
        return new Entry(id,name,duration,notes,pitches);
    }
    public PhoneTake load(Entry entry)throws IOException {
        DataInputStream in=read(entry.id);Entry meta=header(entry.id,in);List<PhoneTake.Event> events=new ArrayList<>();
        while(in.available()!=0){int ms=in.readInt(),key=in.readUnsignedByte(),on=in.readUnsignedByte(),velocity=in.readUnsignedByte();if(on>1||(! (on==1)&&velocity!=0))throw new IOException("手机录制事件标志无效");events.add(new PhoneTake.Event(ms,key,on==1,velocity));}
        return PhoneTake.restore(events,meta.duration,meta.notes,meta.pitches);
    }
    public List<Entry> list()throws IOException {
        List<Entry> entries=new ArrayList<>();File[] files=directory.listFiles();if(files==null)throw new IOException("无法读取手机录制目录");
        Arrays.sort(files,(a,b)->Long.compare(b.lastModified(),a.lastModified()));
        for(File source:files){String filename=source.getName();if(!filename.matches("phone-[0-9a-f-]{36}\\.take"))continue;String id=filename.substring(6,42);try{DataInputStream in=read(id);entries.add(header(id,in));}catch(IOException ignored){/* Keep unreadable originals; do not silently delete them. */}}
        return entries;
    }
    public void delete(Entry entry)throws IOException {Files.delete(file(entry.id).toPath());}
}
