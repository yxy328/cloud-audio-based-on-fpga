`timescale 1ns/1ps
module tb_touch_pedal_timing;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [9:0] divider=0;
    wire sample_ce=divider==1023;
    always @(posedge clk)divider<=divider+1'b1;
    reg [15:0] gates=0;
    wire [15:0] active;wire [4:0] count;
    wire clipped,overrun;wire signed [15:0] sample;
    integer frame=0,start_frame,segment_frame=0,part=0;
    reg [31:0] previous_phase;
    touch_tdm_synth #(.EXTENDED_CONTROL(1)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.gates(gates),.physical_gates(gates),
        .pedal_mode(2'd2),.poly_limit(5'd16),.low_steps({7{32'd23012828}}),
        .adsr_config({16'd4,16'd4,16'd39321,16'd488}),.pitch_ratio(16'd65535),
        .sample(sample),.active(active),.voice_count(count),.clipped(clipped),.overrun(overrun));
    always @(negedge clk)if(resetn)begin
        if(sample_ce)frame=frame+1;
        if(clipped || overrun)$fatal(1,"Default tail clipping/deadline");
    end
    task next_frame;begin @(negedge sample_ce);wait(dut.state==1);@(negedge clk);end endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        wait(dut.state==1);gates=1;
        repeat(12)next_frame;
        gates=0;next_frame;
        if(dut.contexts[2][2:0]!=5)$fatal(1,"Default tail not entered");
        start_frame=frame;segment_frame=frame;previous_phase=dut.phases[31:0];
        while(active[0])begin
            next_frame;
            if(dut.phases[31:0]-previous_phase!=23012828)$fatal(1,"Default tail phase discontinuity");
            previous_phase=dut.phases[31:0];
            if(dut.contexts[2][6:5]!=part && dut.contexts[2][2:0]==5)begin
                if(frame-segment_frame!=(part<2 ? 14649 : 14648))$fatal(1,"Linked segment duration");
                part=part+1;segment_frame=frame;
            end
        end
        if(frame-start_frame!=58594 || part!=3 || dut.contexts[3]!=0 || count!=0 || sample!=0)
            $fatal(1,"Default tail duration=%0d part=%0d gain=%0d",frame-start_frame,part,dut.contexts[3]);
        $display("PASS default 1200ms pedal: exactly 58594 samples, four linked segments, continuous phase, silence, no overrun/clipping");
        $finish;
    end
    initial begin #1300000000;$fatal(1,"Default tail timeout");end
endmodule
