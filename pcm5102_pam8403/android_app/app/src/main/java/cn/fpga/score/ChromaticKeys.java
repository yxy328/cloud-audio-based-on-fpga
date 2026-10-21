package cn.fpga.score;

public final class ChromaticKeys {
    private static final int[] NOTES={60,61,62,63,64,65,66,67,68,69,70,71,72,74,76,77};
    private static final int[] WHITE={0,2,4,5,7,9,11},BLACK={1,3,6,8,10},GAPS={1,2,4,5,6};
    private ChromaticKeys(){}
    public static int[] pitches(){return NOTES.clone();}
    public static int note(int key){if(key<0||key>=16)throw new IllegalArgumentException("键号无效");return NOTES[key];}
    public static boolean black(int key){for(int value:BLACK)if(value==key)return true;return false;}
    public static int xTenths(int key){
        for(int n=0;n<WHITE.length;n++)if(WHITE[n]==key)return n*10;
        for(int n=0;n<BLACK.length;n++)if(BLACK[n]==key)return GAPS[n]*10-3;
        throw new IllegalArgumentException("踏板条不在键盘几何内");
    }
    public static String name(int note){if(note<0||note>127)throw new IllegalArgumentException("音高无效");return new String[]{"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}[note%12]+(note/12-1);}
}
