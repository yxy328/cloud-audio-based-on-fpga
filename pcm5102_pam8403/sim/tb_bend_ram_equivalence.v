`timescale 1ns/1ps
module tb_bend_ram_equivalence;
reg clk=0;always #5 clk=~clk;
reg resetn=0,sample_ce=0,bend_write=0,bend_reset=0;
reg[15:0] pitch_ratio=65535,bend_ratio=16384;reg[2:0]bend_index=0;
reg[223:0] note_increments={32'd43442435,32'd38702809,32'd34480283,32'd30718440,32'd28994347,32'd25831026,32'd23012828};
wire[255:0]phase_increments,expected;
voice_pitch_scaler dut(.bend_min(16'd8192),.bend_max(16'd32768),.bend_slew(16'd4096),.*);
voice_pitch_scaler_reference reference(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),.pitch_ratio(pitch_ratio),.bend_write(bend_write),.bend_reset(bend_reset),.bend_index(bend_index),.bend_ratio(bend_ratio),.note_increments(note_increments),.phase_increments(expected));
integer n,checks=0;reg[31:0]rng=32'h9e3779b9;
always@(negedge clk)if(resetn)begin checks=checks+1;if(phase_increments!==expected)$fatal(1,"bend mismatch cycle=%0d state=%0d index=%0d",checks,dut.state,dut.index);end
initial begin
repeat(5)@(negedge clk);resetn=1;
for(n=0;n<180000;n=n+1)begin
@(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
sample_ce=n%1024==0;bend_write=rng[5:0]<12;bend_index=rng[9:7];bend_ratio=rng[31:16];bend_reset=n%7999==0;
if(n%1024==90)pitch_ratio=rng[15:0];
end
$display("PASS bend memory optimization: %0d cycle comparisons, random writes to all indices, range rejection, resets and frame races",checks);$finish;
end
endmodule
