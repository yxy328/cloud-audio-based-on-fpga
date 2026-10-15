`timescale 1ns/1ps
// Simulation only: run tools/run_sim.ps1. FPGA synthesis top is top.
// synthesis translate_off
module tb_karplus;
    reg clk=0, resetn=0, key=0, ce=0;
    wire signed [15:0] sample;
    geita #(.STRING_LENGTH(110), .DEBOUNCE_CYCLES(4)) dut
        (.clk(clk), .resetn(resetn), .key_s1(key), .sample_ce(ce), .sample(sample), .pluck(1'bz));
    always #10 clk=~clk;
    integer reference [0:109];
    integer i, p, prev, value, avg, mag, expected;
    integer nonzero=0;
    task tick;
        begin
            @(negedge clk); ce=1;
            @(negedge clk); ce=0;
            repeat (2) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        tick;
        if(sample !== 0) $fatal(1,"Startup not silent");
        key=1; repeat(10) @(negedge clk); tick;
        for(i=0;i<110;i=i+1) begin
            tick; reference[i]=$signed(sample);
            if(reference[i]!=16384 && reference[i]!=-16384)
                $fatal(1,"Excitation incorrect");
        end
        prev=reference[109]; p=0;
        // Independent integer recurrence, including signed rounding and loss.
        for(i=0;i<40000;i=i+1) begin
            if(i==100) key=0;
            value=reference[p]; avg=(value+prev)/2;
            mag=(avg<0)?-avg:avg;
            expected=mag-((mag+511)/512);
            reference[p]=(avg<0)?-expected:expected;
            prev=value; p=(p==109)?0:p+1;
            tick;
            if(sample !== value) $fatal(1,"Feedback mismatch at %0d",i);
            if(i<1000 && sample!=0) nonzero=nonzero+1;
        end
        if(nonzero<100) $fatal(1,"No sustained vibration");
        key=1; repeat(10) @(negedge clk); tick;
        if(dut.fill_remaining!=110) $fatal(1,"Retrigger failed");
        tick;
        if(sample!=16384 && sample!=-16384) $fatal(1,"No new excitation");
        $display("PASS: noise, 40000 reference samples, release tail, retrigger");
        $finish;
    end
endmodule
// synthesis translate_on
