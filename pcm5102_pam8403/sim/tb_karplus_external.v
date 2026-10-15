`timescale 1ns/1ps
module tb_karplus_external;
    reg clk=0, resetn=0, key=0, ce=0, pluck=0;
    wire signed [15:0] sample;
    geita #(.STRING_LENGTH(8), .DEBOUNCE_CYCLES(2), .EXTERNAL_TRIGGER(1)) dut (
        .clk(clk), .resetn(resetn), .key_s1(key), .sample_ce(ce),
        .sample(sample), .pluck(pluck)
    );
    always #10 clk=~clk;
    task tick;
        begin
            @(negedge clk); ce=1;
            @(negedge clk); ce=0;
            repeat (2) @(negedge clk);
        end
    endtask
    task pulse_pluck;
        begin
            @(negedge clk); pluck=1;
            @(negedge clk); pluck=0;
        end
    endtask
    integer i, nonzero;
    initial begin
        repeat (4) @(negedge clk); resetn=1;
        // Physical S1 is disconnected in the fused design.
        key=1; repeat (20) @(negedge clk); tick;
        if (dut.pending || dut.fill_remaining || sample !== 0)
            $fatal(1,"Physical key triggered external-only guitar");
        pulse_pluck;
        if (!dut.pending) $fatal(1,"One-clock pluck between frames was lost");
        tick;
        if (dut.fill_remaining !== 8 || dut.pending)
            $fatal(1,"External pluck did not start excitation");
        for (i=0; i<8; i=i+1) begin
            tick;
            if (sample !== 16384 && sample !== -16384)
                $fatal(1,"Incorrect external excitation at %0d",i);
        end
        nonzero=0;
        repeat (40) begin tick; if (sample != 0) nonzero=nonzero+1; end
        if (nonzero < 8 || !dut.active || dut.fill_remaining)
            $fatal(1,"External guitar failed to sustain");
        // A pulse coincident with a frame must survive until it is consumed.
        @(negedge clk); ce=1; pluck=1;
        @(negedge clk); ce=0; pluck=0;
        repeat (2) @(negedge clk);
        if (!dut.pending) $fatal(1,"Frame-coincident pluck was lost");
        tick;
        if (dut.fill_remaining !== 8) $fatal(1,"Frame-coincident retrigger failed");
        repeat (8) tick;
        // Read/feedback occupies a second fabric clock. Capture a trigger then.
        @(negedge clk); ce=1;
        @(negedge clk); ce=0; pluck=1;
        @(negedge clk); pluck=0;
        if (!dut.pending) $fatal(1,"Feedback-cycle pluck was lost");
        tick;
        if (dut.fill_remaining !== 8) $fatal(1,"Feedback-cycle retrigger failed");
        $display("PASS: external guitar ignores S1, captures one-clock/inter-frame/frame/feedback triggers and sustains");
        $finish;
    end
    initial begin #100000; $fatal(1,"External guitar timeout"); end
endmodule
