`timescale 1ns/1ps
// Registered lookup must retain the original PCM value at each audio enable.
module tb_gesture_nco_pipeline;
    reg clk=0, resetn=0;
    always #10 clk=~clk;
    reg [4:0] divider=0;
    always @(posedge clk) divider <= divider==19 ? 0 : divider+1'b1;
    wire sample_ce=divider==19;
    wire signed [15:0] pipelined, reference;
    gesture_nco_sine dut (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .phase_inc(32'd38702432), .sample(pipelined)
    );
    nco_sine #(.INC(32'd38702432)) original (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce), .sample(reference)
    );
    integer samples=0;
    always @(posedge clk) begin
        if (resetn && sample_ce) begin
            if (pipelined !== reference)
                $fatal(1,"Registered sine changed audio-rate PCM at sample %0d",samples);
            samples=samples+1;
            if (samples==1024) begin
                $display("PASS: registered gesture sine matches 1024 original audio-rate samples including phase wrap");
                $finish;
            end
        end
    end
    initial begin #100; @(negedge clk); resetn=1; end
    initial begin #500000; $fatal(1,"NCO comparison timeout"); end
endmodule
