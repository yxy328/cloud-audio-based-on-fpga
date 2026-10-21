package cn.fpga.score;

public final class TakeWorkflowTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("TakeWorkflow "+checks);}
    private static DeviceControls controls(int hold,int poly)throws Exception{return DeviceControls.parse("CTRL2,1,0,4,"+hold+",0,16,0,"+poly+",0");}
    private static TakeStatus take(String flags)throws Exception{return TakeStatus.parse("TAKE,"+flags+",0,000000,001,000001");}
    public static void main(String[] args)throws Exception{
        check(!new TakeWorkflow(null,null).canRecord);check(!new TakeWorkflow(controls(0,16),null).canRecord);
        for(int hold=0;hold<3;hold++)for(int poly:new int[]{1,2,4,8,16}){
            TakeWorkflow state=new TakeWorkflow(controls(hold,poly),take("00"));
            check(state.canRecord==(hold<2&&poly==16));check(!state.canPlay&&!state.canSave&&!state.canStop);
        }
        TakeWorkflow recording=new TakeWorkflow(controls(0,16),take("01"));check(recording.canStop&&!recording.canRecord);check(recording.stop==TakeWorkflow.Step.READY);
        TakeWorkflow ready=new TakeWorkflow(controls(1,16),take("04"));check(ready.canRecord&&ready.canPlay&&ready.canSave&&ready.canDelete);check(ready.stop==TakeWorkflow.Step.DONE);
        TakeWorkflow saved=new TakeWorkflow(controls(0,16),take("0C"));check(saved.canPlay&&!saved.canSave);check(saved.save==TakeWorkflow.Step.DONE);
        for(String flags:new String[]{"24","44","84"}){TakeWorkflow wait=new TakeWorkflow(controls(0,16),take(flags));check(!wait.canRecord&&!wait.canPlay&&!wait.canSave&&!wait.canDelete);}
        check(!TakeWorkflow.logBlockReason(controls(0,16)).isEmpty());
        check(TakeWorkflow.logBlockReason(DeviceControls.parse("CTRL2,0,0,4,0,0,16,0,16,0")).isEmpty());
        check(TakeWorkflow.logBlockReason(DeviceControls.parse("CTRL2,0,0,4,0,0,16,0,8,0")).isEmpty());
        for(int mode=0;mode<2;mode++)for(int hold=0;hold<3;hold++)for(int analog=0;analog<5;analog++)for(int poly:new int[]{1,16}){
            String reason=TakeWorkflow.logBlockReason(DeviceControls.parse("CTRL2,"+mode+",0,4,"+hold+","+analog+",16,0,"+poly+",0"));
            check(reason.isEmpty()==(mode==0&&hold==0&&analog==0));
            check(reason.contains("8 键直连")== (mode!=0));check(reason.contains("HOLD=0")== (hold!=0));check(reason.contains("ANALOG=0")== (analog!=0));
        }
        check(!new TakeWorkflow(DeviceControls.parse("CTRL,0,0,4,0,0,16,0"),take("00")).canRecord);
        System.out.println("PASS TakeWorkflow: "+checks+" checks");
    }
}
