package cn.fpga.score;

import java.io.IOException;

/** Confirmed FPGA state. Spinner positions are drafts until read back. */
public final class DeviceControls {
    public final int mode16,effect,wet,hold,analog,volume,pressure;
    private DeviceControls(int[] v){mode16=v[0];effect=v[1];wet=v[2];hold=v[3];analog=v[4];volume=v[5];pressure=v[6];}
    public static DeviceControls parse(String line)throws IOException {
        String[] p=line.split(",",-1);
        int[] max={1,2,8,1,4,16,1},v=new int[7];
        if(p.length!=8||!p[0].equals("CTRL"))throw new IOException("设备控制状态格式错误");
        for(int i=0;i<7;i++){
            if(!p[i+1].matches("[0-9]{1,2}"))throw new IOException("设备控制状态数字错误");
            try{v[i]=Integer.parseInt(p[i+1]);}catch(NumberFormatException e){throw new IOException("设备控制状态数字错误",e);}
            if(v[i]>max[i])throw new IOException("设备控制状态超出范围");
        }
        return new DeviceControls(v);
    }
    public static String touchCommand(int selection){if(selection<0||selection>1)throw new IllegalArgumentException();return "TOUCH,"+(selection==0?8:16);}
    public String summary(){return (mode16==0?"8 键直连 · 7 音＋压力切换":"16 键串行 · 16 音和弦")+
        "\n音效："+new String[]{"原声","回声","合唱"}[effect]+" · 湿度 "+wet+"/8 · 总音量 "+volume+"/16"+
        "\n延音锁存："+(hold==1?"开":"关")+" · 模拟输入用途 "+analog+" · 压力"+(pressure==1?"音高":"音量");}
}
