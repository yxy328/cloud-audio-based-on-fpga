package cn.fpga.score;

public final class TakeWorkflow {
    public enum Step { LATER, READY, DONE }
    public final Step record,stop,play,save;
    public final String reason;
    public final boolean canRecord,canStop,canPlay,canSave,canDelete;
    public TakeWorkflow(DeviceControls controls,TakeStatus take){
        boolean content=take!=null&&(take.flags&4)!=0;
        boolean active=take!=null&&(take.flags&3)!=0;
        boolean waiting=take==null||take.confirmation()!=0||(take.flags&32)!=0;
        reason=controls==null?"请先读取设备演奏状态":!controls.extended?"旧固件未提供复音状态，无法确认可录配置":
            controls.hold==2&&controls.poly!=16?"钢琴踏板和限复音不支持板上事件录制；需关闭踏板并设复音 16":
            controls.hold==2?"钢琴踏板不支持板上事件录制；延音需为关闭或无限锁存":
            controls.poly!=16?"板上事件录制要求复音上限为 16":take==null?"请先读取板上事件录制状态":
            take.confirmation()!=0?"请先确认或取消覆盖 / 删除":(take.flags&32)!=0?"正在检查或保存 Flash":active?"请先停止当前录制 / 回放":"";
        canRecord=reason.isEmpty();canStop=active&&!waiting;
        canPlay=content&&!active&&!waiting;canSave=canPlay&&!take.saved();canDelete=content&&!active&&!waiting;
        record=active&&(take.flags&1)!=0?Step.DONE:canRecord?Step.READY:content?Step.DONE:Step.LATER;
        stop=canStop?Step.READY:content&&!active?Step.DONE:Step.LATER;
        play=canPlay?Step.READY:Step.LATER;
        save=take!=null&&take.saved()?Step.DONE:canSave?Step.READY:Step.LATER;
    }
    public static String logBlockReason(DeviceControls controls){
        if(controls==null)return "请先读取设备演奏状态";
        StringBuilder reason=new StringBuilder();
        if(controls.mode16!=0)reason.append("当前为 16 键模式，日志要求 8 键直连；");
        if(controls.hold!=0)reason.append(controls.hold==2?"当前为踏板态，日志要求 HOLD=0；":"当前已开延音，日志要求 HOLD=0；");
        if(controls.analog!=0)reason.append("当前模拟用途为 ").append(controls.analog).append("，日志要求 ANALOG=0（FSR）；");
        return reason.toString();
    }
}
