`timescale 1ns/1ps
// Deliberately abort a busy effect frame and violate the input contract once.
module tb_fx3_reset;
reg clk=0;always #5 clk=~clk;
reg resetn=0,ce=0;
reg signed [15:0] dry=4000;
wire signed [15:0] sample;
wire valid,overrun;
audio_fx_chain dut(.clk(clk),.resetn(resetn),.sample_valid(ce),.dry(dry),.mask(3'd7),.settings(8'hd0),.wet_mix(12'h888),.sample(sample),.valid(valid),.overrun(overrun));
integer n,outputs=0;
always @(negedge clk)if(valid)outputs=outputs+1;
task frame;
begin
    @(negedge clk);ce=1;@(negedge clk);ce=0;
    wait(valid);@(negedge clk);
end
endtask
task reset;
begin
    @(negedge clk);resetn=0;ce=0;
    @(negedge clk);
    if(dut.state!==0 || valid!==0 || sample!==0 || overrun!==0 || dut.cf!==0 || dut.df!==0 || dut.age!==0)$fatal(1,"Synchronous reset failed");
    resetn=1;
end
endtask
initial begin
    repeat(3)@(negedge clk);resetn=1;
    for(n=0;n<5000;n=n+1)frame;
    if(dut.cf!=2048 || dut.df!=4096 || dut.age!=751 || sample<=4000)$fatal(1,"Histories not filled");
    // Reset between accepting a sample and publishing it, during reverb work.
    @(negedge clk);ce=1;@(negedge clk);ce=0;
    wait(dut.state==dut.R_LOAD);reset;
    dry=0;
    for(n=0;n<2500;n=n+1)begin frame;if(sample!==0)$fatal(1,"Stale RAM exposed after reset");end
    @(negedge clk);ce=1;@(negedge clk);ce=0;
    repeat(3)@(negedge clk);ce=1;@(negedge clk);ce=0;
    if(!overrun)$fatal(1,"Input-overrun not detected");
    reset;
    repeat(100)@(negedge clk);
    if(valid || overrun)$fatal(1,"Aborted result leaked");
    $display("PASS FX3 reset during active reverb, filled RAM history invalidation, 2500 silent outputs and sticky overrun/reset");$finish;
end
initial begin #5000000;$fatal(1,"Reset test timeout");end
endmodule
