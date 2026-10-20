`timescale 1ns/1ps
// Production note/mode confirmation, ADSR and audio timing. Only the one-time
// power-up wait is shortened. OUT-to-I2S excludes the touch IC and analog DAC.
module tb_top_touch_response;
    reg clk=0; always #10 clk=~clk;
    reg [7:0] pads=0;
    wire bck,lrck,din;
    top #(.TOUCH_STARTUP_US(3000)) dut (
        .clk(clk), .key_s1(1'b0), .key_s2(1'b0), .ir_beam(8'hff),.touch_out(pads),
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck), .i2s_lrck(lrck), .i2s_din(din), .touch_scl()
    );
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24564)) monitor (
        .bck(bck), .lrck(lrck), .din(din)
    );
    integer key_index, first, transitions=0;
    reg previous_mode=0, mode_done=0;
    time press_at, gate_at, audio_at, release_at, idle_at, quiet_at;
    time press_at_mode;
    time max_press=0, max_release=0;
    wire voices_idle = dut.touch_active[3:0]==0 &&
                       dut.touch_active[7:4]==0;
    task silence;
        input integer start_sample;
        integer n;
        begin
            for(n=start_sample;n<monitor.pcm_count;n=n+1)
                if(monitor.pcm[n]!=0) $fatal(1,"Unexpected sound after release/key 8 alone");
        end
    endtask
    // Six full frames cover the envelope-to-external-I2S pipeline. Check the
    // subsequent samples, instead of mistaking a sine zero crossing for mute.
    task drain_and_check;
        begin
            first=monitor.pcm_count;
            wait(monitor.pcm_count>=first+6); #1;
            quiet_at=$time; first=monitor.pcm_count;
            wait(monitor.pcm_count>=first+8); #1;
            silence(first);
        end
    endtask
    always @(negedge clk) begin
        if(dut.resetn) begin
            if(dut.fsr_pitch_mode!==previous_mode) begin
                transitions=transitions+1;
                previous_mode=dut.fsr_pitch_mode;
            end
            if(dut.touch_note_gates[7]!==0 || dut.u_output_mix.clipped)
                $fatal(1,"Mode key sounded or production audio clipped");
        end
    end
    // Exercise the real 20ms mode-key path alongside the note keys.
    initial begin
        #7000000;
        @(negedge clk); pads[7]=1; #5000000; pads[7]=0; #3000000;
        if(transitions!=0) $fatal(1,"Short mode-key tap was accepted");
        @(negedge clk); pads[7]=1; press_at_mode=$time;
        wait(dut.fsr_pitch_mode==1);
        if($time-press_at_mode<19000000 || $time-press_at_mode>20000200)
            $fatal(1,"Mode-key confirmation no longer 20 samples");
        #5000000;
        if(transitions!=1) $fatal(1,"Held mode key toggled repeatedly");
        // A release shorter than 20ms must not rearm the mode switch.
        @(negedge clk); pads[7]=0; #2000000; pads[7]=1; #25000000;
        if(transitions!=1) $fatal(1,"Unconfirmed mode release rearmed the switch");
        @(negedge clk); pads[7]=0; #21000000;
        @(negedge clk); pads[7]=1;
        wait(dut.fsr_pitch_mode==0); #100;
        if(transitions!=2) $fatal(1,"Confirmed mode release/second press failed");
        @(negedge clk); pads[7]=0; #21000000;
        mode_done=1;
    end
    initial begin
        // Guard against accidental fixture acceleration or a shared song tail.
        if(dut.TOUCH_DEBOUNCE_MS!=2 || dut.TOUCH_MODE_DEBOUNCE_MS!=20 ||
           dut.ADSR_ATTACK_SAMPLES!=98 || dut.ADSR_DECAY_SAMPLES!=3906 ||
           dut.ADSR_SUSTAIN_LEVEL!=39321 || dut.TOUCH_ADSR_RELEASE_SAMPLES!=488 ||
           dut.ADSR_RELEASE_SAMPLES!=4883)
            $fatal(1,"Test must use production confirmation and ADSR defaults");
        #6000000;
        if(!dut.touch_ready || dut.touch_keys!=0) $fatal(1,"Production readers not ready/idle");
        // Short OUT noise cannot create a gate or a release tail.
        @(negedge clk); pads[0]=1; #300000; pads[0]=0; #2200000;
        if(dut.touch_keys[6:0]!=0) $fatal(1,"Sub-millisecond note pulse accepted");
        silence(0);
        for(key_index=0;key_index<7;key_index=key_index+1) begin
            @(negedge clk); pads[6:0]=7'b1<<key_index; press_at=$time;
            wait(dut.touch_keys[6:0]==pads[6:0]); gate_at=$time;
            if(gate_at-press_at<1000000 || gate_at-press_at>2000100)
                $fatal(1,"Note press did not require two 1ms samples");
            wait(monitor.last_pcm!=0); audio_at=$time;
            if(audio_at-press_at>2300000) $fatal(1,"Production OUT-to-audio exceeds 2.3ms");
            if(audio_at-press_at>max_press) max_press=audio_at-press_at;
            #3000000;
            @(negedge clk); pads[6:0]=0; release_at=$time;
            wait(dut.touch_keys[6:0]==0); gate_at=$time;
            if(gate_at-release_at<1000000 || gate_at-release_at>2000100)
                $fatal(1,"Note release confirmation exceeds two samples");
            wait(voices_idle); idle_at=$time;
            if(idle_at-gate_at<9950000 || idle_at-gate_at>10040000)
                $fatal(1,"Production note release differs from 488 frames");
            drain_and_check;
            if(quiet_at-release_at>12300000) $fatal(1,"Production OUT-to-silence exceeds 12.3ms");
            if(quiet_at-release_at>max_release) max_release=quiet_at-release_at;
            $display("PASS [note %0d response]: OUT-to-first-PCM=%0.6fms, OUT-to-verified-silence=%0.6fms",
                key_index+1,(audio_at-press_at)/1000000.0,(quiet_at-release_at)/1000000.0);
        end
        // Release/retrigger one note without interrupting six held notes.
        @(negedge clk); pads[6:0]=7'h7f;
        wait(dut.touch_keys[6:0]==7'h7f); #3000000;
        @(negedge clk); pads[0]=0;
        wait(dut.touch_keys[6:0]==7'h7e); #2000000;
        if(!dut.touch_active[0]) $fatal(1,"Release cut off abruptly");
        @(negedge clk); pads[0]=1;
        wait(dut.touch_keys[6:0]==7'h7f); #21000;
        if(dut.u_touch_synth.states[2:0]!=1 ||
           dut.touch_active[3:0]!=4'hf || dut.touch_active[7:4]!=4'h7)
            $fatal(1,"Fast retrigger interrupted another held note");
        #3000000;
        @(negedge clk); pads[6:0]=0;
        wait(dut.touch_keys[6:0]==0); wait(voices_idle); drain_and_check;
        wait(mode_done); first=monitor.pcm_count;
        wait(monitor.pcm_count>=first+8); #1; silence(first);
        $display("PASS [production touch response]: seven keys, short noise, independent release/retrigger, 20ms mode key, song release unchanged");
        $display("Measured max OUT-to-first-PCM=%0.6fms, max OUT-to-verified-silence=%0.6fms; %0d stereo frames",
            max_press/1000000.0,max_release/1000000.0,monitor.pair_count);
        $finish;
    end
    initial begin #220000000; $fatal(1,"Production response timeout"); end
endmodule
