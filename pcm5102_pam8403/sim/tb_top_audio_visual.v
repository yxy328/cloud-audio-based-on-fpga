`timescale 1ns/1ps
// Real audio timing and physical debounced buttons. Only long-press length
// and UART baud are accelerated; waveform capture retains 512 real samples.
module tb_top_audio_visual;
    reg clk=0; always #10 clk=~clk;
    reg rx=1,s2=0;
    reg [7:0] pads=0,beams=255;
    wire tx,bck,lrck,din,lat;
    wire r1,g1,b1,r2,g2,b2,ha,hb,hc,hd,he,hck;
    wire [4:0] panel_row={he,hd,hc,hb,ha};
    tri1 scl,sda;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),
        .FSR_ENABLE(0),.KEY_CONFIRM_CYCLES(10),.DISPLAY_HOLD_FRAMES(64),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16)) dut (
        .clk(clk),.key_s1(1'b0),.key_s2(s2),.touch_out(pads),.ir_beam(beams),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .scl(scl),.sda(sda),.hub_ST(lat),.hub_CK(hck),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(ha),.hub_B(hb),.hub_C(hc),.hub_D(hd),.hub_E(he));
    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=1000;
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor (.bck(bck),.lrck(lrck),.din(din));
    integer frame_count=0,restarts=0,resets=0,latches=0,phase_checks=0,k;
    integer ir_events=0,sensor_max=0,sensor_magnitude;
    reg [31:0] expected_phase;
    reg signed [15:0] expected_sample;
    integer expected_y;
    always @(posedge lat) latches=latches+1;
    always @(posedge clk) if(dut.resetn) begin
        if(dut.s2_action) restarts=restarts+1;
        if(dut.ir_note_valid) ir_events=ir_events+1;
        if(dut.guide_reset) resets=resets+1;
        if(dut.frame_ce) begin
            frame_count=frame_count+1;
            expected_sample=dut.audio_sample;
            sensor_magnitude=$signed(dut.gesture_sample);
            if(sensor_magnitude<0) sensor_magnitude=-sensor_magnitude;
            if(sensor_magnitude>sensor_max) sensor_max=sensor_magnitude;
            if(expected_sample>7680) expected_y=1;
            else if(expected_sample < -7680) expected_y=31;
            else expected_y=16-($signed(expected_sample) >>> 9);
            expected_phase=dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase+dut.touch_phase_increments[31:0];
            #1;
            if(dut.u_i2s_tx.frame_sample!==expected_sample) $fatal(1,"Visualization changed I2S frame sample");
            if(dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase!==expected_phase)
                $fatal(1,"Display switch disturbed live oscillator");
            if(!dut.u_guide_display.audio_visual.u_visualizer.capture_ready &&
               dut.u_guide_display.audio_visual.u_visualizer.sample_phase==1) begin
                if(dut.u_guide_display.audio_visual.u_visualizer.minimum_y!==expected_y[4:0])
                    $fatal(1,"Waveform sample %0d y=%0d expected %0d",expected_sample,
                        dut.u_guide_display.audio_visual.u_visualizer.minimum_y,expected_y);
            end
            phase_checks=phase_checks+1;
        end
    end
    task frames;
        input integer count; integer target;
        begin target=frame_count+count; wait(frame_count>=target); @(negedge clk); end
    endtask
    task send_byte;
        input [7:0] ch; integer b;
        begin rx=0;repeat(100) @(negedge clk);
            for(b=0;b<8;b=b+1) begin rx=ch[b];repeat(100) @(negedge clk);end
            rx=1;repeat(100) @(negedge clk); end
    endtask
    task command;
        input [511:0] message; input integer length;
        integer n,b,c; reg [31:0] reply; reg [7:0] data;
        begin
            fork
                begin
                    reply=0;
                    for(c=0;c<4;c=c+1) begin
                        @(negedge tx);repeat(50) @(posedge clk);
                        for(b=0;b<8;b=b+1) begin repeat(100) @(posedge clk);data[b]=tx;end
                        repeat(100) @(posedge clk);
                        if(tx!==1) $fatal(1,"UART stop bit");
                        reply={reply[23:0],data};
                    end
                    if(reply!=={"OK",8'd13,8'd10}) $fatal(1,"Unexpected command reply %h",reply);
                end
                begin for(n=length-1;n>=0;n=n-1) send_byte(message[n*8 +: 8]); end
            join
        end
    endtask
    integer before_resets,before_restarts;
    // Reconstruct a complete RGB5 frame using external HUB data/clock/LAT,
    // including every PWM phase, for a reviewable simulated panel preview.
    integer screen_r[0:4095],screen_g[0:4095],screen_b[0:4095];
    reg [5:0] row_pixels[0:63];
    reg capture_screen=0;
    integer column=0,px,upper_index,lower_index,preview;
    always @(posedge hck) begin
        row_pixels[column]={r1,g1,b1,r2,g2,b2};
        column=(column+1)%64;
    end
    always @(posedge lat) if(capture_screen) begin
        for(px=0;px<64;px=px+1) begin
            upper_index=panel_row*64+px; lower_index=(panel_row+32)*64+px;
            screen_r[upper_index]=screen_r[upper_index]+row_pixels[px][5];
            screen_g[upper_index]=screen_g[upper_index]+row_pixels[px][4];
            screen_b[upper_index]=screen_b[upper_index]+row_pixels[px][3];
            screen_r[lower_index]=screen_r[lower_index]+row_pixels[px][2];
            screen_g[lower_index]=screen_g[lower_index]+row_pixels[px][1];
            screen_b[lower_index]=screen_b[lower_index]+row_pixels[px][0];
        end
    end
    task save_preview;
        input [511:0] filename;
        integer p;
        begin
            wait(dut.u_guide_display.pwm_phase==31 && panel_row==31 && lat);
            @(negedge lat);
            for(p=0;p<4096;p=p+1) begin screen_r[p]=0;screen_g[p]=0;screen_b[p]=0;end
            capture_screen=1;
            wait(dut.u_guide_display.pwm_phase==31 && panel_row==31 && lat);
            #2; capture_screen=0;
            preview=$fopen(filename,"w");
            if(!preview) $fatal(1,"Cannot open panel preview");
            $fdisplay(preview,"P3\n64 64\n31");
            for(p=0;p<4096;p=p+1) $fdisplay(preview,"%0d %0d %0d",screen_r[p],screen_g[p],screen_b[p]);
            $fclose(preview);
        end
    endtask
    task xy_preset;
        input [1:0] ratio,phase;
        input [511:0] filename;
        begin
            s2=1;frames(4);s2=0;frames(4);
            wait(dut.u_guide_display.audio_visual.u_visualizer.shown_ratio==ratio &&
                 dut.u_guide_display.audio_visual.u_visualizer.shown_phase==phase);
            save_preview(filename);
            if(restarts!=before_restarts || resets!=before_resets)$fatal(1,"XY short release restarted playing score");
        end
    endtask
    initial begin
        wait(dut.touch_ready);frames(8);
        command("SONG_BEGIN,1\n",13);
        command("SONG_NOTE,0,60,1000\n",20);
        command("SONG_END\n",9);
        command("PLAY\n",5);
        wait(dut.downloaded_playing);
        pads=1; wait(dut.touch_keys[0]);frames(20);
        if(dut.visual_mode) $fatal(1,"Boot did not select the guide");
        before_resets=resets; before_restarts=restarts;
        s2=1; frames(80);
        if(!dut.visual_mode || restarts!=before_restarts || resets!=before_resets)
            $fatal(1,"Long S2 restarted the guide");
        wait(dut.u_guide_display.visual_active);
        frames(80);
        if(!dut.visual_mode) $fatal(1,"Held S2 repeated its mode switch");
        s2=0;frames(4);
        if(restarts!=before_restarts || resets!=before_resets || !dut.downloaded_playing)
            $fatal(1,"Long release interrupted the guide");
        frames(600);
        if(!dut.u_guide_display.audio_visual.u_visualizer.display_valid ||
           dut.u_guide_display.audio_visual.u_visualizer.shown_touch==0)
            $fatal(1,"Live touch did not reach waveform/meter");
        // Real qualified IR and the real guitar engine must reach their group taps.
        beams=254;frames(60);beams=255;frames(100);
        command("GUITAR\n",7);frames(200);
        // Meter pixels use the published whole-PWM-frame snapshot. A new
        // source can peak just after that boundary, so await its next publish.
        wait(dut.u_guide_display.display_boundary); @(posedge clk); #2;
        if(dut.u_guide_display.audio_visual.u_visualizer.shown_sensor==0 ||
           dut.u_guide_display.audio_visual.u_visualizer.shown_guitar==0)
            $fatal(1,"IR/guitar meters: %0d/%0d; IR events=%0d, sensor peak=%0d, voices=%0d",
                dut.u_guide_display.audio_visual.u_visualizer.shown_sensor,
                dut.u_guide_display.audio_visual.u_visualizer.shown_guitar,ir_events,sensor_max,dut.sensor_voice_count);
        save_preview("sim/build/audio_visual_panel.ppm");
        s2=1;frames(80);s2=0;frames(4);
        wait(dut.u_guide_display.visual_active==2);
        save_preview("sim/build/xy_lissajous_panel.ppm");
        xy_preset(3,0,"sim/build/xy_multiloop_panel.ppm");
        xy_preset(1,2,"sim/build/xy_circle_panel.ppm");
        xy_preset(1,1,"sim/build/xy_ellipse_panel.ppm");
        xy_preset(1,0,"sim/build/xy_line_panel.ppm");
        xy_preset(0,0,"sim/build/xy_audio_panel.ppm");
        // UART settings take effect while live voices and the score keep running.
        command("XY,1,2\n",7);
        wait(dut.u_guide_display.audio_visual.u_visualizer.shown_ratio==1 &&
             dut.u_guide_display.audio_visual.u_visualizer.shown_phase==2);
        command("XY,2,0\n",7);
        s2=1;frames(80);s2=0;frames(4);
        wait(dut.u_guide_display.visual_active==3);
        wait(dut.u_guide_display.audio_visual.u_visualizer.shown_spectrum_valid);
        if(dut.u_guide_display.audio_visual.u_visualizer.shown_spectrum[4*5+:5]==0)
            $fatal(1,"Live C4 did not reach its FFT frequency band");
        save_preview("sim/build/xy_spectrum_panel.ppm");
        s2=1;frames(80);s2=0;frames(4);
        wait(dut.u_guide_display.visual_active==0);
        if(restarts!=before_restarts || resets!=before_resets)
            $fatal(1,"Return to guide restarted it");
        // Short release is still an independent score restart.
        s2=1;frames(4);
        if(restarts!=before_restarts) $fatal(1,"Short press restarted before release");
        s2=0;frames(4);
        if(restarts!=before_restarts+1 || resets<=before_resets || !dut.downloaded_playing)
            $fatal(1,"Short S2 release lost the score restart");
        if(dut.visual_mode || dut.sensor_overrun || monitor.pcm_count<1000 || latches<1000 || phase_checks<1000)
            $fatal(1,"Integrated audio/display coverage or timing failed");
        $display("PASS top audio visual: exact I2S tap/continuous phase, live touch/IR/guitar, C4 FFT, S2 modes and six XY presets, UART XY while playing, score uninterrupted, external I2S/HUB and eight panel captures");
        $finish;
    end
    initial begin #250000000; $fatal(1,"Top audio visual timeout"); end
endmodule
