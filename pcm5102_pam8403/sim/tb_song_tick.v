`timescale 1ns/1ps
module song_tick_case #(parameter N=5)(input wire clk,resetn);
wire tick;
downloadable_song #(.CLK_HZ(N*1000),.CONTROL_KEYS(12)) dut(
 .clk(clk),.resetn(resetn),.request(1'b0),.operation(3'd0),
 .arg0(16'd0),.arg1(16'd0),.arg2(16'd0),.arg3(16'd0),
 .score_min(16'd8192),.score_max(16'd32768),.score_ratio(),.edit_allowed(1'b1),
 .note_map(96'h47464544434241403f3e3d3c),.toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),.ms_tick(tick));
integer active_clocks=0,pulses=0;
reg expected;
always @(posedge clk)begin
 if(!resetn)active_clocks=0;else active_clocks=active_clocks+1;
 expected=resetn && active_clocks%N==N-1;
 #1;
 if(tick!==expected)$fatal(1,"millisecond phase N%0d clock%0d got%b expected%b",N,active_clocks,tick,expected);
 if(resetn && tick)pulses=pulses+1;
end
endmodule

module tb_song_tick;
reg clk=0;always #10 clk=~clk;
reg resetn=0;
song_tick_case #(1) c1(clk,resetn);
song_tick_case #(2) c2(clk,resetn);
song_tick_case #(3) c3(clk,resetn);
song_tick_case #(17) c17(clk,resetn);
song_tick_case #(50000) production(clk,resetn);
initial begin
 repeat(4)@(negedge clk);resetn=1;
 repeat(100010)@(negedge clk);resetn=0;
 repeat(4)@(negedge clk);resetn=1;
 repeat(100010)@(negedge clk);
 if(production.pulses!=4)$fatal(1,"production tick count %0d",production.pulses);
 $display("PASS song tick: absolute-clock phase N=1/2/3/17/50000,200020 active clocks,two resets,no extra/missing pulses");$finish;
end
endmodule
