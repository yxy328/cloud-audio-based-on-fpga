package cn.fpga.score;

import java.io.IOException;
import java.util.Locale;

/** Board-owned event take. A command acknowledgement never means saved. */
public final class TakeStatus {
    public final int flags,error,elapsedMs,count,durationMs;
    private TakeStatus(int f,int e,int t,int n,int d){flags=f;error=e;elapsedMs=t;count=n;durationMs=d;}
    public static TakeStatus parse(String line) throws IOException {
        if(line==null || !line.matches("TAKE,[0-9A-F]{2},[0-9A-F],[0-9A-F]{6},[0-9A-F]{3},[0-9A-F]{6}"))
            throw new IOException("录制状态格式错误");
        String[] p=line.split(",");
        int f=Integer.parseInt(p[1],16),n=Integer.parseInt(p[4],16);
        if(n>1024 || (f&3)==3 || (f&0xc0)==0xc0 || ((f&8)!=0 && (f&4)==0))
            throw new IOException("录制状态互相矛盾");
        return new TakeStatus(f,Integer.parseInt(p[2],16),Integer.parseInt(p[3],16),n,Integer.parseInt(p[5],16));
    }
    public int confirmation(){return flags>>>6;}
    public boolean busy(){return (flags&0x23)!=0;}
    public boolean saved(){return (flags&8)!=0 && (flags&0x21)==0 && error==0;}
    public String description(){
        String mode=(flags&1)!=0?"正在录制":(flags&2)!=0?"正在回放":(flags&0x20)!=0?"正在检查或保存 Flash":"已停止";
        String storage=saved()?"Flash 保存并读回校验成功，可断电保留":(flags&4)!=0?"仅有 RAM 内容，尚未保存成功，断电会丢失":"没有可回放内容";
        String issue=error==0?"":"\n错误 "+error+"："+(error==8?"Flash 型号不符或区域含未知数据，已禁止擦写":error==9?"Flash 写使能或超时失败":error==10?"Flash 校验失败":"录制或回放未完成");
        return String.format(Locale.CHINA,"%s · %.3f 秒\n事件 %d / 1024 · %s%s%s",mode,elapsedMs/1000.0,count,storage,
            (flags&16)!=0?"\n容量已满，已自动停止":"",issue);
    }
}
