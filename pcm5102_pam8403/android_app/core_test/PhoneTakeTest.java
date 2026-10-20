package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.*;
public final class PhoneTakeTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("Phone take check "+checks);}
    private static PhoneTake example(){PhoneTake take=new PhoneTake();take.down(0,100,0);take.down(4,80,20);take.up(0,150);take.finish(250);return take;}
    public static void main(String[] args)throws Exception {
        PhoneTake take=example();check(take.finished()&&take.notes()==2&&take.events().size()==4&&take.duration()==250);
        Sequence midi=MidiSystem.getSequence(new ByteArrayInputStream(take.midi()));check(midi.getResolution()==500&&midi.getTickLength()==250&&midi.getMicrosecondLength()==250000);
        boolean on=false,off=false;for(Track track:midi.getTracks())for(int n=0;n<track.size();n++){MidiEvent event=track.get(n);if(event.getMessage() instanceof ShortMessage){ShortMessage message=(ShortMessage)event.getMessage();if(message.getCommand()==0x90&&message.getData1()==60)on=event.getTick()==0&&message.getData2()==100;if(message.getCommand()==0x80&&message.getData1()==60)off=event.getTick()==150;}}check(on&&off);
        File folder=Files.createTempDirectory("phone-takes-").toFile();PhoneTakeStore store=new PhoneTakeStore(folder);List<PhoneTakeStore.Entry> created=new ArrayList<>();
        for(int n=0;n<25;n++)created.add(store.save("演奏 "+n,take));check(store.list().size()==25);check(store.load(created.get(0)).events().size()==4);
        PhoneTakeStore reopened=new PhoneTakeStore(folder);check(reopened.list().size()==25&&reopened.load(created.get(24)).notes()==2);
        PhoneTakeStore.Entry renamed=store.rename(created.get(0),"新名称");check(renamed.id.equals(created.get(0).id)&&store.list().size()==25&&store.list().stream().anyMatch(e->e.name.equals("新名称")));
        try{store.save("",take);throw new AssertionError();}catch(IOException expected){check(take.events().size()==4&&store.list().size()==25);}
        File denied=File.createTempFile("not-a-directory-",".tmp");try{new PhoneTakeStore(denied);throw new AssertionError();}catch(IOException expected){check(take.finished()&&take.notes()==2);}check(denied.delete());
        store.delete(created.get(24));check(store.list().size()==24);try{store.load(created.get(24));throw new AssertionError();}catch(IOException expected){check(true);}
        File corrupted=new File(folder,"phone-"+created.get(1).id+".take");byte[] bytes=Files.readAllBytes(corrupted.toPath());bytes[bytes.length-7]^=1;Files.write(corrupted.toPath(),bytes);try{store.load(created.get(1));throw new AssertionError();}catch(IOException expected){check(corrupted.exists());}check(store.list().size()==23);
        PhoneTake limit=new PhoneTake();for(int n=0;n<10000;n++){check(limit.down(n%16,100,n*2));limit.up(n%16,n*2+1);}check(!limit.down(0,100,20001));limit.finish(20002);PhoneTakeStore.Entry maximum=store.save("10000 音符",limit);check(store.load(maximum).notes()==10000);
        PhoneTake longSilence=new PhoneTake();longSilence.down(0,100,0);longSilence.up(0,1);longSilence.finish(Integer.MAX_VALUE);check(MidiSystem.getSequence(new ByteArrayInputStream(longSilence.midi())).getTickLength()==Integer.MAX_VALUE);
        for(File source:folder.listFiles())check(source.delete());check(folder.delete());
        System.out.println("PASS PhoneTake: "+checks+" checks; local note timing/hold/velocity, standard MIDI, 25 independent saves/reopen/rename/delete, CRC, failure preservation, 10000-note bound and long silence");
    }
}
