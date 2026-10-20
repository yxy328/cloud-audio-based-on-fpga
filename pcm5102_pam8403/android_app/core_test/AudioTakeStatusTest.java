package cn.fpga.score;
public final class AudioTakeStatusTest {
    public static void main(String[] args)throws Exception{
        AudioTakeStatus s=AudioTakeStatus.parse("AREC,0,0,0,1,2,0,FFFF,165A0B");
        if(!s.valid||s.busy||s.error!=0||s.generation!=65535||s.samples!=1464843)throw new AssertionError();
        s=AudioTakeStatus.parse("AREC,0,0,0,1,F,D,0001,000100");
        if(!s.description().contains("拒绝擦除"))throw new AssertionError();
        for(String line:new String[]{"AREC,0,1,0","AREC,0,0,0,1,2,0,0001,000000","AREC,0,0,0,1,2,0,0001,FFFFFF"}){
            try{AudioTakeStatus.parse(line);throw new AssertionError(line);}catch(java.io.IOException expected){}
        }
        System.out.println("PASS AudioTakeStatus: 5 checks");
    }
}
