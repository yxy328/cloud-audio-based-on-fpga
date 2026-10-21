package cn.fpga.score;

public final class ControlStateTest {
    private static int checks;
    private static void check(boolean value){checks++;if(!value)throw new AssertionError("ControlState "+checks);}
    public static void main(String[] args){
        ControlState state=new ControlState();state.edit("page",4,"0");
        check(state.selection("page","0")==ControlState.Selection.DRAFT);check(!state.pending(4));check(!state.enabled());
        state.connected(true);state.confirm("page","0");check(!state.dirty("page"));check(!state.pending(4));
        state.edit("page",4,"3");check(state.pending(4));check(!state.pending(1));
        check(state.selection("page","3")==ControlState.Selection.DRAFT);check(state.selection("page","0")==ControlState.Selection.CONFIRMED);
        check(state.selection("page","1")==ControlState.Selection.OFF);
        state.busy(true);check(!state.enabled());check(state.selection("page","3")==ControlState.Selection.DRAFT);
        state.confirm("page","3");check(!state.pending(4));check(state.selection("page","3")==ControlState.Selection.CONFIRMED);
        state.edit("volume",2,"8");state.confirm("volume","16");check(state.pending(2));
        state.connected(false);check(!state.pending(2)&&!state.pending(4));check(state.confirmed("page")==null);
        check(state.selection("page","3")==ControlState.Selection.DRAFT);state.busy(false);check(!state.enabled());
        state.connected(true);check(state.pending(2)&&state.pending(4));state.confirm("volume","8");check(!state.pending(2));
        state.confirm("page","3");check(state.observe("page","1"));check(state.selection("page","1")==ControlState.Selection.CONFIRMED);check(!state.pending(4));
        state.edit("page",4,"2");check(!state.observe("page","0"));check(state.selection("page","2")==ControlState.Selection.DRAFT);check(state.selection("page","0")==ControlState.Selection.CONFIRMED);
        state.busy(true);check(!state.observe("page","2"));check(!state.pending(4)&&!state.enabled());
        check(ControlState.numbers(" 060, 062 ,64 ").equals("60,62,64"));check(ControlState.numbers("00,1023").equals("0,1023"));
        check(ControlState.numbers("60,,62").equals("60,,62"));check(ControlState.numbers("x,60").equals("x,60"));
        System.out.println("PASS ControlState: "+checks+" checks");
    }
}
