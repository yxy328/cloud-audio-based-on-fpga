`timescale 1ns/1ps
module tb_top_sensors;
    reg clk=0;
    always #10 clk=~clk;
    reg [7:0] pads=0;
    wire bck, lrck, din, touch_scl;
    tri1 scl, sda;
    top #(.TOUCH_STARTUP_US(100), .TOUCH_DEBOUNCE_MS(2),
          .TOUCH_MODE_DEBOUNCE_MS(2), .ADSR_ATTACK_SAMPLES(4),
          .ADSR_DECAY_SAMPLES(4)) dut (
        .clk(clk), .key_s1(1'b0), .key_s2(1'b0), .touch_out(pads),
        .i2s_bck(bck), .i2s_lrck(lrck), .i2s_din(din),
        .touch_scl(touch_scl), .scl(scl), .sda(sda)
    );
    i2s_pcm_monitor #(.PCM_MIN(-32768), .PCM_MAX(32767)) monitor (
        .bck(bck), .lrck(lrck), .din(din)
    );
    integer k, first_sample, audible;
    always @(negedge clk) begin
        if (dut.resetn && dut.u_output_mix.clipped)
            $fatal(1,"Integrated audio clipped at default gain");
        if (dut.resetn && touch_scl !== 1'b1)
            $fatal(1,"TTP229 serial clock must stay high");
    end
    reg [15:0] light_gain;
    reg [31:0] base_pitch;
    initial begin
        #2000000;
        if (!dut.touch_ready || dut.touch_keys !== 0 || dut.audio_sample !== 0)
            $fatal(1,"Startup/idle failed");
        // A pulse shorter than the two confirmation ticks must be rejected.
        pads=8'h81; #200000; pads=0; #2500000;
        if (dut.touch_keys !== 0 || dut.fsr_pitch_mode !== 0)
            $fatal(1,"Short touch/mode pulse was accepted");
        for (k=0; k<7; k=k+1) begin
            pads=8'h01 << k; #2500000;
            if (dut.touch_note_gates !== pads)
                $fatal(1,"Wrong independent touch gate for key %0d",k+1);
            pads=0; #2500000;
            if (dut.touch_note_gates !== 0)
                $fatal(1,"Touch key did not release");
        end
        pads=7'h7f;
        #3000000;
        if (dut.touch_note_gates !== 8'h7f || dut.touch_mix0 === 0)
            $fatal(1,"Seven touch voices missing");
        light_gain=dut.fsr_gain;
        dut.u_fsr_adc.adc_inst.sim_value=14'd2046;
        #22000000;
        if (dut.fsr_adc_sample !== 1023 || dut.fsr_gain >= light_gain)
            $fatal(1,"ADC to pressure volume path failed");
        base_pitch=dut.touch_phase_increments[31:0];
        pads=8'hff;
        #22000000;
        if (!dut.fsr_pitch_mode || dut.touch_note_gates[7] ||
            dut.touch_phase_increments[31:0] >= base_pitch)
            $fatal(1,"K8 to pressure pitch path failed");
        #3000000;
        if (!dut.fsr_pitch_mode) $fatal(1,"Held K8 toggled repeatedly");
        pads=8'h7f; #3000000; pads=8'hff; #3000000;
        if (dut.fsr_pitch_mode !== 0)
            $fatal(1,"Second K8 press did not restore volume mode");
        // Inject a decoded event at the real sensor controller output;
        // this verifies audio integration, not the physical APDS FIFO.
        force dut.u_gesture.init_done=1;
        force dut.u_gesture.gesture_valid=1;
        force dut.u_gesture.dir_evaluated=1;
        force dut.u_gesture.start_dir=3'd1;
        force dut.u_gesture.end_dir=3'd2;
        #20;
        release dut.u_gesture.gesture_valid;
        first_sample=monitor.pcm_count;
        #8000000;
        if (dut.u_gesture.u_audio.remaining == 0 || dut.gesture_sample === 0)
            $fatal(1,"Gesture event did not reach audio mix");
        if ((^dut.audio_sample) === 1'bx || din === 1'bx)
            $fatal(1,"Unknown integrated audio");
        audible=0;
        for (k=first_sample;k<monitor.pcm_count;k=k+1)
            if (monitor.pcm[k]!=0) audible=audible+1;
        if (audible < 100) $fatal(1,"Mixed PCM did not reach external I2S pins");
        release dut.u_gesture.init_done;
        release dut.u_gesture.dir_evaluated;
        release dut.u_gesture.start_dir;
        release dut.u_gesture.end_dir;
        $display("PASS: touch debounce/7 independent keys/release, ADC volume, K8 pitch/hold/repress, gesture mix, I2S timing/padding/stereo, no clipping; %0d frames",monitor.pair_count);
        $fclose(monitor.capture_file);
        $finish;
    end
    initial begin #130000000; $fatal(1,"Sensor integration timeout"); end
endmodule

