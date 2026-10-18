`timescale 1ns/1ps
module tb_audio_master_volume;
    reg clk=0,resetn=0,frame_ce=0;
    reg signed [15:0] sample_in=0;
    reg [12:0] target=4096;
    wire signed [15:0] sample_out;
    wire [12:0] gain;
    integer i,old_gain,expected;
    always #10 clk=~clk;
    audio_master_volume dut(.clk(clk),.resetn(resetn),.frame_ce(frame_ce),
        .sample_in(sample_in),.target_gain(target),.sample_out(sample_out),.applied_gain(gain));
    task step_frame;
        begin
            @(negedge clk); frame_ce=1;
            @(negedge clk); frame_ce=0;
            repeat(2) @(negedge clk);
        end
    endtask
    task sample_check(input integer pcm);
        begin
            @(negedge clk); sample_in=pcm;
            @(negedge clk);
            expected=(pcm*$signed({1'b0,gain}))>>>12;
            if($signed(sample_out)!==expected)
                $fatal(1,"PCM mismatch: pcm=%0d gain=%0d got=%0d want=%0d",pcm,gain,sample_out,expected);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); resetn=1;
        sample_check(-32768); sample_check(32767); sample_check(-1); sample_check(1);
        // Audio-rate inputs while control changes only on frame boundaries.
        target=0; repeat(20) @(negedge clk);
        if(gain!=4096) $fatal(1,"Gain changed outside stereo frame boundary");
        for(i=0;i<64;i=i+1) begin
            old_gain=gain; step_frame;
            if(gain!=old_gain-64) $fatal(1,"Non-monotonic / excessive fall step");
            sample_check(-32768); sample_check(32767);
        end
        if(gain || sample_out) $fatal(1,"Mute not exact");
        sample_check(-1); sample_check(1);
        target=2051;
        repeat(33) step_frame;
        if(gain!=2051) $fatal(1,"Ramp overshoot or failed convergence");
        for(i=-32768;i<=32767;i=i+257) sample_check(i);
        target=8191;
        repeat(33) step_frame;
        if(gain!=4096) $fatal(1,"Gain above unity was not clamped");
        sample_check(-32768); sample_check(32767);
        target=1000; repeat(10) step_frame;
        target=4096; old_gain=gain; step_frame;
        if(gain!=old_gain+64) $fatal(1,"Reversed pressure ramp discontinuity");
        resetn=0; @(negedge clk);
        if(sample_out || gain!=4096) $fatal(1,"Reset output/gain");
        $display("PASS master volume signed PCM, exact mute/unity, bounded monotonic slew, frame-only updates, reversal and reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Master volume timeout"); end
endmodule
