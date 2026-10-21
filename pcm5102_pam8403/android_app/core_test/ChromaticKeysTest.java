package cn.fpga.score;

import java.io.ByteArrayInputStream;
import javax.sound.midi.*;

public final class ChromaticKeysTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("Chromatic key "+checks);}
    public static void main(String[] args)throws Exception{
        int[] expected={60,61,62,63,64,65,66,67,68,69,70,71,72,74,76,77};
        int[] x={0,7,10,17,20,30,37,40,47,50,57,60};
        PhoneTake take=new PhoneTake();for(int key=0;key<16;key++){
            check(ChromaticKeys.note(key)==expected[key]);check(take.pitches()[key]==expected[key]);
            if(key<12){check(ChromaticKeys.xTenths(key)==x[key]);check(ChromaticKeys.black(key)==(key==1||key==3||key==6||key==8||key==10));}
            take.down(key,90,key*20);take.up(key,key*20+10);
        }
        take.finish(320);Sequence midi=MidiSystem.getSequence(new ByteArrayInputStream(take.midi()));int next=0;
        for(Track track:midi.getTracks())for(int n=0;n<track.size();n++)if(track.get(n).getMessage() instanceof ShortMessage){ShortMessage message=(ShortMessage)track.get(n).getMessage();if(message.getCommand()==0x90)check(message.getData1()==expected[next++]);}
        check(next==16);check(ChromaticKeys.name(61).equals("C#4"));check(ChromaticKeys.name(77).equals("F5"));
        int[] copied=ChromaticKeys.pitches();copied[0]=1;check(ChromaticKeys.note(0)==60);copied=take.pitches();copied[0]=1;check(take.pitches()[0]==60);
        System.out.println("PASS ChromaticKeys: "+checks+" checks; scan/pitch geometry and all sixteen MIDI notes");
    }
}
