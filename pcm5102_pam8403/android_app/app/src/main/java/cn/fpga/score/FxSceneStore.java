package cn.fpga.score;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

/** Small versioned local catalogue; a corrupt catalogue is preserved and write-protected. */
public final class FxSceneStore {
    private final File file;
    public static final int MAX_SCENES=64;
    public FxSceneStore(File file){this.file=file;}
    public List<FxScene> list()throws IOException {
        if(!file.exists())return candidates();
        if(file.length()<12||file.length()>32768)throw new IOException("场景文件长度无效，原文件已保留");
        byte[] bytes=Files.readAllBytes(file.toPath());CRC32 crc=new CRC32();crc.update(bytes,0,bytes.length-4);
        DataInputStream tail=new DataInputStream(new ByteArrayInputStream(bytes,bytes.length-4,4));
        if(tail.readInt()!=(int)crc.getValue())throw new IOException("场景文件校验失败，原文件已保留");
        DataInputStream in=new DataInputStream(new ByteArrayInputStream(bytes,0,bytes.length-4));
        if(in.readInt()!=0x46585331)throw new IOException("场景文件版本不支持");
        int count=in.readInt();if(count<0||count>MAX_SCENES)throw new IOException("场景数量无效");
        List<FxScene> result=new ArrayList<>();Set<String> ids=new HashSet<>();
        try{for(int n=0;n<count;n++){
            FxScene s=new FxScene(in.readUTF(),in.readUTF(),in.readUnsignedByte(),in.readUnsignedByte(),in.readUnsignedShort());
            if(!ids.add(s.id))throw new IOException("场景编号重复");result.add(s);
        }}catch(IllegalArgumentException e){throw new IOException("场景参数无效",e);}
        if(in.available()!=0)throw new IOException("场景文件有多余数据");return result;
    }
    public FxScene save(String name,FxState confirmed)throws IOException {
        List<FxScene> all=list();if(all.size()>=MAX_SCENES)throw new IOException("最多保存 64 个场景，请先删除一个");
        FxScene s=FxScene.capture(UUID.randomUUID().toString(),name,confirmed);all.add(s);write(all);return s;
    }
    public void rename(FxScene scene,String name)throws IOException {
        List<FxScene> all=list();int index=index(all,scene);all.set(index,all.get(index).rename(name));write(all);
    }
    public void delete(FxScene scene)throws IOException {List<FxScene> all=list();all.remove(index(all,scene));write(all);}
    private static int index(List<FxScene> all,FxScene scene)throws IOException {
        for(int n=0;n<all.size();n++)if(all.get(n).id.equals(scene.id))return n;
        throw new IOException("场景已不存在，请刷新列表");
    }
    private void write(List<FxScene> all)throws IOException {
        File directory=file.getAbsoluteFile().getParentFile();
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建场景目录");
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        out.writeInt(0x46585331);out.writeInt(all.size());
        for(FxScene s:all){out.writeUTF(s.id);out.writeUTF(s.name);out.writeByte(s.mask);out.writeByte(s.settings);out.writeShort(s.mix);}out.flush();
        CRC32 crc=new CRC32();crc.update(bytes.toByteArray());out.writeInt((int)crc.getValue());out.flush();
        File staged=File.createTempFile(".scenes-",".tmp",directory);
        try{try(FileOutputStream stream=new FileOutputStream(staged)){bytes.writeTo(stream);stream.getFD().sync();}
            Files.move(staged.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }finally{if(staged.exists())staged.delete();}
    }
    /** Starting points awaiting hardware listening; editable and deletable like saved scenes. */
    private static List<FxScene> candidates(){return new ArrayList<>(Arrays.asList(
        new FxScene("dry","原声 · 候选",0,0x52,0x444),
        new FxScene("space","轻空间 · 待听音",4,0x12,0x300),
        new FxScene("chorus","温暖合唱 · 待听音",5,0x51,0x203),
        new FxScene("echo","节奏回声 · 待听音",2,0x18,0x040)));}
}
