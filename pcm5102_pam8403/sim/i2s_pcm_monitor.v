`timescale 1ns/1ps
// Decode only external I2S pins, including protocol and physical periods.
module i2s_pcm_monitor #(
    parameter PCM_MIN = -8192,
    parameter PCM_MAX = 8188,
    parameter CAPTURE_FILE = "",
    parameter SUPPORT_RESET = 0
) (input wire bck, input wire lrck, input wire din, input wire resetn);
    reg started=0, last_lrck=1;
    integer slot_bit=0, word=0, left_word=0;
    integer pcm[0:131071];
    integer pcm_count=0, pair_count=0, capture_file, capture_arg;
    integer last_pcm=0;
    reg [8*256-1:0] capture_path;
    time last_rise=0, last_fall=0, last_frame=0;
    always @(negedge resetn)if(SUPPORT_RESET)begin
        started=0;last_lrck=1;slot_bit=0;word=0;left_word=0;last_pcm=0;
        last_rise=0;last_fall=0;last_frame=0;
    end
    initial begin
        if(CAPTURE_FILE!="") capture_path=CAPTURE_FILE;
        else begin
            capture_path="sim/build/decoded_pcm.csv";
            capture_arg=$value$plusargs("pcm_csv=%s",capture_path);
        end
        capture_file=$fopen(capture_path,"w");
        if(!capture_file) $fatal(1,"Cannot open I2S capture");
        $fdisplay(capture_file,"time_ns,pcm");
    end
    always @(negedge bck) last_fall=$time;
    always @(din or lrck) begin
        if($time>2000 && (!SUPPORT_RESET || resetn)) begin
            #1;
            if(bck!==0 || $time-1!=last_fall) $fatal(1,"I2S changed away from falling BCK");
        end
    end
    always @(negedge lrck) if(!SUPPORT_RESET || resetn)begin
        if(last_frame!=0 && $time-last_frame!=20480) $fatal(1,"Wrong LRCK period");
        last_frame=$time;
    end
    always @(posedge bck) if(!SUPPORT_RESET || resetn)begin
        if(last_rise!=0 && $time-last_rise!=320) $fatal(1,"Wrong BCK period");
        last_rise=$time;
        #1;
        if((^{lrck,din})===1'bx) $fatal(1,"Unknown I2S pin");
        if(!started && !lrck) begin started=1;last_lrck=0;slot_bit=0;word=0;end
        else if(started) begin
            if(lrck!=last_lrck) begin
                if(slot_bit!=31) $fatal(1,"Wrong 32-bit slot");
                last_lrck=lrck;slot_bit=0;word=0;
            end else slot_bit=slot_bit+1;
        end
        if(started) begin
            if(slot_bit==0 || slot_bit>=17) begin
                if(din!==0) $fatal(1,"I2S delay or padding nonzero");
            end else begin
                word=((word<<1)|din)&16'hffff;
                if(slot_bit==16) begin
                    if(word>=32768) word=word-65536;
                    if(word<PCM_MIN || word>PCM_MAX) $fatal(1,"Mixed sample exceeds configured headroom");
                    if(!lrck) begin
                        if(pcm_count>=131072) $fatal(1,"Capture buffer full");
                        left_word=word;last_pcm=word;pcm[pcm_count]=word;
                        $fdisplay(capture_file,"%0d,%0d",$time,word);
                        pcm_count=pcm_count+1;
                    end else begin
                        if(word!=left_word) $fatal(1,"Stereo mismatch");
                        pair_count=pair_count+1;
                    end
                end
            end
        end
    end
endmodule
