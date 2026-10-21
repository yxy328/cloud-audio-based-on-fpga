package cn.fpga.score;

import java.io.IOException;

/** Discover recording features with read-only queries before offering write commands. */
public final class RecordingSupport {
    public static final String AUDIO_UNAVAILABLE="当前板端未启用 HC-05 Flash 原音质录音。钢琴踏板版为保留演奏资源已关闭此功能，手机本地录制与板上事件录制仍可使用。原音质录音需另用支持该功能的旧版或独立 PCM5102_AUDIO_TAKE 固件。";
    public static final String EVENTS_UNAVAILABLE="当前板端未启用事件录制与板上重放。请使用配套统一固件 PCM5102_UNIFIED.fs，或独立 FINAL_EVENT_RECORDER.fs。更换 App 不能替代更新 FPGA 固件。";
    public final AudioTakeStatus audio;
    public final TakeStatus events;
    private RecordingSupport(AudioTakeStatus audio,TakeStatus events){this.audio=audio;this.events=events;}
    public static final class UnsupportedFeatureException extends IOException {
        private UnsupportedFeatureException(String message){super(message);}
    }
    private static boolean unavailable(SppLink.CommandRejectedException e){
        return e.response.equals("ERR,CMD")||e.response.equals("ERR,STATE");
    }
    public static AudioTakeStatus readAudio(SppLink link)throws IOException,InterruptedException {
        String line;
        try{line=link.command("AREC?","AREC");}
        catch(SppLink.CommandRejectedException e){if(unavailable(e))throw new UnsupportedFeatureException(AUDIO_UNAVAILABLE);throw e;}
        // The older USB recorder also answers AREC?, even when disabled. Its
        // three flags do not establish Flash support, regardless of ready=1.
        if(line.matches("AREC,[01],[01],[01]"))throw new UnsupportedFeatureException(AUDIO_UNAVAILABLE);
        return AudioTakeStatus.parse(line);
    }
    public static TakeStatus readEvents(SppLink link)throws IOException,InterruptedException {
        try{return TakeStatus.parse(link.command("TAKE?","TAKE,"));}
        catch(SppLink.CommandRejectedException e){if(unavailable(e))throw new UnsupportedFeatureException(EVENTS_UNAVAILABLE);throw e;}
    }
    public static RecordingSupport probe(SppLink link)throws IOException,InterruptedException {
        AudioTakeStatus audio=null;TakeStatus events=null;
        try{audio=readAudio(link);}catch(UnsupportedFeatureException expected){}
        try{events=readEvents(link);}catch(UnsupportedFeatureException expected){}
        return new RecordingSupport(audio,events);
    }
}
