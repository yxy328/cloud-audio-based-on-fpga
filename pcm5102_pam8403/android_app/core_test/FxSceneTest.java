package cn.fpga.score;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public final class FxSceneTest {
    private static int checks;
    private static void yes(boolean ok){checks++;if(!ok)throw new AssertionError("Scene check "+checks);}
    private static FxState state(int mask,int settings,int mix){return FxState.parse(String.format(Locale.ROOT,"EFFECT3,%X,%02X,%03X,7,FF,888",mask,settings,mix));}
    public static void main(String[] args)throws Exception {
        Path directory=Files.createTempDirectory("fx-scene-test-");File file=directory.resolve("scenes.bin").toFile();
        FxSceneStore store=new FxSceneStore(file);
        yes(store.list().size()==4);yes(!file.exists());
        FxScene scene=store.save("自定义空间",state(4,0x52,0x321));
        yes(scene.mask==4&&scene.mix==0x321&&scene.settings==0x52); // Never saves 7/FF/888 actual overrides.
        yes(new FxSceneStore(file).list().size()==5);
        store.rename(scene,"我的混响");yes(store.list().get(4).name.equals("我的混响"));
        yes(store.list().get(4).mix==0x321);store.delete(scene);yes(store.list().size()==4);
        for(FxScene candidate:new ArrayList<>(store.list()))store.delete(candidate);
        yes(store.list().isEmpty());yes(new FxSceneStore(file).list().isEmpty()); // Deleted candidates do not reappear.
        for(String name:new String[]{"", " ", "a\nb",String.join("",Collections.nCopies(41,"字"))}){
            try{store.save(name,state(0,0,0));throw new AssertionError("bad name");}catch(IllegalArgumentException expected){checks++;}
        }
        FxScene dry=store.save("原声",state(0,0x52,0x444));
        List<String> commands=new ArrayList<>();
        FxScene.Result good=dry.apply((command,reply)->{commands.add(command);return reply.equals("OK")?"OK":"EFFECT3,0,52,444,7,FF,888";});
        yes(good.confirmed&&good.observed.appliedMask==7); // Config acknowledged even if TAKE overrides actual.
        yes(commands.equals(Arrays.asList("EFFECT,3,0,82,1092","EFFECT,?")));
        FxScene.Result mismatch=dry.apply((command,reply)->reply.equals("OK")?"OK":"EFFECT3,1,52,444,1,52,444");
        yes(!mismatch.confirmed&&mismatch.observed.mask==1);
        FxScene.Result rejected=dry.apply((command,reply)->{if(reply.equals("OK"))throw new IOException("ERR,STATE");return "EFFECT3,4,52,444,4,52,444";});
        yes(!rejected.confirmed&&rejected.observed.mask==4&&rejected.error.contains("ERR,STATE"));
        FxScene.Result offline=dry.apply((command,reply)->{throw new IOException("disconnected");});
        yes(!offline.confirmed&&offline.observed==null);
        final int[] attempt={0};
        FxScene.Result unread=dry.apply((command,reply)->{if(attempt[0]++==0)return "OK";throw new IOException("read timeout");});
        yes(!unread.confirmed&&unread.observed==null&&attempt[0]==3);
        FxScene.Result corrupt=dry.apply((command,reply)->reply.equals("OK")?"OK":"EFFECT3,0,52,449,0,00,000");
        yes(!corrupt.confirmed&&corrupt.observed==null);
        for(int n=store.list().size();n<FxSceneStore.MAX_SCENES;n++)store.save("场景"+n,state(n%8,n%256,(n%9)*273));
        yes(store.list().size()==64);
        byte[] intact=Files.readAllBytes(file.toPath());
        try{store.save("超限",state(0,0,0));throw new AssertionError("capacity");}catch(IOException expected){checks++;}
        yes(Arrays.equals(intact,Files.readAllBytes(file.toPath())));
        byte[] bad=intact.clone();bad[10]^=1;Files.write(file.toPath(),bad);
        try{store.list();throw new AssertionError("CRC");}catch(IOException expected){checks++;}
        try{store.save("保护原文件",state(0,0,0));throw new AssertionError("overwrite corrupt");}catch(IOException expected){checks++;}
        yes(Arrays.equals(bad,Files.readAllBytes(file.toPath())));
        for(int mask=0;mask<8;mask++)for(int wet=0;wet<=8;wet++){
            FxScene s=FxScene.capture("roundtrip","测试",state(mask,mask*31,wet*273));
            yes(s.matches(state(mask,mask*31,wet*273)));yes(!s.matches(state(mask^1,mask*31,wet*273)));
        }
        Files.delete(file.toPath());Files.delete(directory);
        System.out.println("PASS local FX scenes, CRC/atomic persistence, configuration vs overrides, rejection/readback/timeout: "+checks+" checks");
    }
}
