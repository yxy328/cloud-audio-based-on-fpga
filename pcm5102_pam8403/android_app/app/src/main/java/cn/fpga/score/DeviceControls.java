package cn.fpga.score;

import java.io.IOException;

/** Confirmed FPGA state. Spinner positions are drafts until read back. */
public final class DeviceControls {
    public final int mode16,effect,wet,hold,analog,volume,pressure,poly,voices;
    public final boolean extended;
    private DeviceControls(int[] v,boolean ext){mode16=v[0];effect=v[1];wet=v[2];hold=v[3];analog=v[4];volume=v[5];pressure=v[6];poly=v[7];voices=v[8];extended=ext;}
    public static DeviceControls parse(String line)throws IOException {
        String[] p=line.split(",",-1);
        boolean ext=p.length==10&&p[0].equals("CTRL2");
        int[] max={1,2,8,ext?2:1,4,16,1,16,16},v=new int[9];v[7]=16;
        if(!ext&&(p.length!=8||!p[0].equals("CTRL")))throw new IOException("设备控制状态格式错误");
        for(int i=0;i<(ext?9:7);i++){
            if(!p[i+1].matches("[0-9]{1,2}"))throw new IOException("设备控制状态数字错误");
            try{v[i]=Integer.parseInt(p[i+1]);}catch(NumberFormatException e){throw new IOException("设备控制状态数字错误",e);}
            if(v[i]>max[i])throw new IOException("设备控制状态超出范围");
        }
        if(ext&&v[7]!=1&&v[7]!=2&&v[7]!=4&&v[7]!=8&&v[7]!=16)throw new IOException("设备复音上限无效");
        return new DeviceControls(v,ext);
    }
    public String summary(){return summary(true);}
    public String keyboardSummary(){return summary(false);}
    private String summary(boolean legacy){return (mode16==0?"旧固件：8 键直连，请更新配套 16 键固件":"16 键串行 · 16 音和弦")+
        (legacy?"\n音效："+new String[]{"原声","回声","合唱"}[effect]+" · 湿度 "+wet+"/8":"")+"\n总音量 "+volume+"/16"+
        "\n延音："+new String[]{"关闭","无限锁存","钢琴踏板"}[hold]+" · 模拟输入用途 "+analog+" · 压力"+(pressure==1?"音高":"音量")+
        (extended?"\n复音上限："+poly+" · 当前发声："+voices+"（按住的键优先）":"\n旧固件：未提供踏板及复音状态");}
}
