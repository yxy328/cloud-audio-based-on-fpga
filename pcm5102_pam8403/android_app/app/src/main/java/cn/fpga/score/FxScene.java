package cn.fpga.score;

import java.util.Locale;

/** Phone scene contains device configuration only, never slider/replay values. */
public final class FxScene {
    public final String id,name;
    public final int mask,settings,mix;
    public FxScene(String id,String name,int mask,int settings,int mix){
        if(id==null||!id.matches("[a-zA-Z0-9-]{1,48}"))throw new IllegalArgumentException("场景编号无效");
        this.id=id;this.name=validName(name);
        // Use the same strict field validation as the wire protocol.
        FxState.parse(String.format(Locale.ROOT,"EFFECT3,%X,%02X,%03X,0,00,000",mask,settings,mix));
        this.mask=mask;this.settings=settings;this.mix=mix;
    }
    public static String validName(String name){
        String value=name==null?"":name.trim();
        if(value.isEmpty()||value.length()>40)throw new IllegalArgumentException("场景名称须为 1～40 个字符");
        for(int n=0;n<value.length();n++)if(Character.isISOControl(value.charAt(n)))throw new IllegalArgumentException("场景名称不能含换行或控制字符");
        return value;
    }
    public static FxScene capture(String id,String name,FxState confirmed){
        if(confirmed==null)throw new IllegalArgumentException("请先读取设备三效果配置");
        return new FxScene(id,name,confirmed.mask,confirmed.settings,confirmed.mix);
    }
    public FxScene rename(String name){return new FxScene(id,name,mask,settings,mix);}
    public boolean matches(FxState f){return f!=null&&mask==f.mask&&settings==f.settings&&mix==f.mix;}
    public String command(){return "EFFECT,3,"+mask+","+settings+","+mix;}
    public String toString(){return name;}
    public interface Exchange {String command(String command,String reply)throws Exception;}
    public static final class Result {
        public final FxState observed;
        public final boolean confirmed;
        public final String error;
        Result(FxState observed,boolean confirmed,String error){this.observed=observed;this.confirmed=confirmed;this.error=error;}
    }
    /** Acknowledgement is insufficient: success requires matching configuration readback. */
    public Result apply(Exchange exchange){
        try{
            exchange.command(command(),"OK");
            FxState actual=FxState.parse(exchange.command("EFFECT,?","EFFECT3"));
            return new Result(actual,matches(actual),matches(actual)?null:"设备配置与所选场景不同，请检查实际状态后重试");
        }catch(Exception failure){
            FxState known=null;
            try{known=FxState.parse(exchange.command("EFFECT,?","EFFECT3"));}catch(Exception ignored){/* Unknown after failed recovery. */}
            return new Result(known,false,"应用未确认："+(failure.getMessage()==null?failure.getClass().getSimpleName():failure.getMessage()));
        }
    }
}
