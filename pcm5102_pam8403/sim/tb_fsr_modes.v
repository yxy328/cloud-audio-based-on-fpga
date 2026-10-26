`timescale 1ns/1ps
module tb_fsr_modes;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0, ready=0, raw8=1, key8=1, ce=0, valid=0;
    reg [9:0] adc=0;
    reg [15:0] scale_ratio=65535;
    reg scale_ce=1;
    wire pitch_mode;
    wire [15:0] volume_target, volume_gain, pitch_target, pitch_gain;
    wire [255:0] steps;
    integer p, expected, error, previous_volume=65535, previous_pitch=65535;
    integer old_volume, old_pitch, delta, ratio, note;
    reg sampled_ce;
    reg [31:0] base[0:6];
    reg [63:0] expected_product;
    fsr_mode_select mode(.clk(clk),.resetn(resetn),.keys_ready(ready),
        .key8_raw(raw8),.key8_stable(key8),.pitch_mode(pitch_mode));
    fsr_dynamics #(.ADC_INVERT(0),.ADC_FULL(600)) volume(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.expression_enable(!pitch_mode),
        .adc_valid(valid),.adc_sample(adc),.pressure_code(),
        .target_gain(volume_target),.gain(volume_gain));
    fsr_dynamics #(.ADC_INVERT(0),.ADC_FULL(600),.MIN_GAIN(32768)) pitch(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.expression_enable(pitch_mode),
        .adc_valid(valid),.adc_sample(adc),.pressure_code(),
        .target_gain(pitch_target),.gain(pitch_gain));
    fsr_pitch_scaler scaler(.score_ratio(16'd0),.score_keys(7'd0),.bend_min(16'd8192),.bend_max(16'd32768),.bend_slew(16'd4096),.clk(clk),.resetn(resetn),.sample_ce(scale_ce),.pitch_ratio(scale_ratio),
        .note_increments({base[6],base[5],base[4],base[3],base[2],base[1],base[0]}),
        .phase_increments(steps));
    always @(posedge clk) begin
        old_volume=volume_gain; old_pitch=pitch_gain; sampled_ce=ce; #1;
        if(resetn) begin
            delta=volume_gain-old_volume; if(delta<0) delta=-delta;
            if(delta>64 || (!sampled_ce && delta!=0)) $fatal(1,"Volume mode slew/CE violated");
            delta=pitch_gain-old_pitch; if(delta<0) delta=-delta;
            if(delta>64 || (!sampled_ce && delta!=0)) $fatal(1,"Pitch mode slew/CE violated");
        end
    end
    task send_adc;
        input [9:0] value;
        begin
            @(negedge clk); adc=value; valid=1;
            @(negedge clk); valid=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task toggle_mode;
        input wanted;
        begin
            @(negedge clk); raw8=0; key8=0;
            repeat(3) @(negedge clk); raw8=1; key8=1;
            repeat(3) @(negedge clk);
            if(pitch_mode!==wanted) $fatal(1,"Key 8 failed to toggle");
        end
    endtask
    initial begin
        base[0]=23012828; base[1]=25831026; base[2]=28994347;
        base[3]=30718440; base[4]=34480283; base[5]=38702809; base[6]=43442435;
        repeat(4) @(negedge clk); resetn=1;
        repeat(3) @(negedge clk); ready=1;
        repeat(30) @(negedge clk);
        if(pitch_mode!==0) $fatal(1,"Startup-held key 8 toggled mode");
        raw8=0; key8=0; repeat(3) @(negedge clk);
        raw8=1; repeat(3) @(negedge clk); raw8=0;
        if(pitch_mode!==0) $fatal(1,"Undebounced key toggled mode");
        // Both mappings use the same calibrated pressure, even while inactive.
        for(p=0;p<1024;p=p+1) begin
            send_adc(p);
            if(p<=32) expected=65535;
            else if(p>=600) expected=16384;
            else expected=65535-(p-32)*49151/568;
            error=volume_target-expected; if(error<0) error=-error;
            if(error>1 || volume_target>previous_volume) $fatal(1,"Volume mapping error at %0d",p);
            previous_volume=volume_target;
            if(p<=32) expected=65535;
            else if(p>=600) expected=32768;
            else expected=65535-(p-32)*32767/568;
            error=pitch_target-expected; if(error<0) error=-error;
            if(error>1 || pitch_target>previous_pitch) $fatal(1,"Pitch mapping error at %0d",p);
            previous_pitch=pitch_target;
        end
        ce=1; repeat(800) @(negedge clk);
        if(volume_gain!==16384 || pitch_gain!==65535) $fatal(1,"Volume mode endpoints failed");
        // Mode changes consume the last pressure target without a fresh ADC.
        toggle_mode(1); repeat(800) @(negedge clk);
        if(pitch_mode!==1 || volume_gain!==65535 || pitch_gain!==32768)
            $fatal(1,"Pitch mode/long-held key did not preserve mode or reach neutral volume");
        ce=0; toggle_mode(0); repeat(20) @(negedge clk);
        if(volume_gain!==65535 || pitch_gain!==32768) $fatal(1,"Mode changed gain without CE");
        ce=1; repeat(800) @(negedge clk);
        if(volume_gain!==16384 || pitch_gain!==65535) $fatal(1,"Return to volume mode failed");
        send_adc(0); repeat(800) @(negedge clk);
        if(volume_gain!==65535 || pitch_gain!==65535) $fatal(1,"Pressure release did not restore base values");
        // Sweep all usable frequency ratios, checking all seven note steps.
        for(ratio=32768;ratio<=65535;ratio=ratio+1) begin
            @(negedge clk); scale_ratio=ratio;
            repeat(12) @(negedge clk);
            for(note=0;note<7;note=note+1) begin
                expected_product={32'd0,base[note]}*ratio;
                expected=(ratio==65535) ? base[note] : expected_product>>16;
                if(steps[note*32 +: 32]!==expected) $fatal(1,"Pitch step error at ratio=%0d note=%0d",ratio,note+1);
            end
            if(steps[255:224]!==0) $fatal(1,"Key 8 received a pitch step");
        end
        // Rapid full/half transitions also check the bypass pipeline alignment.
        scale_ratio=32768; repeat(12) @(negedge clk);
        if(steps[31:0]!==11506414) $fatal(1,"Low octave endpoint failed");
        scale_ratio=65535; repeat(12) @(negedge clk);
        if(steps[31:0]!==23012828) $fatal(1,"Exact original pitch was not restored");
        // In production the ratio changes ON the audio frame edge. A single
        // pulse must calculate that new ratio for all seven following samples.
        scale_ce=0; repeat(12) @(negedge clk);
        @(negedge clk);scale_ce=1;
        @(posedge clk);scale_ratio<=32768;
        @(negedge clk);scale_ce=0;
        repeat(12) @(negedge clk);
        for(note=0;note<7;note=note+1)
            if(steps[note*32 +: 32]!==base[note]/2)
                $fatal(1,"Frame edge ratio used one frame too late");
        scale_ratio=65535; repeat(20) @(negedge clk);
        if(steps[31:0]!==11506414) $fatal(1,"Scaler ran without an audio frame");
        resetn=0; repeat(3) @(negedge clk);
        if(pitch_mode!==0 || volume_gain!==65535 || pitch_gain!==65535)
            $fatal(1,"Mode/expression reset failed");
        $display("PASS [FSR modes]: startup-held/bounce/long-press key 8, default volume, both calibrated 1024-code mappings, neutral inactive control, switch without fresh ADC, 64-LSB slew/CE/reset; all 32768 ratios for seven notes, exact base/low-octave steps, new ratio on frame edge and idle between frames");
        $finish;
    end
    initial begin #10000000; $fatal(1,"FSR mode test timeout"); end
endmodule
