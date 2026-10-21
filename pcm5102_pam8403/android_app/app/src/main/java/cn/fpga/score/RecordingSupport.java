package cn.fpga.score;

import java.io.IOException;

/** Discover recording features with read-only queries before offering write commands. */
public final class RecordingSupport {
    public static final String EVENTS_UNAVAILABLE="当前板端未启用事件录制与板上重放。请使用配套统一固件 PCM5102_UNIFIED.fs，或独立 FINAL_EVENT_RECORDER.fs。更换 App 不能替代更新 FPGA 固件。";
    public static final class UnsupportedFeatureException extends IOException {
        private UnsupportedFeatureException(String message){super(message);}
    }
    private static boolean unavailable(SppLink.CommandRejectedException e){
        return e.response.equals("ERR,CMD")||e.response.equals("ERR,STATE");
    }
    public static TakeStatus readEvents(SppLink link)throws IOException,InterruptedException {
        try{return TakeStatus.parse(link.command("TAKE?","TAKE,"));}
        catch(SppLink.CommandRejectedException e){if(unavailable(e))throw new UnsupportedFeatureException(EVENTS_UNAVAILABLE);throw e;}
    }
}
