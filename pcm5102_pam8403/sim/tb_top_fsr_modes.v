`timescale 1ns/1ps
// External I2S validation with real ADC/fabric/sample timing and short debounce.
module tb_top_fsr_modes;
    reg clk=0; always #10 clk=~clk;
    reg [7:0] pads=8'h80;
    reg s1=0;
    wire bck,lrck,din;
    top #(.KEY_CONFIRM_CYCLES(1000),.TOUCH_STARTUP_US(3000),
        .TOUCH_DEBOUNCE_MS(2),.TOUCH_MODE_DEBOUNCE_MS(2),
        .TOUCH_ADSR_RELEASE_SAMPLES(32),.ADSR_ATTACK_SAMPLES(4),
        .ADSR_DECAY_SAMPLES(4),.ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(s1),.key_s2(1'b0),.touch_out(pads),
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl());
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24564)) monitor(
        .bck(bck),.lrck(lrck),.din(din));
    real volume_light,volume_heavy,pitch_low,pitch_mid,pitch_base,returned,song_amp,wrong_pitch;
    integer first,k;
    reg [31:0] old_phase,expected_phase;
    // DDS phase must advance by the selected step, never reset on a mode change.
    always @(posedge clk) begin
        if(dut.resetn && dut.frame_ce) begin
            old_phase=dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase;
            expected_phase=old_phase+dut.touch_phase_increments[31:0]; #1;
            if(dut.touch_voices[0].u_synth.voices[0].u_voice.u_dds.phase!==expected_phase)
                $fatal(1,"Mode/pressure change interrupted DDS phase continuity");
        end
    end
    always @(negedge clk) begin
        if(dut.resetn && (dut.u_output_mix.clipped || dut.pressure_enabled.u_touch_mix.clipped))
            $fatal(1,"Default 11-voice expression mix clipped");
        if(dut.touch_note_gates[7]!==0) $fatal(1,"Control key 8 started a note");
    end
    task silence;
        input integer start_sample;
        integer n;
        begin
            for(n=start_sample;n<monitor.pcm_count;n=n+1)
                if(monitor.pcm[n]!=0) $fatal(1,"Key 8/pressure alone produced audio");
        end
    endtask
    task spectrum;
        input real hz;
        input integer start_sample;
        output real result;
        integer n;
        real co,si,w,ws,angle;
        begin
            co=0;si=0;ws=0;
            for(n=0;n<1024;n=n+1) begin
                w=0.5-0.5*$cos(6.283185307179586*n/1023.0);
                angle=6.283185307179586*hz*n/48828.125;
                co=co+w*monitor.pcm[start_sample+n]*$cos(angle);
                si=si+w*monitor.pcm[start_sample+n]*$sin(angle);ws=ws+w;
            end
            result=2*$sqrt(co*co+si*si)/ws;
        end
    endtask
    task measure;
        input real hz;
        output real result;
        begin
            first=monitor.pcm_count;
            wait(monitor.pcm_count>=first+1024);#1;
            spectrum(hz,first,result);
        end
    endtask
    task set_pressure;
        input [9:0] value;
        begin
            dut.u_fsr_adc.adc_inst.sim_value={3'd0,value,1'b0};#22000000;
            if(dut.fsr_adc_sample!==value) $fatal(1,"Mode test ADC sample did not settle");
            if(dut.fsr_pitch_mode) begin
                if(dut.fsr_gain!==65535 || dut.fsr_pitch_ratio!==dut.fsr_target_pitch_ratio)
                    $fatal(1,"Pitch mode did not settle to unity volume/target pitch");
            end else if(dut.fsr_gain!==dut.fsr_target_gain || dut.fsr_pitch_ratio!==65535)
                $fatal(1,"Volume mode did not settle to original pitch/target gain");
        end
    endtask
    task press_mode;
        input wanted;
        begin
            pads=pads & 8'h7f;wait(dut.touch_keys[7]==0);#1000;
            pads=pads | 8'h80;wait(dut.touch_keys[7]==1);#1000;
            if(dut.fsr_pitch_mode!==wanted) $fatal(1,"Debounced key 8 failed to switch");
        end
    endtask
    initial begin
        #7000000;
        if(!dut.touch_ready || dut.fsr_pitch_mode!==0) $fatal(1,"Startup-held key 8 changed default volume mode");
        silence(0);
        pads=0;wait(dut.touch_keys==0);#1000;
        pads=8'h80;#300000;pads=0;#3000000;
        if(dut.fsr_pitch_mode!==0) $fatal(1,"Short control-key pulse switched mode");
        press_mode(1);#8000000;
        if(dut.fsr_pitch_mode!==1) $fatal(1,"Held key 8 switched repeatedly");
        press_mode(0);silence(0);
        pads=1;wait(dut.touch_keys==1);#1000000;
        set_pressure(0);measure(261.6255653,volume_light);
        set_pressure(1023);measure(261.6255653,volume_heavy);
        if(volume_light<1190 || volume_light>1260 || volume_heavy/volume_light<0.24 || volume_heavy/volume_light>0.26)
            $fatal(1,"Volume mode lost original pitch or quarter-gain endpoint");
        press_mode(1);set_pressure(1023);measure(130.81278265,pitch_low);
        spectrum(261.6255653,first,wrong_pitch);
        if(pitch_low<1180 || pitch_low>1270 || wrong_pitch>70 || dut.fsr_pitch_mode!==1)
            $fatal(1,"Low-octave pitch mode/held key/constant volume failed: %f/%f",pitch_low,wrong_pitch);
        set_pressure(316);measure(196.219173975,pitch_mid);
        set_pressure(0);measure(261.6255653,pitch_base);
        if(pitch_mid<1180 || pitch_mid>1270 || pitch_base<1190 || pitch_base>1260)
            $fatal(1,"Continuous pressure pitch/constant volume endpoints failed");
        set_pressure(1023);press_mode(0);set_pressure(1023);measure(261.6255653,returned);
        if(returned<295 || returned>320 || dut.fsr_pitch_mode!==0)
            $fatal(1,"Switch back to volume did not restore original note/pressure gain");
        $display("PASS [mode I2S]: volume C4 light=%0.2f heavy=%0.2f; pitch C3=%0.2f intermediate=%0.2f C4=%0.2f, pressure changes frequency with fixed sustain amplitude; returned C4=%0.2f",volume_light,volume_heavy,pitch_low,pitch_mid,pitch_base,returned);
        pads=8'h7f;wait(dut.touch_keys==8'h7f);set_pressure(0);
        s1=1;#100000;s1=0;#45000000;
        if(!dut.u_control.playing || dut.voice_gates!==4'hf ||
           dut.touch_voices[0].u_synth.active!==4'hf || dut.touch_voices[1].u_synth.active!==4'h7)
            $fatal(1,"Seven notes plus four song voices failed");
        press_mode(1);set_pressure(1023);
        if(dut.phase_increments[31:0]!==46025656 || dut.u_control.note_index!==0)
            $fatal(1,"Pressure changed the independent song pitch");
        measure(523.2511306,song_amp);
        if(song_amp<1140 || song_amp>1330) $fatal(1,"Independent C5 song tone missing: %f",song_amp);
        pads=0;wait(dut.touch_keys==0);#2000000;
        if(dut.touch_mix0!==0 || !dut.u_control.playing) $fatal(1,"Note release affected song");
        s1=1;#100000;s1=0;#2000000;
        first=monitor.pcm_count;
        press_mode(0);#3000000;silence(first);
        $display("PASS [top FSR modes]: key 8 never sounds, startup/short-pulse/long-press handling, both modes via ADC model, six I2S tone measurements, uninterrupted DDS phase, seven notes/11 voices/no clipping, song pitch independence, release/final silence; %0d stereo pairs",monitor.pair_count);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #700000000;$fatal(1,"Top FSR modes timeout");end
endmodule
