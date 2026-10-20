package cn.fpga.score;
public final class TakeStatusTest {
    static int checks;
    static void check(boolean b){checks++;if(!b)throw new AssertionError();}
    static void reject(String s)throws Exception{try{TakeStatus.parse(s);throw new AssertionError(s);}catch(java.io.IOException expected){checks++;}}
    public static void main(String[] args)throws Exception{
        TakeStatus empty=TakeStatus.parse("TAKE,00,0,000000,000,000000");check(!empty.saved()&&!empty.busy());
        TakeStatus saved=TakeStatus.parse("TAKE,0C,0,003039,400,003039");check(saved.saved()&&saved.count==1024&&saved.durationMs==12345);
        TakeStatus pending=TakeStatus.parse("TAKE,24,0,003039,040,003039");check(!pending.saved()&&pending.busy());
        TakeStatus failed=TakeStatus.parse("TAKE,04,8,003039,040,003039");check(!failed.saved()&&failed.description().contains("禁止擦写"));
        check(TakeStatus.parse("TAKE,4C,0,000000,022,000000").confirmation()==1);
        check(TakeStatus.parse("TAKE,8C,0,000000,022,000000").confirmation()==2);
        for(String s:new String[]{null,"","OK","TAKE,08,0,000000,001,000000","TAKE,03,0,000000,001,000000",
                "TAKE,C0,0,000000,001,000000","TAKE,00,0,000000,401,000000","TAKE,0c,0,000000,001,000000",
                "TAKE,00,0,000000,001,000000,extra","TAKE,00,0,-00001,001,000000"})reject(s);
        check(TakeStatus.parse("TAKE,1C,0,000100,3FF,000100").description().contains("容量已满"));
        System.out.println("PASS TakeStatusTest: "+checks+" checks");
    }
}
