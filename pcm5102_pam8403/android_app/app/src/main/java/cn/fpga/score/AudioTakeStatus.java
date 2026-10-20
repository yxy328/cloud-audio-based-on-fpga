package cn.fpga.score;

import java.io.IOException;

/** Flash PCM status. Legacy USB's three flags cannot prove a Flash commit. */
public final class AudioTakeStatus {
    public final boolean busy,prepared,overflow,valid;
    public final int state,error,generation,samples;
    private AudioTakeStatus(String[] p){
        busy=p[1].equals("1");prepared=p[2].equals("1");overflow=p[3].equals("1");valid=p[4].equals("1");
        state=Integer.parseInt(p[5],16);error=Integer.parseInt(p[6],16);
        generation=Integer.parseInt(p[7],16);samples=Integer.parseInt(p[8],16);
    }
    public static AudioTakeStatus parse(String line)throws IOException {
        if(line==null||!line.matches("AREC,[01],[01],[01],[01],[0-9A-F],[0-9A-F],[0-9A-F]{4},[0-9A-F]{6}"))
            throw new IOException("需要配套的HC-05 Flash音频固件："+line);
        AudioTakeStatus s=new AudioTakeStatus(line.split(","));
        if(s.samples>1464843||(s.valid&&s.samples==0))throw new IOException("Flash录音长度无效");
        return s;
    }
    public String description(){
        String[] errors={"正常","Flash型号/初始化不匹配","录音槽未准备","没有已提交录音","擦除失败",
            "写入失败","读回失败","PCM读回CRC不一致","元数据写入/校验失败","提交标志失败",
            "回传读取失败","回传确认超时","录音已中止","目标槽含未知或损坏内容，已拒绝擦除",
            "空录音未提交","FIFO溢出，本次未提交"};
        return "状态 "+state+"；"+errors[error]+"；"+(busy?"忙":"空闲")+"；"+(prepared?"已准备":"未准备")+
            "；有效录音 "+(valid?samples+"采样（序号"+generation+"）":"无");
    }
}
