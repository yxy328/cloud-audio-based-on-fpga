`timescale 1ns/1ps
// Short regression for both score elaboration branches. UART parsing has its
// own tests; force its decoded audition events here and observe external I2S.
module tb_top_score_config;
    reg clk=0; always #10 clk=~clk;
    reg s1=0;
    wire live_bck,live_lrck,live_din,demo_bck,demo_lrck,demo_din;
    top #(.FSR_ENABLE(0),.KEY_CONFIRM_CYCLES(4),.TOUCH_STARTUP_US(100),
        .ADSR_ATTACK_SAMPLES(1),.ADSR_DECAY_SAMPLES(1),.TOUCH_ADSR_RELEASE_SAMPLES(4)) live (
        .clk(clk),.key_s1(s1),.key_s2(1'b0),.touch_out(8'd0),.touch_sdo(1'b1),
        .ir_beam(8'hff),.hc05_rx(1'b1),.i2s_bck(live_bck),.i2s_lrck(live_lrck),.i2s_din(live_din));
    top #(.ENABLE_DEMO_SCORE(1),.FSR_ENABLE(0),.KEY_CONFIRM_CYCLES(4),.TOUCH_STARTUP_US(100),
        .ADSR_ATTACK_SAMPLES(1),.ADSR_DECAY_SAMPLES(1),.ADSR_RELEASE_SAMPLES(4),
        .SONG_INTRO_SAMPLES(1),.SONG_BEAT_SAMPLES(32),.SONG_GAP_SAMPLES(1),.SONG_TAIL_SAMPLES(4)) demo (
        .clk(clk),.key_s1(s1),.key_s2(1'b0),.touch_out(8'd0),.touch_sdo(1'b1),
        .ir_beam(8'hff),.hc05_rx(1'b1),.i2s_bck(demo_bck),.i2s_lrck(demo_lrck),.i2s_din(demo_din));
    i2s_pcm_monitor #(.CAPTURE_FILE("sim/build/score_config_live.csv")) live_monitor(.bck(live_bck),.lrck(live_lrck),.din(live_din));
    i2s_pcm_monitor #(.CAPTURE_FILE("sim/build/score_config_demo.csv")) demo_monitor(.bck(demo_bck),.lrck(demo_lrck),.din(demo_din));
    integer first,i,nonzero;
    task frames;
        input integer n;
        integer j;
        begin for(j=0;j<n;j=j+1) begin @(posedge live.frame_ce);@(negedge clk);end end
    endtask
    task sound;
        input integer from_sample;
        begin
            nonzero=0;
            for(i=from_sample;i<live_monitor.pcm_count;i=i+1)
                if(live_monitor.pcm[i]!=0)nonzero=nonzero+1;
            if(nonzero<8)$fatal(1,"Live routing lost audible I2S samples");
        end
    endtask
    initial begin
        frames(8);s1=1;repeat(16)@(negedge clk);s1=0;frames(24);
        if(live.ENABLE_DEMO_SCORE!=0 || live.builtin_playing!==0 || live.song_sample!==0 || live.song_active!==0)
            $fatal(1,"Default build enabled legacy demo audio");
        for(i=0;i<live_monitor.pcm_count;i=i+1)
            if(live_monitor.pcm[i]!==0)$fatal(1,"S1 created live audio without a note");
        nonzero=0;
        for(i=0;i<demo_monitor.pcm_count;i=i+1)
            if(demo_monitor.pcm[i]!=0)nonzero=nonzero+1;
        if(!demo.builtin_playing || demo.song_active==0 || nonzero<8)
            $fatal(1,"Enabled legacy demo no longer reaches I2S");
        // The production AUDITION path consumes guide keys, not the disabled
        // legacy downloaded_increment lookup.
        force live.downloaded_audition=1'b1;
        force live.downloaded_gate=1'b1;
        force live.song_guide_keys=7'h15;
        first=live_monitor.pcm_count;frames(24);
        if(live.touch_active!==16'h0015 || live.u_keymap.downloaded_increment!==0)
            $fatal(1,"Live audition depends on the removed legacy lookup");
        sound(first);
        force live.downloaded_audition=1'b0;frames(16);
        if(live.touch_active!==0 || live.audio_sample!==0)$fatal(1,"Audition release failed");
        force live.physical_notes=16'h8001;
        first=live_monitor.pcm_count;frames(24);
        if(live.touch_active!==16'h8001)$fatal(1,"Live K1/K16 voices missing");
        sound(first);
        force live.physical_notes=16'd0;frames(16);
        if(live.touch_active!==0 || live.audio_sample!==0)$fatal(1,"Physical note release failed");
        $display("PASS top score configuration: default S1 stays silent, enabled demo reaches I2S, production audition works without legacy LUT, independent K1/K16 and release");
        $finish;
    end
    initial begin #4000000;$fatal(1,"Score configuration timeout");end
endmodule
