package cn.fpga.score;
public final class Control12Test {
    public static void main(String[] args)throws Exception {
        int[] m=SongCodec.parseMapping("MAP,60,61,62,63,64,65,66,67,68,69,70,71");
        if(m.length!=12||m[11]!=71)throw new AssertionError("twelve mapping");
        SongCodec.Song all=SongCodec.csv("twelve.csv","pitches,duration_ms\n60+61+62+63+64+65+66+67+68+69+70+71,100\n".getBytes("UTF-8"));
        all.checkMapping(m);
        SongCodec.Song high=SongCodec.csv("high.csv","pitches,duration_ms\n72,100\n".getBytes("UTF-8"));
        int[] matched=SongLibrary.matchingMapping(high,m);high.checkMapping(matched);
        try {SongLibrary.matchingMapping(SongCodec.csv("thirteen.csv","pitches,duration_ms\n60+61+62+63+64+65+66+67+68+69+70+71+72,100\n".getBytes("UTF-8")),m);throw new AssertionError("lost note");}catch(IllegalArgumentException expected){}
        ScoreBends bend=ScoreBends.parse("bend.csv","pitches,duration_ms,bend_target_cents\n60+61+62+63+64+65+66+67+68+69+70+71,100,200\n".getBytes("UTF-8"));
        bend.song.checkMapping(m);
        if(!new String(bend.csv(),"UTF-8").contains("200"))throw new AssertionError("bend export");
        System.out.println("PASS Control12: twelve-note chord, high-note remap, thirteen-note rejection, score bend CSV");
    }
}
